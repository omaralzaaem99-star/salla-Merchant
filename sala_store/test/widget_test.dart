import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';
import 'package:salla_auth/salla_auth.dart';

void main() {
  setUp(() {
    sallaIdentity = const SallaIdentity(
      uid: 'store-test-user',
      role: SallaUserRole.store,
      entityId: 'store-test',
      name: 'متجر اختبار باسم طويل',
    );
  });

  test('store application can be constructed', () {
    expect(const StoreApp(), isNotNull);
  });

  test('حالة رأس المتجر تفصل طلب مندوبك عن سوق الزبائن', () {
    expect(
      storeReadyHeaderStatusLabel(
        storeStatus: 'active',
        storeLockedByAdmin: false,
        networkAssignmentPending: false,
        customerZoneMode: 'hidden',
        storeExternalDeliveryEnabled: true,
        online: false,
      ),
      'متاح لطلب مندوبك',
    );
    expect(
      storeReadyHeaderStatusLabel(
        storeStatus: 'paused',
        storeLockedByAdmin: true,
        networkAssignmentPending: false,
        customerZoneMode: 'hidden',
        storeExternalDeliveryEnabled: true,
        online: false,
      ),
      'طلب مندوبك بانتظار اعتماد الإدارة',
    );
    expect(
      storeReadyHeaderStatusLabel(
        storeStatus: 'paused',
        storeLockedByAdmin: true,
        networkAssignmentPending: false,
        customerZoneMode: 'normal',
        storeExternalDeliveryEnabled: false,
        online: false,
      ),
      'موقوف من الإدارة',
    );
  });

  test('store order model keeps the trusted geographic snapshot', () {
    final order = StoreOrder.fromFirebase('order-network', {
      'orderNumber': '#100001',
      'createdAt': '2026-07-26T10:00:00.000Z',
      'provinceId': 'province-baghdad',
      'provinceName': 'بغداد',
      'branchId': 'branch-mansour',
      'branchName': 'المنصور',
      'serviceZoneId': 'zone-store-home',
      'serviceZoneName': 'زون المتجر',
      'deliveryZoneId': 'zone-customer',
      'deliveryZoneName': 'زون الزبون',
      'items': const <String, dynamic>{},
    });

    expect(order.provinceId, 'province-baghdad');
    expect(order.branchId, 'branch-mansour');
    expect(order.serviceZoneId, 'zone-store-home');
    expect(order.deliveryZoneId, 'zone-customer');
  });

  test(
    'orders subscribe after store authentication to the store live source',
    () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final pageSource = File(
        'lib/src/pages/store_home_page.dart',
      ).readAsStringSync();
      final identityAssignment = mainSource.indexOf(
        'sallaIdentity = identity;',
      );
      final storePageConstruction = mainSource.indexOf(
        'child: StoreHomePage()',
        identityAssignment,
      );
      final listenerStart = pageSource.indexOf('void _listenToOrders()');
      final listenerEnd = pageSource.indexOf(
        'Future<void> _configurePushNotifications()',
        listenerStart,
      );

      expect(identityAssignment, greaterThanOrEqualTo(0));
      expect(storePageConstruction, greaterThan(identityAssignment));
      expect(listenerStart, greaterThanOrEqualTo(0));
      expect(listenerEnd, greaterThan(listenerStart));

      final listenerSource = pageSource.substring(listenerStart, listenerEnd);
      expect(listenerSource, isNot(contains(".child('orders')")));
      expect(listenerSource, contains("(entry.value as Map)['publicOrder']"));
      expect(listenerSource, contains('.limitToLast(150)'));
      expect(listenerSource, contains(".child('operationalOrderRefs')"));
      expect(listenerSource, contains(".child('stores')"));
      expect(listenerSource, contains('.child(storeId)'));
      expect(
        listenerSource,
        contains("_listenToOperationalOrder(orderId, generation)"),
      );
      expect(listenerSource, contains('.onValue'));
    },
  );

  test('deferred settlement ignores stale driver cash amount', () {
    final deferredOrder = _sampleOrder(
      settlementMode: deferredStoreSettlementMode,
      driverPaysStoreAmount: 5750,
    );
    final directOrder = _sampleOrder(
      key: 'direct-order',
      settlementMode: directStoreSettlementMode,
      driverPaysStoreAmount: 5750,
    );

    expect(deferredOrder.usesDeferredSettlement, isTrue);
    expect(deferredOrder.driverPaysStoreAmount, 0);
    expect(deferredOrder.requiresDriverCashPayment, isFalse);

    expect(directOrder.usesDeferredSettlement, isFalse);
    expect(directOrder.driverPaysStoreAmount, 5750);
    expect(directOrder.requiresDriverCashPayment, isTrue);
  });

  test('returned deferred compensation remains a store settlement record', () {
    final order = StoreOrder.fromFirebase('returned-order', {
      'orderNumber': '#900001',
      'storeId': 'store-test',
      'status': 'cancelled',
      'storeStage': 'cancelled',
      'driverStage': 'cancelled',
      'storeSettlementMode': deferredStoreSettlementMode,
      'storeSettlementStatus': 'pending',
      'cancellationStage': 'financial_resolved',
      'goodsDisposition': 'returned_to_store',
      'storeCancellationPayableAmount': 4250,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'items': const [],
    });

    expect(order.returnedCancellationPayable, isTrue);
    expect(order.isStoreSettlementRecord, isTrue);
    expect(order.storeSettlementDisplayAmount, 4250);
    expect(order.storeSettlementPaid, isFalse);
  });

  test('store item lists and receipt hide item prices', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();

    final prepItemsStart = source.indexOf(
      'Widget itemTile(StoreOrderItem item)',
    );
    final prepItemsEnd = source.indexOf(
      'Widget prepDurationCard()',
      prepItemsStart,
    );
    final receiptStart = source.indexOf(
      'Future<Uint8List> _buildOrderReceiptPdf',
    );
    final receiptEnd = source.indexOf(
      'void _showOrderDetails(StoreOrder order)',
      receiptStart,
    );
    final detailsStart = receiptEnd;
    final detailsEnd = source.indexOf(
      'Widget _liveDriverCard(StoreOrder order)',
      detailsStart,
    );

    expect(prepItemsStart, greaterThanOrEqualTo(0));
    expect(prepItemsEnd, greaterThan(prepItemsStart));
    expect(receiptStart, greaterThanOrEqualTo(0));
    expect(receiptEnd, greaterThan(receiptStart));
    expect(detailsEnd, greaterThan(detailsStart));

    final prepItemsSource = source.substring(prepItemsStart, prepItemsEnd);
    final receiptSource = source.substring(receiptStart, receiptEnd);
    final detailsSource = source.substring(detailsStart, detailsEnd);

    expect(prepItemsSource, isNot(contains('item.lineTotal')));
    expect(detailsSource, isNot(contains('item.lineTotal')));
    expect(receiptSource, isNot(contains('item.lineTotal')));
    expect(receiptSource, isNot(contains('مجموع الأصناف')));
    expect(receiptSource, contains('...order.items.map(_pdfOrderItem)'));
    expect(receiptSource, contains("'المبلغ المطلوب من السائق'"));
    expect(detailsSource, contains('driverSettlementCard(currentOrder)'));
  });

  test('direct payment wording follows the existing store confirmation', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    final receiptStart = source.indexOf(
      'Future<Uint8List> _buildOrderReceiptPdf',
    );
    final receiptEnd = source.indexOf(
      'void _showOrderDetails(StoreOrder order)',
      receiptStart,
    );
    final settlementCardStart = source.indexOf(
      'Widget driverSettlementCard(StoreOrder order)',
    );
    final settlementCardEnd = source.indexOf(
      'Widget driverPaymentConfirmationCard(StoreOrder order)',
      settlementCardStart,
    );

    expect(receiptStart, greaterThanOrEqualTo(0));
    expect(receiptEnd, greaterThan(receiptStart));
    expect(settlementCardStart, greaterThanOrEqualTo(0));
    expect(settlementCardEnd, greaterThan(settlementCardStart));

    final receiptSource = source.substring(receiptStart, receiptEnd);
    final settlementCardSource = source.substring(
      settlementCardStart,
      settlementCardEnd,
    );

    for (final section in [receiptSource, settlementCardSource]) {
      expect(section, contains('order.usesDeferredSettlement'));
      expect(section, contains("'دفع آجل مع الشركة'"));
      expect(
        section,
        contains('order.storePaymentConfirmedAt.trim().isNotEmpty'),
      );
      expect(section, contains("'المبلغ المطلوب من السائق'"));
      expect(section, contains("'المبلغ المستلم من السائق'"));
    }
  });

  test('store dues use the complete trusted settlement preview', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    final loaderStart = source.indexOf(
      'Future<void> _loadStoreSettlementPreview()',
    );
    final loaderEnd = source.indexOf(
      'List<StoreOrder> get _deliveredSettlementOrders',
      loaderStart,
    );
    final financeStart = source.indexOf('Widget _storeFinanceSummary()');
    final financeEnd = source.indexOf(
      'Widget _settlementOrderHint(',
      financeStart,
    );

    expect(loaderStart, greaterThanOrEqualTo(0));
    expect(loaderEnd, greaterThan(loaderStart));
    expect(financeStart, greaterThanOrEqualTo(0));
    expect(financeEnd, greaterThan(financeStart));

    final loader = source.substring(loaderStart, loaderEnd);
    final finance = source.substring(financeStart, financeEnd);
    expect(loader, contains('.httpsCallable('));
    expect(loader, contains("'settleStoreDues'"));
    expect(loader, contains("'action': 'preview'"));
    expect(loader, contains("'storeId': storeId"));
    expect(loader, contains("rawPreview['settledAmount']"));
    expect(loader, contains("rawPreview['settledOrderCount']"));
    expect(finance, contains('الرصيد من السجل الكامل'));
    expect(
      finance,
      contains('تعذر تحميل الرصيد الكامل؛ المعروض مؤقتاً من أحدث الطلبات.'),
    );
  });

  test('returns are server backed and employee names stay out of store UI', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();

    expect(source, contains("httpsCallable('confirmDeferredOrderReturn')"));
    expect(
      source,
      contains('if (_busy || !order.usesDeferredSettlement) return;'),
    );
    expect(
      source,
      contains(
        'هذا طلب دفع مباشر، وتتم معالجة رفض الزبون مالياً من الإدارة من دون إرجاع للمتجر.',
      ),
    );
    expect(source, isNot(contains('order.storePaymentConfirmedBy')));
    expect(source, isNot(contains('currentOrder.storePaymentConfirmedBy')));
  });

  test('store order stages and cash confirmation use the trusted callable', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    final actionsStart = source.indexOf(
      'Future<StoreOrder?> _performStoreOrderAction(',
    );
    final actionsEnd = source.indexOf('Future<void> _setOnline(', actionsStart);

    expect(actionsStart, greaterThanOrEqualTo(0));
    expect(actionsEnd, greaterThan(actionsStart));

    final actionsSource = source.substring(actionsStart, actionsEnd);
    expect(actionsSource, contains('.httpsCallable('));
    expect(actionsSource, contains("'performStoreOrderAction'"));
    expect(actionsSource, contains("'expectedUpdatedAt': expectedUpdatedAt"));
    expect(actionsSource, contains("'requestId': _storeOrderActionRequestId"));
    expect(actionsSource, contains("'confirm_driver_payment'"));
    expect(actionsSource, isNot(contains('runTransaction(')));
    expect(actionsSource, isNot(contains("child('auditLogs')")));
    expect(actionsSource, isNot(contains('_sendNotification(')));
  });

  test(
    'store availability uses the trusted callable and preserves admin lock',
    () {
      final source = File(
        'lib/src/pages/store_home_page.dart',
      ).readAsStringSync();
      final profileStart = source.indexOf('Future<void> _ensureStoreProfile()');
      final profileEnd = source.indexOf(
        'Future<void> _syncPublicCatalog(',
        profileStart,
      );
      final statusStart = source.indexOf('Future<void> _setOnline(');
      final statusEnd = source.indexOf(
        'Future<void> _setPrepMinutes(',
        statusStart,
      );

      expect(profileStart, greaterThanOrEqualTo(0));
      expect(profileEnd, greaterThan(profileStart));
      expect(statusStart, greaterThanOrEqualTo(0));
      expect(statusEnd, greaterThan(statusStart));

      final profileSource = source.substring(profileStart, profileEnd);
      final statusSource = source.substring(statusStart, statusEnd);
      expect(profileSource, contains('storeRef.get()'));
      expect(profileSource, isNot(contains('runTransaction(')));
      expect(profileSource, contains("data['id']"));
      expect(profileSource, contains("data['authUid']"));
      expect(profileSource, contains("data['active'] != true"));
      expect(profileSource, contains("'stores/\$storeId/prepMinutes'"));
      expect(profileSource, contains("'stores/\$storeId/autoDispatchEnabled'"));
      expect(profileSource, contains("'stores/\$storeId/dispatchLeadMinutes'"));
      expect(profileSource, isNot(contains("data['products']")));
      expect(profileSource, isNot(contains("data['authUid'] =")));
      expect(profileSource, isNot(contains("data['id'] =")));
      expect(profileSource, isNot(contains("data['isOnline']")));
      expect(profileSource, isNot(contains("data['acceptingOrders']")));
      expect(statusSource, contains("'setStoreOperationalAvailability'"));
      expect(
        statusSource,
        contains("final requestedAction = value ? 'open' : 'close'"),
      );
      expect(
        statusSource,
        contains('_pendingStoreOperationalRequestIds.keys.first'),
      );
      expect(
        statusSource,
        contains('_pendingStoreOperationalRequestIds.putIfAbsent'),
      );
      expect(statusSource, contains("'action': action"));
      expect(statusSource, contains("'requestId': requestId"));
      expect(
        statusSource,
        contains('جارٍ استكمال مزامنة فتح المتجر السابقة أولاً'),
      );
      final callableIndex = statusSource.indexOf('await callable.call');
      final persistIndex = statusSource.indexOf(
        'await _persistStoreOperationalIntent(',
      );
      final clearIndex = statusSource.indexOf(
        'await _clearPersistedStoreOperationalIntent();',
      );
      final removeIndex = statusSource.indexOf(
        '_pendingStoreOperationalRequestIds.remove(action);',
      );
      expect(persistIndex, greaterThanOrEqualTo(0));
      expect(callableIndex, greaterThan(persistIndex));
      expect(clearIndex, greaterThan(callableIndex));
      expect(removeIndex, greaterThan(clearIndex));
      expect(source, contains('_restorePendingStoreOperationalIntentSafely'));
      expect(source, contains('SallaAuthService.loadLocalRetryIntents'));
      expect(source, contains('ownerUid: sallaIdentity.uid'));
      expect(
        source,
        contains('environment: _storeOperationalRetryEnvironment'),
      );
      expect(
        source,
        isNot(contains("_pendingStoreOperationalRequestIds.remove('open')")),
      );
      expect(
        source,
        isNot(contains("_pendingStoreOperationalRequestIds.remove('close')")),
      );
      expect(statusSource, isNot(contains('database.update(')));
      expect(statusSource, isNot(contains('runTransaction(')));
      expect(source, contains("value['globalOperationLock'] == true"));
      expect(
        source,
        contains('final hasPendingStatusIntent = pendingAction.isNotEmpty;'),
      );
      expect(source, contains("? 'استكمال الفتح'"));
      expect(source, contains(" : 'استكمال الإيقاف'"));
      expect(source, contains('(!liveReady && !hasPendingStatusIntent)'));
      expect(
        source,
        contains("hasPendingStatusIntent ? pendingAction == 'open' : !_online"),
      );
    },
  );

  test('product offers use the trusted callable and stay store funded', () {
    final pageSource = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    expect(pageSource, contains("'setProductOffer'"));
    expect(pageSource, contains("'expectedRevision': product.offerRevision"));
    expect(pageSource, contains("'offerFunding': enabled ? 'store' : null"));
    expect(
      pageSource,
      isNot(
        contains("'storeCatalog/\$storeId/products/\${product.id}/offerPrice'"),
      ),
    );
  });

  test('catalog sync preserves server-owned settlement settings', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    final syncStart = source.indexOf('Future<void> _syncPublicCatalog()');
    final syncEnd = source.indexOf('void _listenToStore()', syncStart);

    expect(syncStart, greaterThanOrEqualTo(0));
    expect(syncEnd, greaterThan(syncStart));

    final syncSource = source.substring(syncStart, syncEnd);
    expect(syncSource, isNot(contains("'storeCatalog/\$storeId/products'")));
    expect(syncSource, isNot(contains("data['menuSections']")));
    expect(
      syncSource,
      isNot(contains("'storeCatalog/\$storeId/menuSections'")),
    );
    expect(syncSource, contains("'storeCatalog/\$storeId/\${entry.key}'"));
    expect(
      syncSource,
      contains("'storeCatalogPublic/\$storeId/\${entry.key}'"),
    );
    expect(syncSource, isNot(contains("'storeCatalog/\$storeId':")));
    expect(syncSource, isNot(contains("'storeCatalogPublic/\$storeId':")));
    expect(syncSource, isNot(contains("'customerZoneUpdatedBy'")));
    expect(syncSource, isNot(contains("'customerZoneUpdatedById'")));
    expect(syncSource, isNot(contains("'customerZonePolygonPoints'")));
  });

  testWidgets('dashboard stays responsive on a narrow screen', (tester) async {
    await _setTestViewport(tester, width: 320, height: 700, textScale: 1.4);
    await tester.pumpWidget(
      _testStoreApp(pageIndex: 0, orders: [_sampleOrder()]),
    );
    await tester.pumpAndSettle();

    expect(find.text('مركز تشغيل المتجر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('products stay responsive on a narrow screen', (tester) async {
    await _setTestViewport(tester, width: 320, height: 700, textScale: 1.6);
    await tester.pumpWidget(
      _testStoreApp(
        pageIndex: 2,
        products: const [
          StoreProduct(
            id: 'product-test',
            name: 'منتج تجريبي باسم طويل جداً لاختبار الشاشة الصغيرة',
            category: 'قسم طويل لاختبار تجاوب بطاقة المنتج',
            price: 7250,
            available: true,
            stockQuantity: 12,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('توفر المنتجات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in const [
    (width: 320.0, textScale: 1.0),
    (width: 360.0, textScale: 1.3),
    (width: 411.0, textScale: 1.6),
  ]) {
    testWidgets('orders stay responsive at ${viewport.width.toInt()} px', (
      tester,
    ) async {
      await _setTestViewport(
        tester,
        width: viewport.width,
        height: 760,
        textScale: viewport.textScale,
      );
      await tester.pumpWidget(
        _testStoreApp(pageIndex: 1, orders: [_sampleOrder()]),
      );
      await tester.pumpAndSettle();

      expect(find.text('طلبات المتجر'), findsOneWidget);
      expect(find.text('قبول الطلب'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('history separates delivered and cancelled orders with summary', (
    tester,
  ) async {
    await _setTestViewport(tester, width: 360, height: 760, textScale: 1.0);
    final delivered = StoreOrder.fromFirebase('delivered-order', {
      'orderNumber': '#DELIVERED',
      'storeId': 'store-test',
      'customerName': 'زبون المنصة',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'delivered',
      'storeStage': 'handedToDriver',
      'driverStage': 'delivered',
      'driverId': 'driver-1',
      'driverName': 'سائق التوصيل',
      'customerTotalToCollect': 9000,
      'items': const <dynamic>[],
    });
    final cancelled = StoreOrder.fromFirebase('cancelled-order', {
      'orderSource': 'store_external',
      'orderNumber': 'EXT-CANCELLED',
      'storeId': 'store-test',
      'customerName': 'مستلم خارجي',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'cancelled',
      'storeStage': 'cancelled',
      'driverStage': 'cancelled',
      'cancelledDriverId': 'driver-2',
      'cancelledDriverName': 'سائق الإلغاء',
      'customerTotalToCollect': 7000,
      'items': const <dynamic>[],
    });

    await tester.pumpWidget(
      _testStoreApp(pageIndex: 1, orders: [delivered, cancelled]),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('المكتملة'));
    await tester.tap(find.text('المكتملة'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('store_order_history_summary')),
      findsOneWidget,
    );
    expect(find.text('من منصة سلة 1'), findsOneWidget);
    expect(find.text('طلب مندوبك 1'), findsOneWidget);
    expect(find.text('#DELIVERED'), findsOneWidget);
    expect(find.text('زبون المنصة'), findsOneWidget);
    expect(find.textContaining('سائق التوصيل'), findsOneWidget);
    expect(find.textContaining('EXT-CANCELLED'), findsNothing);

    await tester.ensureVisible(find.text('الملغاة'));
    await tester.tap(find.text('الملغاة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('EXT-CANCELLED'), findsOneWidget);
    expect(find.textContaining('سائق الإلغاء'), findsOneWidget);
    expect(find.textContaining('#DELIVERED'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accept sheet fits a narrow screen and hides item prices', (
    tester,
  ) async {
    await _setTestViewport(tester, width: 320, height: 700, textScale: 1.3);
    await tester.pumpWidget(
      _testStoreApp(pageIndex: 1, orders: [_sampleOrder()]),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('قبول الطلب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قبول الطلب'));
    await tester.pumpAndSettle();

    expect(find.text('أصناف الطلب'), findsOneWidget);
    expect(find.textContaining('12,345'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _testStoreApp({
  required int pageIndex,
  List<StoreOrder> orders = const [],
  List<StoreProduct> products = const [],
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bgColor,
      colorScheme: ColorScheme.fromSeed(seedColor: appColor),
      fontFamily: 'Arial',
    ),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: StoreHomePage(
        enableRealtime: false,
        initialPageIndex: pageIndex,
        initialOrders: orders,
        initialProducts: products,
      ),
    ),
  );
}

Future<void> _setTestViewport(
  WidgetTester tester, {
  required double width,
  required double height,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

StoreOrder _sampleOrder({
  String key = 'order-test',
  String settlementMode = directStoreSettlementMode,
  int driverPaysStoreAmount = 5750,
}) {
  return StoreOrder.fromFirebase(key, {
    'orderNumber': '#123456',
    'customerId': 'customer-test',
    'storeId': 'store-test',
    'customerName': 'زبون باسم طويل لاختبار الواجهة',
    'phoneNumber': '07700000000',
    'deliveryAddressText': 'عنوان طويل لاختبار العرض على الشاشة الصغيرة',
    'paymentMethod': 'الدفع عند الاستلام',
    'paymentProvider': 'cash',
    'paymentCollectionMode': 'driver_cash_collection',
    'total': 8500,
    'subtotal': 7000,
    'storeGrossAmount': 7000,
    'storeNetAmount': 5750,
    'storeSettlementMode': settlementMode,
    'driverPaysStoreAmount': driverPaysStoreAmount,
    'customerTotalToCollect': 8500,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'status': 'pending',
    'storeStage': 'awaitingAcceptance',
    'driverStage': 'waitingForStore',
    'dispatchStatus': 'awaitingStore',
    'items': [
      {
        'name': 'صنف تجريبي طويل جداً لاختبار قائمة الأصناف',
        'quantity': 2,
        'unit': 'قطعة',
        'lineTotal': 12345,
      },
    ],
  });
}
