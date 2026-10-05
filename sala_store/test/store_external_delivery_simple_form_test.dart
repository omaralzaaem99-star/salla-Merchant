import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';
import 'package:salla_auth/salla_auth.dart';
import 'package:salla_data/salla_data.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _functionsChannel = BasicMessageChannel<Object?>(
  'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
  StandardMessageCodec(),
);
const _area = <String, Object?>{
  'id': 'mansour',
  'nameAr': 'المنصور',
  'aliases': ['حي المنصور'],
  'immediateFee': 2500,
  'scheduledFee': 5000,
  'distanceKm': 4,
  'pricingAnchor': {'lat': 33.32, 'lng': 44.37},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  final calls = <Map<String, dynamic>>[];
  var deliveryAreas = <Map<String, Object?>>[_area];
  var enabled = true;
  int nextTransitionAtMs = 0;
  Completer<List<Object?>>? configurationCompletion;
  String? quoteFailureCode;
  String? createFailureCode;
  Completer<List<Object?>>? createCompletion;
  StoreOrder? createdOrder;

  setUpAll(() async {
    await Firebase.initializeApp();
    final previewFont = Platform.environment['SALLA_PREVIEW_FONT'];
    if (previewFont != null) {
      final loader = FontLoader('Arial')
        ..addFont(
          File(
            previewFont,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  setUp(() {
    calls.clear();
    deliveryAreas = <Map<String, Object?>>[_area];
    enabled = true;
    nextTransitionAtMs = 0;
    configurationCompletion = null;
    quoteFailureCode = null;
    createFailureCode = null;
    createCompletion = null;
    createdOrder = null;
    SharedPreferences.setMockInitialValues({});
    sallaIdentity = const SallaIdentity(
      uid: 'test-store-user',
      role: SallaUserRole.store,
      entityId: 'test-store',
      name: 'متجر اختبار',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(_functionsChannel, (
          message,
        ) async {
          final arguments = Map<String, dynamic>.from(
            (message! as List).single as Map,
          );
          calls.add(arguments);
          switch (arguments['functionName']) {
            case 'getStoreExternalDeliveryConfiguration':
              if (configurationCompletion != null)
                return configurationCompletion!.future;
              return [
                <String, Object?>{
                  'enabled': enabled,
                  'adminApproved': enabled,
                  'approvalRequired': !enabled,
                  'globalEnabled': true,
                  'storeEnabled': true,
                  'areas': deliveryAreas,
                  'serviceAvailability': {
                    'nextTransitionAtMs': nextTransitionAtMs,
                  },
                },
              ];
            case 'quoteStoreExternalDelivery':
              if (quoteFailureCode != null) {
                return [
                  quoteFailureCode,
                  'مبلغ البضاعة خارج النطاق المسموح.',
                  {
                    'code': quoteFailureCode,
                    'message': 'مبلغ البضاعة خارج النطاق المسموح.',
                    'additionalData': {'reason': 'invalid_integer'},
                  },
                ];
              }
              final payload = Map<String, dynamic>.from(
                arguments['parameters'] as Map,
              );
              final scheduled = payload['serviceType'] != 'immediate';
              final fare = scheduled ? 5000 : 2500;
              return [
                <String, Object?>{
                  'quote': {
                    'quoteFingerprint': 'test-fingerprint',
                    'area': _area,
                    'serviceType': payload['serviceType'],
                    'pricing': {
                      'goodsAmount': payload['goodsAmount'],
                      'deliveryFee': fare,
                      'serviceFee': 250,
                      'customerTotalToCollect':
                          (payload['goodsAmount'] as int) + fare + 250,
                    },
                  },
                },
              ];
            case 'createStoreExternalDelivery':
              if (createCompletion != null) return createCompletion!.future;
              if (createFailureCode == null) {
                fail('Unexpected creation without confirmation');
              }
              return [
                createFailureCode,
                'تغيرت الكروة. راجع الطلب مجدداً.',
                {
                  'code': createFailureCode,
                  'message': 'تغيرت الكروة. راجع الطلب مجدداً.',
                },
              ];
            default:
              fail('Unexpected mutation: ${arguments['functionName']}');
          }
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(_functionsChannel, null);
  });

  Future<void> openForm(
    WidgetTester tester, {
    double width = 412,
    double height = 900,
    double scale = 1,
    SallaGeoPoint? initialPoint,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: Platform.environment['SALLA_PREVIEW_FONT'] != null
              ? 'Arial'
              : null,
          colorScheme: ColorScheme.fromSeed(seedColor: appColor),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const ValueKey('test_screen'),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  createdOrder = await showStoreExternalDeliveryComposer(
                    context,
                    initialDeliveryPoint: initialPoint,
                  );
                },
                child: const Text('افتح النموذج'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح النموذج'));
    await tester.pumpAndSettle();
    expect(find.text('طلب جديد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  Future<void> reveal(WidgetTester tester, String key) async {
    if (key == 'store_external_submit') {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
      return;
    }
    final scroll = find
        .descendant(
          of: find.byKey(const ValueKey('store_external_composer_scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(key)),
      220,
      scrollable: scroll,
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseArea(WidgetTester tester) async {
    await reveal(tester, 'store_external_destination_field');
    await tester.tap(
      find.byKey(const ValueKey('store_external_destination_field')),
    );
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('store_external_area_search'));
    expect(search, findsOneWidget);
    await tester.enterText(search, 'منطقة غير موجودة');
    await tester.pumpAndSettle();
    expect(find.text('لا توجد منطقة مطابقة'), findsOneWidget);
    await tester.tap(find.byTooltip('مسح البحث'));
    await tester.enterText(search, 'حي المنصور');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('store_external_area_mansour')));
    await tester.pumpAndSettle();
  }

  testWidgets('الدبوس يختار أقرب اسم تلقائياً ويرسل معرف التسمية فقط', (
    tester,
  ) async {
    deliveryAreas = [
      {
        ..._area,
        'id': 'far',
        'nameAr': 'المنطقة الأبعد',
        'pricingAnchor': {'lat': 33.50, 'lng': 44.37},
      },
      {
        ..._area,
        'id': 'nearest',
        'nameAr': 'المنطقة الأقرب',
        'pricingAnchor': {'lat': 33.321, 'lng': 44.37},
      },
    ];
    await openForm(tester, initialPoint: const SallaGeoPoint(33.32, 44.37));
    expect(find.text('المنطقة الأقرب'), findsOneWidget);
    expect(find.textContaining('اختير تلقائياً أقرب اسم'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final sent =
        calls.lastWhere(
              (c) => c['functionName'] == 'quoteStoreExternalDelivery',
            )['parameters']
            as Map;
    expect(sent['deliveryLabelAreaId'], 'nearest');
    expect(sent['deliveryLat'], 33.32);
    expect(sent['deliveryLng'], 44.37);
    expect(sent.containsKey('areaId'), isFalse);
    expect(find.text('مراجعة طلب التوصيل'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('تحريك الدبوس يعيد اختيار أقرب اسم تلقائياً', (tester) async {
    const locationChannel = MethodChannel('flutter.baseflow.com/geolocator');
    final gps = Completer<Map<String, dynamic>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, (call) async {
          if (call.method == 'isLocationServiceEnabled') return true;
          if (call.method == 'checkPermission') return 3;
          if (call.method == 'getCurrentPosition') return gps.future;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(locationChannel, null),
    );
    await openForm(tester, initialPoint: const SallaGeoPoint(33.32, 44.37));
    await reveal(tester, 'store_external_map_alternative');
    await tester.tap(
      find.byKey(const ValueKey('store_external_map_alternative')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحديد نقطة دقيقة على الخريطة'));
    await tester.pumpAndSettle();
    final mapFinder = find.byType(FlutterMap);
    expect(mapFinder, findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'map opened');
    await tester.tap(find.byTooltip('موقعي الحالي'));
    await tester.pump();
    await tester.pump();
    final map = tester.widget<FlutterMap>(mapFinder);
    map.options.onPositionChanged!(
      MapCamera(
        crs: const Epsg3857(),
        center: const LatLng(33.33, 44.38),
        zoom: 17,
        rotation: 0,
        nonRotatedSize: const math.Point<double>(400, 600),
      ),
      true,
    );
    gps.complete({
      'latitude': 33.1,
      'longitude': 44.1,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'accuracy': 5.0,
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('اعتماد الموقع للمراجعة'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'map saved');
    expect(find.text('المنصور'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final payload =
        calls.lastWhere(
              (c) => c['functionName'] == 'quoteStoreExternalDelivery',
            )['parameters']
            as Map;
    expect(payload['deliveryLat'], 33.33);
    expect(payload['deliveryLng'], 44.38);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('النموذج البسيط يرتب الموعد أولاً ويبحث ويحدث الملخص دون إنشاء', (
    tester,
  ) async {
    await openForm(tester);
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('store_external_service_selector')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('store_external_customer_fields')),
            )
            .dy,
      ),
    );
    await chooseArea(tester);
    await reveal(tester, 'store_external_goods_field');
    await tester.enterText(
      find.byKey(const ValueKey('store_external_goods_field')),
      '10000',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('store_external_goods_field')),
          )
          .controller!
          .text,
      '10,000',
    );
    await reveal(tester, 'store_external_order_summary');
    final summary = find.byKey(const ValueKey('store_external_order_summary'));
    expect(
      find.descendant(of: summary, matching: find.text(formatIqd(12500))),
      findsOneWidget,
    );
    expect(
      calls.where((c) => c['functionName'] == 'quoteStoreExternalDelivery'),
      isEmpty,
    );
    await reveal(tester, 'store_external_submit');
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('مراجعة طلب التوصيل'), findsOneWidget);
    expect(find.text(formatIqd(12750)), findsOneWidget);
    final quote = calls.singleWhere(
      (c) => c['functionName'] == 'quoteStoreExternalDelivery',
    );
    expect(quote['parameters'], containsPair('areaId', 'mansour'));
    expect(quote['parameters'], containsPair('goodsAmount', 10000));
    expect(quote['parameters'], containsPair('recipientPhone', ''));
    expect(quote['parameters'], isNot(contains('deliveryLat')));
    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    expect(
      calls.where((c) => c['functionName'] == 'createStoreExternalDelivery'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('المجدول يستخدم كروة المنطقة ولا يغيرها بعد البحث', (
    tester,
  ) async {
    await openForm(tester);
    await tester.tap(find.text('مجدول'));
    await tester.pumpAndSettle();
    expect(find.text('خلال 6 ساعات'), findsOneWidget);
    await chooseArea(tester);
    await reveal(tester, 'store_external_goods_field');
    await tester.enterText(
      find.byKey(const ValueKey('store_external_goods_field')),
      '10000',
    );
    await reveal(tester, 'store_external_order_summary');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('store_external_order_summary')),
        matching: find.text(formatIqd(15000)),
      ),
      findsOneWidget,
    );
    await reveal(tester, 'store_external_submit');
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final quote = calls.singleWhere(
      (c) => c['functionName'] == 'quoteStoreExternalDelivery',
    );
    expect(
      quote['parameters'],
      containsPair('serviceType', 'scheduled_flexible_6h'),
    );
    expect((quote['parameters'] as Map)['scheduledFor'], isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('الحقول الناقصة تظهر رسالة وتعيد التركيز ولا تستدعي الخادم', (
    tester,
  ) async {
    await openForm(tester);
    await reveal(tester, 'store_external_goods_field');
    await tester.enterText(
      find.byKey(const ValueKey('store_external_goods_field')),
      '125',
    );
    await reveal(tester, 'store_external_submit');
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pumpAndSettle();
    final goods = tester.widget<TextField>(
      find.byKey(const ValueKey('store_external_goods_field')),
    );
    expect(goods.focusNode!.hasFocus, isTrue);
    expect(goods.decoration!.errorText, contains('مضاعفات 250'));
    await tester.enterText(
      find.byKey(const ValueKey('store_external_goods_field')),
      '',
    );
    await reveal(tester, 'store_external_submit');
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('اختر منطقة التسليم أو حدد موقعاً على الخريطة'),
      findsOneWidget,
    );
    expect(
      calls.where(
        (c) => c['functionName'] != 'getStoreExternalDeliveryConfiguration',
      ),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'النموذج لا يتجاوز شاشة صغيرة بخط كبير ويحافظ على منع غير المعتمد',
    (tester) async {
      enabled = false;
      await openForm(tester, width: 360, height: 640, scale: 1.3);
      await chooseArea(tester);
      await reveal(tester, 'store_external_goods_field');
      await tester.enterText(
        find.byKey(const ValueKey('store_external_goods_field')),
        '10000',
      );
      await reveal(tester, 'store_external_submit');
      await tester.tap(find.byKey(const ValueKey('store_external_submit')));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c['functionName'] == 'quoteStoreExternalDelivery'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('السعر الفارغ يراجع الكروة فقط دون إنشاء الطلب', (tester) async {
    await openForm(tester);
    await chooseArea(tester);
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final quote = calls.singleWhere(
      (c) => c['functionName'] == 'quoteStoreExternalDelivery',
    );
    expect(quote['parameters'], containsPair('goodsAmount', 0));
    expect(find.text('مراجعة طلب التوصيل'), findsOneWidget);
    expect(find.text(formatIqd(2750)), findsOneWidget);
    expect(
      find.textContaining('لا يوجد مبلغ بضاعة يُدفع للمتجر'),
      findsOneWidget,
    );
    expect(
      calls.where((c) => c['functionName'] == 'createStoreExternalDelivery'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('المراجعة ثابتة أثناء التمرير وفوق لوحة المفاتيح', (
    tester,
  ) async {
    await openForm(tester, width: 360, height: 640, scale: 1.3);
    final submit = find.byKey(const ValueKey('store_external_submit'));
    final initial = tester.getRect(submit);
    expect(submit.hitTestable(), findsOneWidget);
    expect(initial.bottom, lessThanOrEqualTo(640));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('store_external_composer_scroll')),
        matching: submit,
      ),
      findsNothing,
    );
    await reveal(tester, 'store_external_note_field');
    expect(tester.getRect(submit), initial);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('رفض المراجعة يظهر السبب الحقيقي ويمكن تصحيحه دون إرسال إنشاء', (
    tester,
  ) async {
    quoteFailureCode = 'invalid-argument';
    await openForm(tester);
    await chooseArea(tester);
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('لم يُنشأ أي طلب. مبلغ البضاعة خارج النطاق المسموح.'),
      findsOneWidget,
    );
    expect(find.textContaining('تثبيت المحاولة محلياً'), findsNothing);
    expect(
      find.byKey(const ValueKey('store_external_submit')).hitTestable(),
      findsOneWidget,
    );
    quoteFailureCode = null;
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('مراجعة طلب التوصيل'), findsOneWidget);
    expect(
      calls.where((c) => c['functionName'] == 'createStoreExternalDelivery'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('تعطل شبكة المراجعة لا يدعي إنشاء طلب أو حفظ معرف محاولة', (
    tester,
  ) async {
    quoteFailureCode = 'unavailable';
    await openForm(tester);
    await chooseArea(tester);
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذر الاتصال لحساب الكروة'), findsOneWidget);
    expect(find.textContaining('احتفظنا بمعرّف'), findsNothing);
    expect(
      calls.where((c) => c['functionName'] == 'createStoreExternalDelivery'),
      isEmpty,
    );
    expect(
      find.byKey(const ValueKey('store_external_submit')).hitTestable(),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final code in ['failed-precondition', 'unavailable']) {
    testWidgets('رفض الإنشاء $code لا يتحول إلى خطأ حفظ محلي', (tester) async {
      createFailureCode = code;
      await openForm(tester);
      await chooseArea(tester);
      await tester.tap(find.byKey(const ValueKey('store_external_submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('إنشاء الطلب'));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c['functionName'] == 'createStoreExternalDelivery'),
        hasLength(1),
      );
      expect(find.textContaining('تعذر حفظ محاولة الطلب'), findsNothing);
      if (code == 'unavailable') {
        expect(find.textContaining('احتفظنا بمعرّف'), findsWidgets);
      } else {
        expect(find.text('تغيرت الكروة. راجع الطلب مجدداً.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('store_external_submit')).hitTestable(),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  Future<Map<String, dynamic>> readSavedAttempts() async =>
      Map<String, dynamic>.from(
        await SallaAuthService.loadLocalRetryIntents(
          role: SallaUserRole.store,
          environment: Firebase.app().options.projectId,
          ownerUid: sallaIdentity.uid,
          namespace: 'store_external_delivery_create_v1',
        ),
      );

  Future<void> startDelayedCreate(
    WidgetTester tester, {
    SallaGeoPoint? initialPoint,
    String? phone,
  }) async {
    createCompletion = Completer<List<Object?>>();
    await openForm(tester, initialPoint: initialPoint);
    await chooseArea(tester);
    if (phone != null) {
      await reveal(tester, 'store_external_phone_field');
      await tester.enterText(
        find.byKey(const ValueKey('store_external_phone_field')),
        phone,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('store_external_phone_field')),
            )
            .controller!
            .text,
        '07712345678',
      );
      await reveal(tester, 'store_external_submit');
    }
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('إنشاء الطلب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  testWidgets('الإرسال البطيء يعرض الانتظار لا تحذيراً ثم يغلق عند النجاح', (
    tester,
  ) async {
    await startDelayedCreate(tester, phone: '٠٧٧١٢٣٤٥٦٧٨');
    final sent =
        calls.singleWhere(
              (c) => c['functionName'] == 'createStoreExternalDelivery',
            )['parameters']
            as Map;
    expect(sent['recipientPhone'], '07712345678');
    expect(
      calls.singleWhere(
        (c) => c['functionName'] == 'quoteStoreExternalDelivery',
      )['parameters'],
      containsPair('recipientPhone', '07712345678'),
    );
    expect(find.text('هناك نتيجة إنشاء غير مؤكدة'), findsNothing);
    expect(find.text('تشخيص حالة المحاولة'), findsNothing);
    expect(find.text('جارٍ إرسال الطلب...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('store_external_create_in_flight')),
      findsOneWidget,
    );
    final saved = await readSavedAttempts();
    expect((saved[storeId] as Map)['payload'], sent);
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pump();
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pump();
    expect(
      calls.where((c) => c['functionName'] == 'createStoreExternalDelivery'),
      hasLength(1),
    );
    createCompletion!.complete([
      {
        'ok': true,
        'orderId': sent['requestId'],
        'order': {'orderSource': 'store_external', 'storeId': storeId},
      },
    ]);
    await tester.pumpAndSettle();
    expect(createdOrder?.databaseKey, sent['requestId']);
    expect(find.byKey(const ValueKey('store_external_submit')), findsNothing);
    expect(await readSavedAttempts(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('النتيجة المجهولة فقط تظهر التحذير وتستعيد نفس المحاولة', (
    tester,
  ) async {
    await startDelayedCreate(
      tester,
      initialPoint: const SallaGeoPoint(33.32, 44.37),
    );
    final sent = Map<String, dynamic>.from(
      calls.singleWhere(
            (c) => c['functionName'] == 'createStoreExternalDelivery',
          )['parameters']
          as Map,
    );
    expect(find.text('هناك نتيجة إنشاء غير مؤكدة'), findsNothing);
    expect(sent['deliveryLabelAreaId'], 'mansour');
    expect(sent.containsKey('areaId'), isFalse);
    createCompletion!.complete([
      'unavailable',
      'Connection lost',
      {'code': 'unavailable', 'message': 'Connection lost'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('هناك نتيجة إنشاء غير مؤكدة'), findsOneWidget);
    expect(find.text('جارٍ إرسال الطلب...'), findsNothing);
    expect(createdOrder, isNull);
    final saved = await readSavedAttempts();
    expect((saved[storeId] as Map)['payload'], sent);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await openForm(tester);
    expect(find.text('هناك نتيجة إنشاء غير مؤكدة'), findsOneWidget);
    expect(find.text('جارٍ إرسال الطلب...'), findsNothing);
    expect(
      calls.where((c) => c['functionName'] == 'createStoreExternalDelivery'),
      hasLength(1),
    );
    // Simulate a persisted, completed read-only diagnosis; replay must use
    // exactly the saved request, not construct a new one after reopening.
    final diagnosed = StoreExternalDeliveryRetryIntent.fromLocal(
      Map<String, dynamic>.from(saved[storeId] as Map),
    ).markDiagnosedAbsent();
    await SallaAuthService.saveLocalRetryIntent(
      role: SallaUserRole.store,
      environment: Firebase.app().options.projectId,
      ownerUid: sallaIdentity.uid,
      namespace: 'store_external_delivery_create_v1',
      intentId: storeId,
      payload: diagnosed.toLocal(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await openForm(tester);
    createCompletion = Completer<List<Object?>>();
    await tester.tap(find.text('إعادة المحاولة نفسها'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('هناك نتيجة إنشاء غير مؤكدة'), findsNothing);
    expect(find.text('جارٍ إرسال الطلب...'), findsOneWidget);
    final replay = calls.lastWhere(
      (c) => c['functionName'] == 'createStoreExternalDelivery',
    );
    expect(replay['parameters'], sent);
    createCompletion!.complete([
      {
        'ok': true,
        'orderId': sent['requestId'],
        'order': {'orderSource': 'store_external', 'storeId': storeId},
      },
    ]);
    await tester.pumpAndSettle();
    expect(createdOrder?.databaseKey, sent['requestId']);
    expect(await readSavedAttempts(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('تحديث إعدادات متأخر لا يمسح محاولة إنشاء الدبوس المعلقة', (
    tester,
  ) async {
    nextTransitionAtMs = DateTime.now().millisecondsSinceEpoch + 10000;
    await openForm(tester, initialPoint: const SallaGeoPoint(33.32, 44.37));
    await chooseArea(tester);
    configurationCompletion = Completer<List<Object?>>();
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    expect(
      calls.where(
        (c) => c['functionName'] == 'getStoreExternalDeliveryConfiguration',
      ),
      hasLength(3),
    );
    createCompletion = Completer<List<Object?>>();
    await tester.tap(find.text('إنشاء الطلب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final sent = calls.singleWhere(
      (c) => c['functionName'] == 'createStoreExternalDelivery',
    )['parameters'];
    configurationCompletion!.complete([
      {
        'enabled': true,
        'adminApproved': true,
        'globalEnabled': true,
        'storeEnabled': true,
        'areas': [_area],
      },
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    createCompletion!.complete([
      'unavailable',
      'lost',
      {'code': 'unavailable', 'message': 'lost'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('هناك نتيجة إنشاء غير مؤكدة'), findsOneWidget);
    expect((await readSavedAttempts())[storeId]['payload'], sent);
    await tester.tap(find.byKey(const ValueKey('store_external_submit')));
    await tester.pumpAndSettle();
    expect(
      calls.where((c) => c['functionName'] == 'createStoreExternalDelivery'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('معاينة مرئية للنموذج من نفس الواجهة الفعلية', (tester) async {
    await openForm(tester);
    if (Platform.environment['SALLA_CAPTURE_FORM'] == '1') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('test_screen')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../backups/store-courier-compact-optional-20260831.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
