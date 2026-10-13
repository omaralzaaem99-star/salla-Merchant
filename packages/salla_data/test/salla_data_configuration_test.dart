import 'dart:async';
import 'dart:io';

import 'package:salla_data/salla_data.dart';
import 'package:test/test.dart';

void main() {
  group('realtime initial timeout', () {
    test('keeps the source alive and accepts a late first event', () async {
      var sourceCancelled = false;
      final source = StreamController<int>.broadcast(
        onCancel: () => sourceCancelled = true,
      );
      final wrapped = sallaRealtimeWithInitialTimeout<int>(
        source.stream,
        initialTimeout: const Duration(milliseconds: 20),
      );
      final firstError = Completer<Object>();
      final lateValue = Completer<int>();

      final subscription = wrapped.listen(
        (value) {
          if (!lateValue.isCompleted) lateValue.complete(value);
        },
        onError: (Object error) {
          if (!firstError.isCompleted) firstError.complete(error);
        },
      );

      expect(wrapped.isBroadcast, isTrue);
      expect(
        await firstError.future.timeout(const Duration(seconds: 1)),
        isA<TimeoutException>(),
      );

      source.add(17);
      expect(
        await lateValue.future.timeout(const Duration(seconds: 1)),
        17,
      );

      await subscription.cancel();
      expect(sourceCancelled, isTrue);
      await source.close();
    });
  });

  group('SallaDataMode', () {
    test('keeps Firebase as the conservative default', () {
      expect(SallaDataMode.parse(''), SallaDataMode.firebase);
      expect(SallaDataMode.parse('unknown'), SallaDataMode.firebase);
    });

    test('accepts LightNode and shadow aliases', () {
      expect(SallaDataMode.parse('lightnode'), SallaDataMode.api);
      expect(SallaDataMode.parse('shadow'), SallaDataMode.dual);
    });
  });

  group('realtime content signatures', () {
    test('are independent from map insertion order', () {
      final first = {
        'order_b': {'status': 'pending', 'total': 5000},
        'order_a': {'total': 7000, 'status': 'accepted'},
      };
      final second = {
        'order_a': {'status': 'accepted', 'total': 7000},
        'order_b': {'total': 5000, 'status': 'pending'},
      };

      expect(
        sallaCollectionContentSignature(first),
        sallaCollectionContentSignature(second),
      );
    });

    test('can ignore location-only changes in direct child records', () {
      final before = {
        'order_a': {
          'status': 'onTheWay',
          'driverLat': 33.31,
          'driverLng': 44.36,
          'driverLocationUpdatedAt': '2026-07-18T10:00:00.000Z',
        },
      };
      final after = {
        'order_a': {
          'status': 'onTheWay',
          'driverLat': 33.32,
          'driverLng': 44.37,
          'driverLocationUpdatedAt': '2026-07-18T10:00:10.000Z',
        },
      };
      const ignored = {
        'driverLat',
        'driverLng',
        'driverLocationUpdatedAt',
      };

      expect(
        sallaCollectionContentSignature(
          before,
          ignoredRecordKeys: ignored,
        ),
        sallaCollectionContentSignature(
          after,
          ignoredRecordKeys: ignored,
        ),
      );
      expect(
        sallaCollectionContentSignature(before),
        isNot(sallaCollectionContentSignature(after)),
      );
    });

    test('does not hide meaningful fields or nested fields with the same name',
        () {
      final before = {
        'status': 'pending',
        'updatedAt': 'heartbeat-one',
        'audit': {'updatedAt': 'audit-one'},
      };
      final heartbeatOnly = {
        'status': 'pending',
        'updatedAt': 'heartbeat-two',
        'audit': {'updatedAt': 'audit-one'},
      };
      final nestedChange = {
        'status': 'pending',
        'updatedAt': 'heartbeat-two',
        'audit': {'updatedAt': 'audit-two'},
      };

      expect(
        sallaRecordContentSignature(before, ignoredKeys: const {'updatedAt'}),
        sallaRecordContentSignature(
          heartbeatOnly,
          ignoredKeys: const {'updatedAt'},
        ),
      );
      expect(
        sallaRecordContentSignature(before, ignoredKeys: const {'updatedAt'}),
        isNot(
          sallaRecordContentSignature(
            nestedChange,
            ignoredKeys: const {'updatedAt'},
          ),
        ),
      );
    });
  });

  group('query bridge contract', () {
    test('keeps key ordering and inclusive bounds in the shared Query API', () {
      final source = File('lib/salla_data.dart').readAsStringSync();

      expect(source, contains('Query orderByKey()'));
      expect(source, contains('_firebaseQuery.orderByKey()'));
      expect(source, contains('Query startAt(Object? value, {String? key})'));
      expect(source, contains('_firebaseQuery.startAt(value, key: key)'));
      expect(source, contains('Query endAt(Object? value, {String? key})'));
      expect(source, contains('_firebaseQuery.endAt(value, key: key)'));
      expect(source, contains("if (orderByKey) 'orderByKey': true"));
      expect(source, contains("if (hasStartAt) 'startAt': startAt"));
      expect(
          source,
          contains(
            "if (hasStartAt && startAtKey != null) 'startAtKey': startAtKey",
          ));
      expect(source, contains("if (hasEndAt) 'endAt': endAt"));
      expect(
          source,
          contains(
            "if (hasEndAt && endAtKey != null) 'endAtKey': endAtKey",
          ));
    });
  });

  group('driver finance contracts', () {
    test('parses debt and prepaid credit from the signed cash balance', () {
      final debt = SallaDriverFinanceSummary.fromFirebase({
        'version': sallaDriverFinanceLedgerVersion,
        'cashBalance': -125000,
        'earningsBalance': 2000,
        'financeLocked': true,
      });
      final credit = SallaDriverFinanceSummary.fromFirebase({
        'version': sallaDriverFinanceLedgerVersion,
        'cashBalance': 20000,
        'earningsBalance': -5,
      });

      expect(debt.usesGrossCashLedger, isTrue);
      expect(debt.cashDebt, 125000);
      expect(debt.prepaidCredit, 0);
      expect(debt.financeLocked, isTrue);
      expect(credit.cashDebt, 0);
      expect(credit.prepaidCredit, 20000);
      expect(credit.earningsBalance, 0);
    });

    test('keeps signed deltas and order breakdown on ledger entries', () {
      final entry = SallaDriverFinanceEntry.fromFirebase('order_a', {
        'type': 'order_delivered',
        'cashDelta': -6000,
        'earningsDelta': 2000,
        'customerCashCollected': 20500,
        'storeCashPaidByDriver': 14500,
        'driverWage': 2000,
        'companyProfit': 4000,
        'reason': 'خصم إداري موثق',
        'createdByName': 'موظف المالية',
      });

      expect(entry.id, 'order_a');
      expect(entry.cashDelta, -6000);
      expect(entry.earningsDelta, 2000);
      expect(entry.customerCashCollected, 20500);
      expect(entry.storeCashPaidByDriver, 14500);
      expect(entry.driverWage, 2000);
      expect(entry.companyProfit, 4000);
      expect(entry.note, 'خصم إداري موثق');
      expect(entry.actorName, 'موظف المالية');
      expect(entry.affectsCash, isTrue);
      expect(entry.affectsEarnings, isTrue);
    });

    test('supports split fare and bonus fields from server entries', () {
      final entry = SallaDriverFinanceEntry.fromFirebase('order_b', {
        'type': 'order_delivery',
        'driverFare': 1750,
        'bonus': 250,
      });

      expect(entry.driverFare, 1750);
      expect(entry.bonus, 250);
      expect(entry.driverWage, 2000);
    });

    test('keeps direct-courier gross fare when ledger earnings are zero', () {
      final entry = SallaDriverFinanceEntry.fromFirebase('order_direct', {
        'type': 'order_delivery',
        'sourceType': 'order',
        'orderSource': 'store_external',
        'driverFare': 20000,
        'driverWage': 0,
        'earningsDelta': 0,
        'cashDelta': -2000,
      });

      expect(entry.driverFare, 20000);
      expect(entry.driverWage, 0);
      expect(entry.earningsDelta, 0);
    });

    test('keeps the original type on reversal entries', () {
      final entry = SallaDriverFinanceEntry.fromFirebase('reversal_a', {
        'type': 'reversal',
        'reversalOf': 'settlement_a',
        'reversedType': 'earnings_cash_offset',
      });

      expect(entry.reversalOf, 'settlement_a');
      expect(entry.reversedType, 'earnings_cash_offset');
    });
  });

  group('account-bound push notification contract', () {
    test('keeps only the important notification types for each app', () {
      expect(sallaPushTypeIsImportantForRole('driver', 'driver_offer'), isTrue);
      expect(
        sallaPushTypeIsImportantForRole('driver', 'driver_support_reply'),
        isTrue,
      );
      expect(
        sallaPushTypeIsImportantForRole('driver', 'driver_announcement'),
        isTrue,
      );
      expect(
        sallaPushTypeIsImportantForRole('driver', 'driver_payout_paid'),
        isFalse,
      );
      expect(
        sallaPushTypeIsImportantForRole('store', 'store_driver_arrived'),
        isTrue,
      );
      expect(sallaPushTypeIsImportantForRole('store', 'new_order'), isFalse);
      expect(
        sallaPushTypeIsImportantForRole(
          'customer',
          'customer_driver_arrived',
        ),
        isTrue,
      );
      expect(
        sallaPushTypeIsImportantForRole('customer', 'customer_order_update'),
        isFalse,
      );
    });

    test('rejects another account and legacy unbound payloads', () {
      final current = <String, dynamic>{
        'type': 'driver_offer',
        'recipientRole': 'driver',
        'recipientEntityId': 'driver_current',
        'orderId': 'order_1',
      };
      expect(
        sallaPushTargetsCurrentAccount(
          current,
          role: 'driver',
          entityId: 'driver_current',
        ),
        isTrue,
      );
      expect(
        sallaPushTargetsCurrentAccount(
          current,
          role: 'driver',
          entityId: 'driver_old',
        ),
        isFalse,
      );
      expect(
        sallaPushTargetsCurrentAccount(
          {'type': 'driver_offer', 'orderId': 'legacy'},
          role: 'driver',
          entityId: 'driver_current',
        ),
        isFalse,
      );
    });

    test('accepts a driver announcement broadcast for the active role', () {
      expect(
        sallaPushTargetsCurrentAccount(
          {
            'type': 'driver_announcement',
            'recipientRole': 'driver',
            'recipientScope': 'all_drivers',
            'announcementId': 'announcement_1',
          },
          role: 'driver',
          entityId: 'driver_current',
        ),
        isTrue,
      );
    });

    test('deduplicates one logical notification inside the time window', () {
      final deduplicator = SallaPushEventDeduplicator(
        window: const Duration(minutes: 1),
      );
      final payload = <String, dynamic>{
        'type': 'customer_driver_arrived',
        'notificationId': 'arrival_order_1',
      };
      final startedAt = DateTime.utc(2026, 8, 22, 15);
      expect(deduplicator.accept(payload, now: startedAt), isTrue);
      expect(
        deduplicator.accept(
          payload,
          now: startedAt.add(const Duration(seconds: 10)),
        ),
        isFalse,
      );
      expect(
        deduplicator.accept(
          payload,
          now: startedAt.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });
  });
}
