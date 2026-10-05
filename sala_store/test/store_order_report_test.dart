import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

Map<String, dynamic> row(
  String key, {
  String status = 'delivered',
  String time = '2026-09-11T10:00:00.000Z',
  int fare = 1000,
}) => {
  'key': key,
  'storeId': 'store-1',
  'orderSource': 'store_external',
  'orderNumber': 'EXT-A1B2C3D4',
  'createdAt': time,
  'status': status,
  'driverStage': status == 'delivered' ? 'delivered' : 'searchingDriver',
  'storeGrossAmount': 10000,
  'subtotal': 10000,
  'deliveryFee': fare,
  'customerTotalToCollect': 10000 + fare + 250,
  'serviceFee': 250,
  'driverId': 'driver-1',
  'driverName': 'أحمد علي',
  'deliveryAreaName': 'المنصور',
  'storeExternalServiceType': 'immediate',
};

Map<String, dynamic> page(
  List<Map<String, dynamic>> rows, {
  Map<String, dynamic>? cursor,
}) => {'orders': rows, 'hasMore': cursor != null, 'nextCursor': cursor};

Widget app(StoreCourierReportLoader loader, {GlobalKey? boundaryKey}) =>
    MaterialApp(
      theme: ThemeData(
        fontFamily: Platform.environment.containsKey('SALLA_REPORT_VISUAL_FONT')
            ? 'ReportVisual'
            : null,
        colorScheme: ColorScheme.fromSeed(seedColor: appColor),
        scaffoldBackgroundColor: bgColor,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(
            color: bgColor,
            child: StoreCourierReport(
              expectedStoreId: 'store-1',
              now: DateTime.utc(2026, 9, 11, 12),
              loadPage: (request) async =>
                  request['action'] == 'report_access_status'
                  ? {'enabled': false, 'revision': 0}
                  : loader(request),
              onOpenOrder: (_) {},
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    '320px layout and larger text remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(app((_) async => page([row('narrow')])));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('نسخ للإدارة'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('نسخ للإدارة'), findsOneWidget);
    },
  );

  setUpAll(() async {
    final fontPath = Platform.environment['SALLA_REPORT_VISUAL_FONT'];
    if (fontPath != null) {
      final loader = FontLoader('ReportVisual')
        ..addFont(
          File(
            fontPath,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
  });
  test(
    'Baghdad boundaries and completed amounts remain separate from cancelled and active',
    () {
      expect(
        storeReportDayKey(
          storeReportBaghdadDate(DateTime.parse('2026-09-10T20:59:59Z')),
        ),
        '2026-09-10',
      );
      expect(
        storeReportDayKey(
          storeReportBaghdadDate(DateTime.parse('2026-09-10T21:00:00Z')),
        ),
        '2026-09-11',
      );
      final delivered = StoreOrder.fromFirebase('a', row('a'));
      final subscription = StoreOrder.fromFirebase('b', row('b', fare: 0));
      final cancelled = StoreOrder.fromFirebase('c', {
        ...row('c'),
        'status': 'cancelled',
      });
      final active = StoreOrder.fromFirebase(
        'd',
        row('d', status: 'preparing'),
      );
      final totals = StoreCourierReportTotals([
        delivered,
        subscription,
        cancelled,
        active,
      ]);
      expect(
        [totals.count, totals.completed, totals.cancelled, totals.active],
        [4, 2, 1, 1],
      );
      expect(totals.goods, 20000);
      final support = storeReportSupportText(delivered);
      expect(support, isNot(contains('كروة')));
      expect(support, isNot(contains('الإجمالي على الزبون')));
      expect(support, isNot(contains('رسم الخدمة')));
      for (final value in [
        'EXT-A1B2C3D4',
        'معرّف الطلب: a',
        'أحمد علي',
        'driver-1',
        'المنصور',
        '2026-09-11',
        '13:00',
      ]) {
        expect(support, contains(value));
      }
      expect(support, isNot(contains('نسبة الشركة')));
    },
  );

  testWidgets(
    'pagination waits for completion, retries same cursor, and deduplicates rows',
    (tester) async {
      final cursor = {
        'mode': 'store_report',
        'createdAt': '2026-09-11T10:00:00.000Z',
        'key': 'a',
      };
      final calls = <Map<String, dynamic>>[];
      var fail = true;
      await tester.pumpWidget(
        app((request) async {
          calls.add(request);
          if (request['cursor'] == null) {
            return page([row('a')], cursor: cursor);
          }
          if (fail) throw TimeoutException('offline');
          return page([row('a'), row('b')]);
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('ملخص الفترة'), findsNothing);
      final list = find.byKey(const ValueKey('courier_report_list'));
      await tester.scrollUntilVisible(
        find.text('إكمال التحميل'),
        180,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      fail = false;
      await tester.tap(find.text('إكمال التحميل'));
      await tester.pumpAndSettle();
      expect(calls.length, 3);
      expect(calls[1]['cursor'], calls[2]['cursor']);
      expect(find.text('ملخص الفترة'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing day discards a late response from the previous day', (
    tester,
  ) async {
    final first = Completer<Map<String, dynamic>>();
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      app((request) {
        calls.add(request);
        if (calls.length == 1) return first.future;
        return Future.value(
          page([row('yesterday', time: '2026-09-10T10:00:00.000Z')]),
        );
      }),
    );
    await tester.pump();
    await tester.tap(find.text('أمس'));
    await tester.pumpAndSettle();
    first.complete(page([row('today')]));
    await tester.pumpAndSettle();
    expect(calls.last['fromDay'], '2026-09-10');
    expect(find.text('2026-09-10  ←  2026-09-10'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('نسخ للإدارة'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2026-09-11'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'number search ignores the selected date and rejects cross-store response',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        app((request) async {
          calls.add(request);
          if (request.containsKey('orderNumber')) {
            return page([
              {...row('private'), 'storeId': 'other'},
            ]);
          }
          return page([]);
        }),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('courier_report_search')),
        'ext-a1b2c3d4',
      );
      await tester.tap(find.byTooltip('بحث عن الطلب'));
      await tester.pumpAndSettle();
      expect(calls.last['orderNumber'], 'EXT-A1B2C3D4');
      expect(calls.last.containsKey('fromDay'), isFalse);
      expect(find.text('ملخص الفترة'), findsNothing);
      expect(find.text('أحمد علي'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow RTL layout renders summary and archived driver without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          (_) async =>
              page([row('order-1'), row('order-0', status: 'cancelled')]),
          boundaryKey: boundary,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ملخص الفترة'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final capture =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final first = await capture.toImage();
        final firstBytes = await first.toByteData(
          format: ui.ImageByteFormat.png,
        );
        final file = File('../.codex_runtime/store-report-summary.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(firstBytes!.buffer.asUint8List());
        first.dispose();
      });
      await tester.scrollUntilVisible(
        find.text('نسخ للإدارة').first,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('السائق الذي سلّم الطلب: أحمد علي'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final second = await capture.toImage();
        final secondBytes = await second.toByteData(
          format: ui.ImageByteFormat.png,
        );
        await File(
          '../.codex_runtime/store-report-orders.png',
        ).writeAsBytes(secondBytes!.buffer.asUint8List());
        second.dispose();
      });
    },
  );
}
