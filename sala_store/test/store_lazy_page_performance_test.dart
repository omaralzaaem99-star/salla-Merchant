import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  testWidgets('يبني صفحة المتجر المرئية فقط', (tester) async {
    final counts = <String, int>{
      'dashboard': 0,
      'orders': 0,
      'products': 0,
      'settings': 0,
    };

    Widget builder(String name) {
      counts[name] = counts[name]! + 1;
      return Text(name);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: buildSelectedStorePage(
          pageIndex: 2,
          dashboardBuilder: () => builder('dashboard'),
          ordersBuilder: () => builder('orders'),
          productsBuilder: () => builder('products'),
          settingsBuilder: () => builder('settings'),
        ),
      ),
    );

    expect(find.text('products'), findsOneWidget);
    expect(counts['products'], 1);
    expect(counts['dashboard'], 0);
    expect(counts['orders'], 0);
    expect(counts['settings'], 0);
  });

  test(
    'تستخدم قائمة المنتجات بناءً كسولاً ولا تنشئ كل البطاقات دفعة واحدة',
    () {
      final source = File(
        'lib/src/pages/store_home_page.dart',
      ).readAsStringSync();
      final start = source.indexOf('  Widget _productsPage()');
      final end = source.indexOf('  Widget _settingsPage()', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      expect(body, contains('ListView.builder('));
      expect(body, contains('itemCount: leading.length + _products.length'));
      expect(body, isNot(contains('..._products.map(')));
    },
  );

  test('تبدأ اتصالات المتجر بعد أول إطار وتجدد الرمز عند التعافي فقط', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    final initStart = source.indexOf('  void initState()');
    final initEnd = source.indexOf(
      '  String get _storeOperationalRetryEnvironment',
      initStart,
    );
    expect(initStart, greaterThanOrEqualTo(0));
    expect(initEnd, greaterThan(initStart));
    final initBody = source.substring(initStart, initEnd);
    final postFrameAt = initBody.indexOf('addPostFrameCallback');
    expect(postFrameAt, greaterThanOrEqualTo(0));
    expect(
      initBody.indexOf('_requestLiveRestart(resetAttempt: true)'),
      greaterThan(postFrameAt),
    );

    final restartStart = source.indexOf(
      'Future<void> _restartLiveSubscriptions',
    );
    final restartEnd = source.indexOf(
      'void _markAllLiveResourcesLoading()',
      restartStart,
    );
    expect(restartStart, greaterThanOrEqualTo(0));
    expect(restartEnd, greaterThan(restartStart));
    final restartBody = source.substring(restartStart, restartEnd);
    expect(restartBody, contains('if (refreshToken)'));
    expect(restartBody, contains('.getIdToken(true)'));
    expect(restartBody, isNot(contains('.getIdToken(refreshToken)')));
  });
}
