import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget links(Future<bool> Function(Uri) open, {bool compact = false}) =>
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: StorePublicLinks(compact: compact, openLink: open),
          ),
        ),
      ),
    );

void main() {
  testWidgets('public links open exact HTTPS pages without account data', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      links((uri) async {
        opened.add(uri);
        return true;
      }),
    );
    for (final label in [
      'سياسة الخصوصية',
      'الدعم',
      'طلب حذف الحساب',
      'شروط الاستخدام',
    ]) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(opened.map((uri) => uri.toString()).toList(), [
      'https://selafood.shop/privacy/',
      'https://selafood.shop/support/',
      'https://selafood.shop/account-deletion/',
      'https://selafood.shop/terms/',
    ]);
  });

  testWidgets('failed opening leaves a selectable URL and permits retry', (
    tester,
  ) async {
    var attempt = 0;
    await tester.pumpWidget(
      links((uri) async {
        if (attempt++ == 0) throw StateError('no browser');
        return true;
      }),
    );
    await tester.tap(find.text('سياسة الخصوصية'));
    await tester.pump();
    expect(find.text('https://selafood.shop/privacy/'), findsOneWidget);
    expect(find.text('نسخ الرابط'), findsOneWidget);
    await tester.tap(find.text('سياسة الخصوصية'));
    await tester.pump();
    expect(find.text('نسخ الرابط'), findsNothing);
    expect(attempt, 2);
  });

  testWidgets('pending open prevents duplicates and survives disposal', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var opens = 0;
    await tester.pumpWidget(
      links((_) {
        opens++;
        return pending.future;
      }),
    );
    await tester.tap(find.text('سياسة الخصوصية'));
    await tester.pump();
    await tester.tap(find.text('الدعم'));
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('links remain usable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: StorePublicLinks(openLink: (_) async => false),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('سياسة الخصوصية'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('store login exposes privacy and support before authentication', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const StoreApp());
    await tester.pumpAndSettle();
    expect(find.text('متجر تجريبي'), findsOneWidget);
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pumpAndSettle();
    expect(find.text('سياسة الخصوصية'), findsOneWidget);
    expect(find.text('الدعم'), findsOneWidget);
    expect(find.text('إنشاء حساب جديد'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
