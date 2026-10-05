import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

Widget report(StoreCourierReportLoader load) => MaterialApp(
  home: Scaffold(
    body: StoreCourierReport(
      expectedStoreId: 'store-1',
      loadPage: load,
      onOpenOrder: (_) {},
    ),
  ),
);

Map<String, dynamic> rows() => {
  'orders': [
    {
      'key': 'a',
      'storeId': 'store-1',
      'orderSource': 'store_external',
      'orderNumber': 'EXT-A1B2C3D4',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'delivered',
      'storeGrossAmount': 10000,
      'deliveryFee': 2000,
      'customerTotalToCollect': 12000,
      'driverName': 'أحمد',
      'deliveryAreaName': 'المنصور',
    },
  ],
  'hasMore': false,
};

void main() {
  testWidgets(
    'protection settings are reachable inside the locked store report and reload access after saving',
    (tester) async {
      var enabled = true;
      var revision = 1;
      var loaded = 0;
      await tester.pumpWidget(
        report((data) async {
          if (data['action'] == 'report_access_status')
            return {'enabled': enabled, 'revision': revision};
          if (data['action'] == 'set_report_access') {
            expect(data['currentPin'], '123456');
            expect(data['enabled'], false);
            enabled = false;
            return {'ok': true, 'enabled': enabled, 'revision': ++revision};
          }
          loaded++;
          return rows();
        }),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('حماية السجل'));
      await tester.pumpAndSettle();
      expect(loaded, 0);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('report_current_pin')),
        '123456',
      );
      await tester.ensureVisible(find.text('حفظ الحماية'));
      await tester.tap(find.text('حفظ الحماية'));
      await tester.pumpAndSettle();
      expect(loaded, 1);
      expect(find.text('قيمة الطلبات'), findsOneWidget);
      expect(find.text('حماية السجل'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'locked report never requests orders before a valid PIN and hides all fares',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        report((data) async {
          requests.add(data);
          if (data['action'] == 'report_access_status')
            return {'enabled': true, 'revision': 1};
          if (data['action'] == 'report_unlock')
            return {
              'enabled': true,
              'revision': 1,
              'reportSession': 'session-token',
              'expiresAt': DateTime.now().millisecondsSinceEpoch + 900000,
            };
          if (data['action'] == 'report_lock') return {'ok': true};
          expect(data['reportSession'], 'session-token');
          return rows();
        }),
      );
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      expect(find.text('قيمة الطلبات'), findsNothing);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('فتح السجل'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r['action'] == null).length, 1);
      expect(find.text('قيمة الطلبات'), findsOneWidget);
      expect(find.textContaining('كرو'), findsNothing);
      expect(find.textContaining('الإجمالي على الزبون'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(requests.last['action'], 'report_lock');
    },
  );

  testWidgets('backgrounding clears loaded data and requires a fresh PIN', (
    tester,
  ) async {
    await tester.pumpWidget(
      report((data) async {
        if (data['action'] == 'report_access_status')
          return {'enabled': true, 'revision': 1};
        if (data['action'] == 'report_unlock')
          return {
            'enabled': true,
            'revision': 1,
            'reportSession': 'token',
            'expiresAt': DateTime.now().millisecondsSinceEpoch + 900000,
          };
        if (data['action'] == 'report_lock') return {'ok': true};
        return rows();
      }),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('فتح السجل'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('قيمة الطلبات'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('فتح السجل'), findsOneWidget);
    expect(find.text('قيمة الطلبات'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'unknown protection status fails closed and retries without loading orders',
    (tester) async {
      var count = 0;
      await tester.pumpWidget(
        report((data) async {
          count++;
          expect(data['action'], 'report_access_status');
          throw StateError('offline');
        }),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('تعذر التحقق'), findsOneWidget);
      expect(find.text('قيمة الطلبات'), findsNothing);
      await tester.tap(find.text('تحديث حالة القفل'));
      await tester.pumpAndSettle();
      expect(count, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unlock response arriving after leaving is revoked and never loads history',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final actions = <String?>[];
      await tester.pumpWidget(
        report((data) async {
          actions.add(data['action'] as String?);
          if (data['action'] == 'report_access_status')
            return {'enabled': true, 'revision': 1};
          if (data['action'] == 'report_unlock') return pending.future;
          return {'ok': true};
        }),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('فتح السجل'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete({
        'enabled': true,
        'revision': 1,
        'reportSession': 'token',
        'expiresAt': DateTime.now().millisecondsSinceEpoch + 900000,
      });
      await tester.pumpAndSettle();
      expect(actions, ['report_access_status', 'report_unlock', 'report_lock']);
      expect(tester.takeException(), isNull);
    },
  );
}
