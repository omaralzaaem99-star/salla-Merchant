import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart' show storeOpenStreetMapAttribution;

void main() {
  test('خرائط المتجر تعرّف التطبيق وتعرض نسبة OpenStreetMap', () {
    final home = File('lib/src/pages/store_home_page.dart').readAsStringSync();
    final external = File(
      'lib/src/pages/store_external_delivery.dart',
    ).readAsStringSync();
    final maps = '$home\n$external';

    expect('TileLayer('.allMatches(maps), hasLength(3));
    expect(
      "userAgentPackageName: 'com.selafood.store'".allMatches(maps),
      hasLength(3),
    );
    expect(home, contains('flutter_map | © OpenStreetMap contributors'));
    expect(home, contains('https://www.openstreetmap.org/copyright'));
    expect(home, contains('LaunchMode.externalApplication'));
    expect('storeOpenStreetMapAttribution()'.allMatches(maps), hasLength(4));
  });

  testWidgets('نسبة OpenStreetMap مرئية في واجهة المتجر', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: storeOpenStreetMapAttribution())),
    );

    expect(
      find.text('flutter_map | © OpenStreetMap contributors'),
      findsOneWidget,
    );
  });
}
