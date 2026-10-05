import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

Widget settings(StoreCourierReportLoader call, VoidCallback close) =>
    MaterialApp(
      home: Scaffold(
        body: StoreReportProtectionSettings(
          expectedStoreId: 'store-1',
          call: call,
          onClose: close,
        ),
      ),
    );

Future<void> typePins(
  WidgetTester tester, {
  String? current,
  String? next,
  String? confirm,
}) async {
  if (current != null)
    await tester.enterText(
      find.byKey(const ValueKey('report_current_pin')),
      current,
    );
  if (next != null)
    await tester.enterText(find.byKey(const ValueKey('report_new_pin')), next);
  if (confirm != null)
    await tester.enterText(
      find.byKey(const ValueKey('report_confirm_pin')),
      confirm,
    );
}

Future<void> save(WidgetTester tester, [String label = 'حفظ الحماية']) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'late save after leaving does not call back into the disposed report',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var closed = 0;
      await tester.pumpWidget(
        settings((data) async {
          if (data['action'] == 'report_access_status')
            return {'enabled': false, 'revision': 0};
          return pending.future;
        }, () => closed++),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await typePins(tester, next: '246810', confirm: '246810');
      await tester.ensureVisible(find.text('حفظ الحماية'));
      await tester.tap(find.text('حفظ الحماية'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete({'ok': true, 'enabled': true, 'revision': 1});
      await tester.pumpAndSettle();
      expect(closed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'store enables its own protection with confirmation and disables only with the current PIN',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      var enabled = false;
      var revision = 0;
      var closed = 0;
      Future<Map<String, dynamic>> call(Map<String, dynamic> data) async {
        if (data['action'] == 'report_access_status')
          return {'enabled': enabled, 'revision': revision};
        calls.add(data);
        enabled = data['enabled'] as bool;
        return {'ok': true, 'enabled': enabled, 'revision': ++revision};
      }

      await tester.pumpWidget(settings(call, () => closed++));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await typePins(tester, next: '123456', confirm: '000000');
      await save(tester);
      expect(calls, isEmpty);
      expect(find.text('تأكيد الرمز الجديد غير مطابق.'), findsOneWidget);
      await typePins(tester, confirm: '123456');
      await save(tester);
      expect(calls.single['storeId'], 'store-1');
      expect(calls.single.containsKey('currentPin'), false);
      expect(closed, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(settings(call, () => closed++));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await save(tester);
      expect(calls.length, 1);
      expect(find.text('أدخل الرمز الحالي من 6 أرقام.'), findsOneWidget);
      await typePins(tester, current: '123456');
      await save(tester);
      expect(calls.last['enabled'], false);
      expect(calls.last['currentPin'], '123456');
      expect(calls.last.containsKey('reportPin'), false);
      expect(closed, 2);
    },
  );

  testWidgets(
    'uncertain save retains exactly the same request and PIN payload across backgrounding',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      var closed = 0;
      await tester.pumpWidget(
        settings((data) async {
          if (data['action'] == 'report_access_status')
            return {'enabled': true, 'revision': 3};
          calls.add(data);
          if (calls.length == 1) throw TimeoutException('lost response');
          return {'ok': true, 'enabled': true, 'revision': 4};
        }, () => closed++),
      );
      await tester.pumpAndSettle();
      await typePins(
        tester,
        current: '123456',
        next: '246810',
        confirm: '246810',
      );
      await save(tester);
      expect(closed, 0);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('report_current_pin')))
            .controller!
            .text,
        isEmpty,
      );
      await save(tester, 'إعادة محاولة الحفظ');
      expect(calls[1], equals(calls[0]));
      expect(closed, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'wrong PIN shows server error and permits correcting it without leaving a busy form',
    (tester) async {
      var attempts = 0;
      var closed = 0;
      await tester.pumpWidget(
        settings((data) async {
          if (data['action'] == 'report_access_status')
            return {'enabled': true, 'revision': 1};
          if (++attempts == 1)
            throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'الرمز الحالي غير صحيح.',
            );
          return {'ok': true, 'enabled': true, 'revision': 2};
        }, () => closed++),
      );
      await tester.pumpAndSettle();
      await typePins(
        tester,
        current: '000000',
        next: '246810',
        confirm: '246810',
      );
      await save(tester);
      expect(find.text('الرمز الحالي غير صحيح.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('report_current_pin')))
            .enabled,
        true,
      );
      await typePins(tester, current: '123456');
      await save(tester);
      expect(closed, 1);
    },
  );

  testWidgets(
    'late settings load after disposal never updates a disposed form',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(settings((_) => pending.future, () {}));
      await tester.pumpWidget(const SizedBox());
      pending.complete({'enabled': false, 'revision': 0});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
