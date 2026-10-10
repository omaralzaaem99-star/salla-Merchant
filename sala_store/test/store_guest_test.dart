import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  testWidgets(
    'pending review refreshes only while visible; approval opens the same account and retries a lost login result',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      var approved = false, activations = 0, opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StorePendingAccountPage(
            receipt: {
              'applicationId': 'a' * 64,
              'applicantUid': 'owner',
              'storeName': 'متجر التجربة',
              'phone': '07775655367',
              'address': 'بغداد المنصور',
            },
            call: (data) async {
              calls.add(Map.of(data));
              return {'ok': true, 'status': approved ? 'approved' : 'pending'};
            },
            activate: (_) async {
              activations++;
              if (activations == 1) throw TimeoutException('unknown login');
            },
            onActivated: () => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('حسابك قيد المراجعة'), findsOneWidget);
      expect(activations, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 61));
      expect(calls.length, 1);
      approved = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(activations, 1);
      expect(opened, 0);
      await tester.scrollUntilVisible(find.text('تحديث حالة الحساب'), 250);
      await tester.pumpAndSettle();
      await tester.tap(find.text('تحديث حالة الحساب'));
      await tester.pumpAndSettle();
      expect(activations, 2);
      expect(opened, 1);
      expect(calls.every((r) => r['applicationId'] == 'a' * 64), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending page tolerates disposal during a read and does not activate after leaving',
    (tester) async {
      final reply = Completer<Map<String, dynamic>>();
      var activated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StorePendingAccountPage(
            receipt: {'applicationId': 'a' * 64},
            call: (_) => reply.future,
            activate: (_) async {
              activated++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      reply.complete({'ok': true, 'status': 'approved'});
      await tester.pumpAndSettle();
      expect(activated, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'guest uses the actual orders home and all filters without operational access',
    (tester) async {
      var apply = 0, login = 0;
      var nativeCalls = 0;
      const shared = MethodChannel('com.selafood.store/shared_location');
      const notifications = MethodChannel('com.selafood.store/notifications');
      for (final channel in [shared, notifications]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async {
            nativeCalls++;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: StoreExplorePage(
            onLogin: () => login++,
            onApply: () => apply++,
          ),
        ),
      );
      expect(find.byType(StoreHomePage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('store_guest_orders_home')),
        findsOneWidget,
      );
      expect(find.text('طلبات المتجر'), findsOneWidget);
      expect(find.text('متجر تجريبي'), findsOneWidget);
      expect(find.text('مفتوح'), findsNothing);
      expect(find.text('تعرّف على سلة'), findsNothing);
      for (final label in [
        'سجل طلب مندوبك',
        'الجديدة',
        'الجاهزة',
        'الإرجاع',
        'المكتملة',
        'الملغاة',
        'النشطة',
      ]) {
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, label));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
              .selected,
          isTrue,
        );
        expect(find.text('لا توجد طلبات في هذا القسم'), findsOneWidget);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(apply, 0);
      expect(login, 0);
      expect(nativeCalls, 0);
      await tester.tap(
        find.byKey(const ValueKey('store_request_your_courier_banner')),
      );
      await tester.pumpAndSettle();
      expect(find.text('استخدم الميزة بحساب متجرك'), findsOneWidget);
      expect(apply, 0);
      await tester.tap(find.widgetWithText(OutlinedButton, 'إنشاء حساب'));
      await tester.pumpAndSettle();
      expect(apply, 1);
      expect(login, 0);
      await tester.tap(find.text('معاينة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
      await tester.pumpAndSettle();
      expect(login, 1);
      await tester.tap(find.byTooltip('المزيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إعدادات المتجر'));
      await tester.pumpAndSettle();
      expect(find.text('استخدم الميزة بحساب متجرك'), findsOneWidget);
      await tester.tap(find.text('متابعة الاستكشاف'));
      await tester.pumpAndSettle();
      expect(find.text('طلبات المتجر'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(nativeCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'validation and persisted retry preserve exact Arabic-normalized submission after reopening',
    (tester) async {
      Map<String, dynamic>? saved;
      final calls = <Map<String, dynamic>>[];
      Widget host() => MaterialApp(
        home: StoreApplicationPage(
          ensureSession: () async => 'applicant',
          load: () async => saved,
          save: (v) async {
            saved = Map.of(v);
          },
          clear: () async {
            saved = null;
          },
          call: (v) async {
            if (v['action'] == 'get_pending_store_account')
              return {'ok': true, 'status': 'pending'};
            calls.add(Map.of(v));
            if (calls.length == 1) throw TimeoutException('lost response');
            return {'ok': true, 'received': true, 'applicationId': 'a' * 64};
          },
        ),
      );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'إنشاء حساب'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'إنشاء حساب'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.enterText(find.byType(TextFormField).at(0), 'متجر التجربة');
      await tester.enterText(find.byType(TextFormField).at(1), '٠٧٧٧٥٦٥٥٣٦٧');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'بغداد المنصور شارع الرواد',
      );
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'إنشاء حساب'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'إنشاء حساب'));
      await tester.pumpAndSettle();
      expect(calls.single['phone'], '07775655367');
      expect(saved, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('إعادة إرسال الطلب نفسه'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إعادة إرسال الطلب نفسه'));
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      expect(calls[1], calls[0]);
      expect(saved?['received'], true);
      expect(saved?['applicantUid'], 'applicant');
      expect(find.text('حسابك قيد المراجعة'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('in-flight submission blocks double tap and survives disposal', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final saved = {
      'action': 'submit_store_application',
      'requestId': 'retry-12345678901234567890',
      'storeName': 'متجر سلة',
      'phone': '07775655367',
      'address': 'بغداد المنصور',
      'consent': true,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: StoreApplicationPage(
          ensureSession: () async => 'applicant',
          load: () async => saved,
          save: (_) async {},
          clear: () async {},
          call: (_) {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete({'ok': true, 'received': true});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
