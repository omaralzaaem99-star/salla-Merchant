import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

Map<String, dynamic> receipt() => {
  'ok': true,
  'request': {
    'id': 'SP-test',
    'storeId': 'store-a',
    'status': 'pending',
    'message': 'تم تسجيل الطلب',
  },
};
Widget page(Future<Map<String, dynamic>> Function(Map<String, dynamic>) call) =>
    MaterialApp(
      home: StorePrivacyRequestPage(storeId: 'store-a', call: call),
    );
Future<void> confirm(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pump();
}

void main() {
  testWidgets('cancel final deletion confirmation performs no write', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      page((data) async {
        if (data['action'] != 'scheduled_privacy_status') writes++;
        return {'ok': true, 'request': null};
      }),
    );
    await tester.pumpAndSettle();
    await confirm(tester);
    await tester.ensureVisible(find.text('حذف الحساب وتسجيل الخروج'));
    await tester.tap(find.text('حذف الحساب وتسجيل الخروج'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد حذف الحساب نهائياً'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();
    expect(writes, 0);
  });
  testWidgets(
    'saved intent survives restart and scheduled receipt signs out once',
    (tester) async {
      final payload = <String, dynamic>{
        'action': 'schedule_privacy_deletion',
        'storeId': 'store-a',
        'requestId': 'original-1234',
        'confirmation': 'DELETE_STORE_ACCOUNT',
        'graceDays': 30,
      };
      var cleared = 0, closed = 0;
      Map<String, dynamic>? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: StorePrivacyRequestPage(
            storeId: 'store-a',
            loadPending: () async => payload,
            savePending: (value) async {
              expect(value, payload);
            },
            clearPending: () async {
              cleared++;
            },
            onScheduled: (_) async {
              closed++;
            },
            call: (value) async {
              if (value['action'] == 'scheduled_privacy_status')
                return {'ok': true, 'request': null};
              sent = value;
              return {
                'ok': true,
                'signOut': true,
                'request': {
                  ...receipt()['request'] as Map,
                  'status': 'scheduled',
                },
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('إعادة محاولة الإرسال'));
      await tester.tap(find.text('إعادة محاولة الإرسال'));
      await tester.pumpAndSettle();
      expect(sent, payload);
      expect(cleared, 1);
      expect(closed, 1);
    },
  );

  testWidgets(
    'pending signup sends its application binding and cannot show another receipt',
    (tester) async {
      Map<String, dynamic>? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: StorePrivacyRequestPage(
            applicationId: 'application-a',
            call: (value) async {
              if (value['action'] == 'scheduled_privacy_status')
                return {'ok': true, 'request': null};
              sent = value;
              return {
                'ok': true,
                'signOut': true,
                'request': {
                  'id': 'SP-other',
                  'applicationId': 'foreign',
                  'status': 'scheduled',
                },
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await confirm(tester);
      await tester.ensureVisible(find.text('حذف الحساب وتسجيل الخروج'));
      await tester.tap(find.text('حذف الحساب وتسجيل الخروج'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('نعم، احذف حسابي نهائياً'));
      await tester.pumpAndSettle();
      expect(sent?['applicationId'], 'application-a');
      expect(sent?.containsKey('storeId'), false);
      expect(find.textContaining('SP-other'), findsNothing);
      expect(find.textContaining('لم يتأكد'), findsOneWidget);
    },
  );

  testWidgets(
    'confirmation required and uncertain request retries identical payload',
    (tester) async {
      final sent = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        page((data) async {
          if (data['action'] == 'scheduled_privacy_status')
            return {'ok': true, 'request': null};
          sent.add(Map.of(data));
          if (sent.length == 1) throw TimeoutException('offline');
          return receipt();
        }),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await confirm(tester);
      await tester.ensureVisible(find.text('حذف الحساب وتسجيل الخروج'));
      await tester.tap(find.text('حذف الحساب وتسجيل الخروج'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('نعم، احذف حسابي نهائياً'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('إعادة محاولة الإرسال'));
      await tester.tap(find.text('إعادة محاولة الإرسال'));
      await tester.pumpAndSettle();
      expect(sent.length, 2);
      expect(sent[1], sent[0]);
      expect(sent[0]['storeId'], 'store-a');
      expect(sent[0]['confirmation'], 'DELETE_STORE_ACCOUNT_NOW');
      expect(sent[0]['graceDays'], 0);
      expect(find.text('رقم المتابعة: SP-test'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    },
  );
  testWidgets(
    'existing request and mismatched reply cannot create or display another request',
    (tester) async {
      await tester.pumpWidget(page((_) async => receipt()));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        page(
          (_) async => {
            'ok': true,
            'request': {
              'id': 'foreign',
              'storeId': 'other',
              'status': 'pending',
            },
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
      expect(find.textContaining('foreign'), findsNothing);
      expect(find.textContaining('تعذر تحميل'), findsOneWidget);
    },
  );
  testWidgets('pending send disables duplicates and is safe after disposal', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    var count = 0;
    await tester.pumpWidget(
      page((data) async {
        if (data['action'] == 'scheduled_privacy_status')
          return {'ok': true, 'request': null};
        count++;
        return pending.future;
      }),
    );
    await tester.pumpAndSettle();
    await confirm(tester);
    await tester.ensureVisible(find.text('حذف الحساب وتسجيل الخروج'));
    await tester.tap(find.text('حذف الحساب وتسجيل الخروج'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نعم، احذف حسابي نهائياً'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(count, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(receipt());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
