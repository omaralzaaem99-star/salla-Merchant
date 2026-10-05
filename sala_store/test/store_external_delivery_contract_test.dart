import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  test('numeric display number preserves the stored request key', () {
    final order = StoreOrder.fromFirebase('external-request-1', {
      'orderSource': 'store_external',
      'orderNumber': '512345678',
      'storeId': 'store-1',
      'status': 'preparing',
      'createdAt': '2026-09-22T10:00:00.000Z',
    });
    expect(order.number, '512345678');
    expect(order.databaseKey, 'external-request-1');
  });
  test('دورة حياة النتيجة غير المؤكدة تحفظ المعرف والحمولة دلالياً', () {
    final original = StoreExternalDeliveryRetryIntent(
      requestId: 'store_external_create_store_123',
      payload: <String, dynamic>{
        'requestId': 'store_external_create_store_123',
        'areaId': 'area-karada',
        'goodsAmount': 25000,
        'serviceType': 'scheduled_0_6h',
        'scheduledFor': '2026-08-13T12:00:00.000Z',
        'recipientPhone': '07700000000',
        'note': 'اتصل عند الوصول',
        'expectedQuoteFingerprint': 'quote-hash',
      },
    );
    final persisted = jsonDecode(jsonEncode(original.toLocal()));
    final restored = StoreExternalDeliveryRetryIntent.fromLocal(
      storeExternalObject(persisted),
    );
    final sameSemanticPayloadDifferentKeyOrder = <String, dynamic>{
      'note': 'اتصل عند الوصول',
      'expectedQuoteFingerprint': 'quote-hash',
      'recipientPhone': '07700000000',
      'scheduledFor': '2026-08-13T12:00:00.000Z',
      'serviceType': 'scheduled_0_6h',
      'goodsAmount': 25000,
      'areaId': 'area-karada',
      'requestId': 'store_external_create_store_123',
    };

    expect(restored.requestId, original.requestId);
    expect(
      restored.matchesPayload(sameSemanticPayloadDifferentKeyOrder),
      isTrue,
    );
    expect(restored.diagnosedAbsent, isFalse);
    final diagnosed = restored.markDiagnosedAbsent();
    expect(diagnosed.requestId, original.requestId);
    expect(diagnosed.payload, original.payload);
    expect(diagnosed.diagnosedAbsent, isTrue);
  });

  test('يرفض سجل إعادة محاولة تغيرت حمولته بعد حفظ بصمته', () {
    final intent = StoreExternalDeliveryRetryIntent(
      requestId: 'request-1',
      payload: <String, dynamic>{'requestId': 'request-1', 'goodsAmount': 250},
    ).toLocal();
    final tampered = <String, dynamic>{
      ...intent,
      'payload': <String, dynamic>{
        'requestId': 'request-1',
        'goodsAmount': 500,
      },
    };
    expect(
      () => StoreExternalDeliveryRetryIntent.fromLocal(tampered),
      throwsFormatException,
    );
  });

  test('طلب المتجر الخارجي يحافظ على القيم الخادمية بلا تقريب', () {
    final order = StoreOrder.fromFirebase('external-1', <String, dynamic>{
      'orderSource': 'store_external',
      'orderNumber': 'EXT-A1B2C3D4',
      'storeId': 'store-1',
      'createdAt': '2026-08-13T10:00:00.000Z',
      'status': 'preparing',
      'storeStage': 'readyForPickup',
      'driverStage': 'searchingDriver',
      'deliveryAreaId': 'area-karada',
      'deliveryAreaName': 'الكرادة',
      'storeExternalServiceType': 'immediate',
      'subtotal': 10000,
      'total': 11250,
      'customerTotalToCollect': 11250,
      'deliveryFee': 1000,
      'serviceFee': 250,
      'storeGrossAmount': 10000,
      'storeCommissionPercent': 0,
      'storeCommissionAmount': 0,
      'storeNetAmount': 10000,
      'driverPaysStoreAmount': 10000,
      'companyShareAmount': 100,
      'driverNetFare': 900,
      'driverCashCustodyAmount': 350,
      'driverCompanyDepositDue': 350,
      'financialLedgerVersion': 'salla_finance_v3_gross_cash',
      'items': const <String, dynamic>{},
    });

    expect(order.isStoreExternal, isTrue);
    expect(
      storeOrderUsesCashRounding(<String, dynamic>{
        'orderSource': 'store_external',
        'paymentProvider': 'cash',
      }, 'preparing'),
      isFalse,
    );
    expect(order.customerTotalToCollect, 11250);
    expect(order.storeNetAmount, 10000);
    expect(order.driverPaysStoreAmount, 10000);
    expect(order.deliveryFee, 1000);
    expect(order.serviceFee, 250);
    expect(order.companyShareAmount, 100);
    expect(order.driverNetFare, 900);
    expect(order.driverCashCustodyAmount, 350);
    expect(order.driverCompanyDepositDue, 350);
  });

  test('سجل المتجر يميز المصدر ويحفظ السائق المرتبط وقت الإلغاء', () {
    final cancelled = StoreOrder.fromFirebase('cancelled-order', {
      'orderSource': 'store_external',
      'orderNumber': 'EXT-CANCELLED',
      'createdAt': '2026-08-14T10:00:00.000Z',
      'status': 'cancelled',
      'storeStage': 'cancelled',
      'driverStage': 'cancelled',
      'driverId': '',
      'driverName': '',
      'cancelledDriverId': 'driver-42',
      'cancelledDriverName': 'سائق الإلغاء',
    });
    final platform = StoreOrder.fromFirebase('platform-order', {
      'orderNumber': '#100001',
      'createdAt': '2026-08-14T11:00:00.000Z',
      'status': 'delivered',
      'driverStage': 'delivered',
      'driverId': 'driver-7',
      'driverName': 'سائق التوصيل',
    });

    expect(cancelled.sourceLabel, 'طلب مندوبك');
    expect(cancelled.responsibleDriverId, 'driver-42');
    expect(cancelled.responsibleDriverName, 'سائق الإلغاء');
    expect(cancelled.responsibleDriverLabel, 'السائق وقت الإلغاء');
    expect(platform.sourceLabel, 'طلب من منصة سلة');
    expect(platform.responsibleDriverName, 'سائق التوصيل');
    expect(platform.responsibleDriverLabel, 'السائق الذي سلّم الطلب');
  });

  test('موقع السائق يظهر للمتجر بعد قبول الطلب الخارجي فقط', () {
    Map<String, dynamic> fixture({
      required String source,
      required String stage,
      double lat = 33.31,
      double lng = 44.41,
    }) => <String, dynamic>{
      'orderSource': source,
      'orderNumber': 'EXT-TRACK-1',
      'createdAt': '2026-08-13T10:00:00.000Z',
      'status': 'preparing',
      'storeStage': 'readyForPickup',
      'driverStage': stage,
      'driverId': 'driver-1',
      'driverName': 'سائق سلة',
      'driverLat': lat,
      'driverLng': lng,
      'driverLocationUpdatedAt': '2026-08-13T10:01:00.000Z',
    };

    final accepted = StoreOrder.fromFirebase(
      'external-track',
      fixture(source: 'store_external', stage: 'accepted'),
    );
    final beforeAcceptance = StoreOrder.fromFirebase(
      'external-searching',
      fixture(source: 'store_external', stage: 'searchingDriver'),
    );
    final customer = StoreOrder.fromFirebase(
      'customer-track',
      fixture(source: '', stage: 'accepted'),
    );
    final invalid = StoreOrder.fromFirebase(
      'external-invalid-location',
      fixture(source: 'store_external', stage: 'accepted', lat: 200),
    );
    final completed = StoreOrder.fromFirebase(
      'external-completed',
      fixture(source: 'store_external', stage: 'delivered'),
    );
    final arrivedStore = StoreOrder.fromFirebase(
      'external-arrived-store',
      fixture(source: 'store_external', stage: 'arrivedStore'),
    );
    final pickedUp = StoreOrder.fromFirebase(
      'external-picked-up',
      fixture(source: 'store_external', stage: 'pickedUp'),
    );
    final detached = StoreOrder.fromFirebase('external-detached', {
      ...fixture(source: 'store_external', stage: 'accepted'),
      'driverId': '',
    });

    expect(accepted.hasTrustedLiveDriverLocation, isTrue);
    expect(arrivedStore.hasTrustedLiveDriverLocation, isTrue);
    expect(pickedUp.hasTrustedLiveDriverLocation, isFalse);
    expect(accepted.driverLocationUpdatedAt, isNotNull);
    expect(beforeAcceptance.hasTrustedLiveDriverLocation, isFalse);
    expect(customer.hasTrustedLiveDriverLocation, isFalse);
    expect(invalid.hasTrustedLiveDriverLocation, isFalse);
    expect(completed.hasTrustedLiveDriverLocation, isFalse);
    expect(detached.hasTrustedLiveDriverLocation, isFalse);
  });

  test('بصمة الطلب الحي تحدث الخارجي فقط عند حركة السائق', () {
    final externalBefore = <String, dynamic>{
      'orderSource': 'store_external',
      'driverId': 'driver-1',
      'driverStage': 'accepted',
      'driverLat': 33.31,
      'driverLng': 44.41,
      'driverLocationUpdatedAt': '2026-08-13T10:01:00.000Z',
      'status': 'preparing',
    };
    final externalAfter = <String, dynamic>{
      ...externalBefore,
      'driverLat': 33.32,
      'driverLocationUpdatedAt': '2026-08-13T10:01:05.000Z',
    };
    final customerBefore = <String, dynamic>{
      ...externalBefore,
      'orderSource': 'customer',
    };
    final customerAfter = <String, dynamic>{
      ...externalAfter,
      'orderSource': 'customer',
    };

    expect(
      storeOperationalOrderContentSignature(externalBefore),
      isNot(storeOperationalOrderContentSignature(externalAfter)),
    );
    expect(
      storeOperationalOrderContentSignature(customerBefore),
      storeOperationalOrderContentSignature(customerAfter),
    );
    expect(
      storeOperationalOrderContentSignature(customerAfter),
      isNot(
        storeOperationalOrderContentSignature(<String, dynamic>{
          ...customerAfter,
          'status': 'cancelled',
        }),
      ),
    );
  });

  test('واجهة المتجر تستخدم callables وتثبت النية قبل أي إنشاء أو إلغاء', () {
    final source = File(
      'lib/src/pages/store_external_delivery.dart',
    ).readAsStringSync();
    final createStart = source.indexOf('Future<void> _quoteAndCreate()');
    final createEnd = source.indexOf(
      'Future<void> _sendCreateIntent',
      createStart,
    );
    final createSection = source.substring(createStart, createEnd);
    final cancelStart = source.indexOf(
      'Future<bool> cancelStoreExternalDeliveryFromStore',
    );
    final cancelSection = source.substring(cancelStart);
    final areaPickerStart = source.indexOf('Future<void> _chooseArea()');
    final areaPickerEnd = source.indexOf(
      'bool _samePrecisePoint',
      areaPickerStart,
    );
    final areaPickerSection = source.substring(areaPickerStart, areaPickerEnd);

    expect(source, contains("'getStoreExternalDeliveryConfiguration'"));
    expect(areaPickerSection, contains('await _refreshAreaConfiguration()'));
    expect(source, contains('Future<StoreExternalDeliveryConfiguration?>'));
    expect(source, contains('_scheduleServiceTransitionRefresh'));
    expect(source, contains('serviceNextTransitionAtMs'));
    expect(source, contains('serviceAvailabilityMessage'));
    expect(source, contains("'quoteStoreExternalDelivery'"));
    expect(source, contains("'store_external_precise_point_immediate_fare'"));
    expect(
      source,
      contains('StoreExternalDeliveryQuote? _precisePointImmediateQuote'),
    );
    expect(source, contains("'goodsAmount': 250"));
    expect(source, contains('الكروة الفورية:'));
    expect(source, contains("'createStoreExternalDelivery'"));
    expect(source, contains("'cancelStoreExternalDelivery'"));
    expect(createSection.indexOf('await _saveIntent(intent)'), greaterThan(0));
    expect(
      createSection.indexOf('await _sendCreateIntent(intent)'),
      greaterThan(createSection.indexOf('await _saveIntent(intent)')),
    );
    expect(
      cancelSection.indexOf('saveLocalRetryIntent'),
      lessThan(cancelSection.indexOf("'cancelStoreExternalDelivery'")),
    );
    expect(
      source,
      contains('scheduled ? area.scheduledFee : area.immediateFee'),
    );
    expect(source, contains('scheduled: _scheduled'));
    expect(source, contains('الكروة حسب نوع الطلب المحدد'));
    expect(source, contains('منطقة التسليم (إلزامي)'));
    expect(source, contains('أو حدد الموقع على الخريطة'));
    expect(source, contains("'deliveryLat': deliveryPoint.lat"));
    expect(source, contains("'deliveryLng': deliveryPoint.lng"));
    expect(source, contains("if (area != null) 'areaId': area.id"));
    expect(source, isNot(contains("'locationMode'")));
    expect(source, contains('لا يوجد راتب آجل'));
    expect(source, isNot(contains('showTimePicker')));
    expect(source, isNot(contains('showDatePicker')));
    expect(source, contains('sallaCourierServiceFlexibleSixHours'));
    expect(source, contains('sallaCourierServiceNextDayTwelveHours'));
    expect(source, contains("Text('خلال 6 ساعات')"));
    expect(source, contains("Text('اليوم التالي • خلال 12 ساعة')"));
    expect(source, contains('قبل رسم الخدمة إن وجد'));
    expect(source, isNot(contains('.set(')));
    expect(source, isNot(contains('.update(')));
  });

  test('منطقة التوصيل تحمل المسافة والكروتين الصادرتين من جدول المتجر', () {
    final area = StoreExternalDeliveryArea.fromMap(<String, dynamic>{
      'id': 'al_karrada',
      'nameAr': 'الكرادة',
      'aliases': <String, bool>{'الكراده': true, 'مهمل': false},
      'distanceKm': 8.437,
      'immediateFee': 3000,
      'scheduledFee': 5000,
    });

    expect(area.id, 'al_karrada');
    expect(area.nameAr, 'الكرادة');
    expect(area.distanceKm, 8.437);
    expect(area.immediateFee, 3000);
    expect(area.scheduledFee, 5000);
    expect(area.matches('الكراده'), isTrue);
    expect(area.matches('الكرادة'), isTrue);
    expect(area.aliases, <String>['الكراده']);
  });

  test('إعداد طلب مندوبك يحتفظ بحالة اعتماد الإدارة', () {
    final configuration = StoreExternalDeliveryConfiguration.fromMap(
      <String, dynamic>{
        'enabled': false,
        'adminApproved': false,
        'approvalRequired': true,
        'globalEnabled': true,
        'storeEnabled': true,
        'serviceAvailability': <String, dynamic>{'enabled': true},
        'areas': const <dynamic>[],
      },
    );

    expect(configuration.adminApproved, isFalse);
    expect(configuration.approvalRequired, isTrue);
    expect(configuration.storeEnabled, isTrue);
  });

  test('اختيار ساعة المجدول يحدد اليوم أو الغد تلقائياً ضمن 12 ساعة', () {
    final sameDay = storeExternalScheduledDateTimeForClock(
      now: DateTime(2026, 8, 14, 10),
      clock: const TimeOfDay(hour: 18, minute: 30),
    );
    final nextDay = storeExternalScheduledDateTimeForClock(
      now: DateTime(2026, 8, 14, 20),
      clock: const TimeOfDay(hour: 1, minute: 30),
    );
    final outsideWindow = storeExternalScheduledDateTimeForClock(
      now: DateTime(2026, 8, 14, 10),
      clock: const TimeOfDay(hour: 23, minute: 0),
    );

    expect(sameDay, DateTime(2026, 8, 14, 18, 30));
    expect(nextDay, DateTime(2026, 8, 15, 1, 30));
    expect(outsideWindow, isNull);
  });

  test('تسميات نوافذ المندوب الجديدة ثابتة مع توافق المجدول القديم', () {
    expect(storeExternalServiceTypeLabel('immediate'), 'فوري');
    expect(
      storeExternalServiceTypeLabel('scheduled_flexible_6h'),
      'خلال 6 ساعات',
    );
    expect(
      storeExternalServiceTypeLabel('scheduled_next_day_12h'),
      'اليوم التالي • خلال 12 ساعة',
    );
    expect(storeExternalServiceTypeLabel('scheduled_0_6h'), 'مجدول');
  });

  test('واجهة التتبع تفتح الموقع من الحقول القائمة بلا جذر مواز', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    expect(source, contains('order.hasTrustedLiveDriverLocation'));
    expect(source, contains('storeOperationalOrderContentSignature'));
    expect(source, contains('تتبع السائق مباشرة'));
    expect(
      source,
      contains('انتهى تتبع اقتراب السائق بعد استلامه الطلب من المتجر.'),
    );
    expect(source, contains('FlutterMap('));
    expect(source, contains('_mapController.move(_driverPoint, 16.25)'));
    expect(source, contains("userAgentPackageName: 'com.selafood.store'"));
    expect(source, contains('watchStorePublicOrder(order.databaseKey)'));
    expect(source, contains("scheme: 'geo'"));
    expect(source, contains('driverLocationUpdatedAt'));
    expect(source, isNot(contains("child('driverLocations')")));
    expect(source, isNot(contains("child('drivers').child(order.driverId)")));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('flutter_map: ^7.0.2'));
    expect(pubspec, contains('latlong2: ^0.9.1'));
  });

  test('قائمة الطلبات تميز الخارجي بصرياً وتبقي البطاقة المشتركة واحدة', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    expect(source, contains('final isExternal = order.isStoreExternal'));
    expect(source, contains('Icons.local_shipping_rounded'));
    expect(source, contains(r'كروة ${formatIqd(order.deliveryFee)}'));
    expect(
      source,
      contains(r'الإجمالي ${formatIqd(order.customerTotalToCollect)}'),
    );
    expect(source, contains('Widget _orderCard(StoreOrder order)'));
    expect(source, contains('Future<void> _copyOrderNumber(StoreOrder order)'));
    expect(source, contains("ClipboardData(text: order.number)"));
    expect(source, contains("'copy_order_number_\${order.databaseKey}'"));
    expect(source, contains("_filterChip('cancelled', 'الملغاة')"));
    expect(source, contains("'store_order_history_summary'"));
    expect(source, contains('return !order.isCancelled && order.isDelivered;'));
    expect(source, contains('return !_isTerminalStoreOrder(order);'));
    expect(source, contains('order.responsibleDriverName'));
    expect(source, contains('order.sourceLabel'));
    expect(
      source,
      contains('storeExternalServiceTypeLabel(order.storeExternalServiceType)'),
    );
    expect(
      source,
      isNot(contains('لا راتب آجل: السائق يحتفظ بصافي الكروة مباشرة.')),
    );
  });

  test('مدخل طلب المندوب بطاقة مستقلة وملخص الطلبات خفيف', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    final bannerStart = source.indexOf('Widget _storeExternalDeliveryBanner()');
    final bannerEnd = source.indexOf(
      'Future<Map<String, String>?> _pendingSharedLocation()',
      bannerStart,
    );
    final bannerSource = source.substring(bannerStart, bannerEnd);

    expect(source, contains("'طلب مندوبك'"));
    expect(source, contains("'store_request_your_courier_banner'"));
    expect(source, contains("'store_pending_network_assignment'"));
    expect(bannerSource, contains('if (_networkAssignmentPending)'));
    expect(
      bannerSource,
      contains('ستتمكن من إنشاء طلب مندوبك بعد أن تعيّن الإدارة'),
    );
    expect(source, contains('Widget _storeExternalDeliveryBanner()'));
    expect(source, isNot(contains('_storeExternalDeliveryCompactBanner')));
    expect(source, contains('_pageIndex == 0 || _pageIndex == 1'));
    expect(source, contains("'store_orders_compact_summary'"));
    expect(source, contains("'فوري حسب المسافة'"));
    expect(source, contains("'مجدول 5,000'"));
    expect(source, contains('_openStoreExternalDelivery'));
    expect(source, isNot(contains('FloatingActionButton.extended')));
    expect(bannerSource, contains('Color(0xFF0F8F80)'));
    expect(bannerSource, contains('Color(0xFF0B5F68)'));
    expect(bannerSource, contains('height: 86'));
    expect(bannerSource, contains('width: 54'));
    expect(bannerSource, contains('fontSize: 19'));
    expect(source, contains("'com.selafood.store/shared_location'"));
    expect(source, contains('sallaResolveSharedLocationText(source)'));
    expect(source, contains('onInitialDeliveryPointApplied'));
  });

  test('نموذج طلب المندوب مبسط والموعد أعلى الحقول مع مراجعة واضحة', () {
    final source = File(
      'lib/src/pages/store_external_delivery.dart',
    ).readAsStringSync();

    expect(source, contains("'store_external_composer_header'"));
    expect(source, isNot(contains("'store_external_steps_overview'")));
    expect(source, contains("'store_external_customer_fields'"));
    expect(source, contains("'store_external_service_selector'"));
    expect(source, contains("'store_external_order_summary'"));
    expect(source, contains("'store_external_step_goods'"));
    expect(source, contains("'store_external_step_area'"));
    expect(source, contains("'store_external_step_schedule'"));
    expect(source, contains("'store_external_phone_field'"));
    expect(source, contains("'store_external_review_panel'"));
    expect(source, contains("'store_external_review_validation_message'"));
    expect(source, contains("'store_external_submit'"));
    expect(source, contains("'اطلب مندوبك'"));
    expect(source, contains("'راجع الكروة والطلب'"));
    expect(source, contains("'سعر الطلب (اختياري)'"));
    // Optional/empty amounts and formatted numeric payloads are exercised by
    // store_external_delivery_simple_form_test, independently of parser syntax.
    expect(source, contains("'املأ حقل «موقع التسليم»"));
    expect(source, contains('liveRegion: true'));
    expect(
      source,
      contains('setState(() => _draftValidationMessage = message)'),
    );
    expect(source, isNot(contains('required int step')));
    expect(source, contains('Scrollable.ensureVisible('));
    expect(source, contains('focusNode: _goodsFocusNode'));
    expect(source, contains('final draft = await _validatedDraft()'));
    expect(source, contains('configuration != null'));
    expect(source, isNot(contains('configuration?.enabled == true')));
  });

  test('استيراد موقع Android يبقى معلقاً حتى المراجعة ولا ينشئ طلباً', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/salla/sala_store/MainActivity.kt',
    ).readAsStringSync();
    final home = File('lib/src/pages/store_home_page.dart').readAsStringSync();

    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android:scheme="geo"'));
    expect(manifest, contains('android:scheme="google.navigation"'));
    expect(manifest, contains('android:host="maps.app.goo.gl"'));
    expect(
      manifest,
      contains('android:host="goo.gl" android:pathPrefix="/maps/"'),
    );
    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android:mimeType="text/plain"'));
    expect(manifest, contains('android:launchMode="singleTask"'));
    expect(manifest, isNot(contains('android:launchMode="singleTop"')));
    expect(activity, contains('override fun onNewIntent(intent: Intent)'));
    expect(activity, contains('"peekPending"'));
    expect(activity, contains('"ackPending"'));
    expect(activity, contains('sharedLocationQueueKey'));
    expect(home, contains('initialDeliveryPoint: point'));
    expect(home, contains('_StoreExternalDeliveryMapPickerPage('));
    expect(home, contains('لم يعتمد موقع المستلم، ولم يُنشأ أي طلب.'));
    expect(home, contains('onInitialDeliveryPointApplied'));
    expect(home, contains('_ackSharedLocation(sharedLocationId)'));
    expect(home, isNot(contains("invokeMethod('createStoreExternalDelivery'")));
  });
}
