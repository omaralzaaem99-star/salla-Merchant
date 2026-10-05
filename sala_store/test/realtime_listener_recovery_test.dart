import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/src/pages/store_home_page.dart').readAsStringSync();
  });

  String section(String startMarker, String endMarker) {
    final start = source.indexOf(startMarker);
    final end = source.indexOf(endMarker, start + startMarker.length);
    expect(start, greaterThanOrEqualTo(0), reason: startMarker);
    expect(end, greaterThan(start), reason: endMarker);
    return source.substring(start, end);
  }

  test('authenticated startup uses one coordinated realtime restart', () {
    final initState = section(
      '  void initState()',
      '  void _listenToAuthenticationRecovery()',
    );
    final restart = section(
      '  Future<void> _restartLiveSubscriptions',
      '  Future<void> _stopLiveForAuthenticationLoss()',
    );

    expect(initState, contains('_listenToAuthenticationRecovery();'));
    expect(initState, contains('_requestLiveRestart(resetAttempt: true);'));
    expect(initState, isNot(contains('_listenToStore();')));
    expect(initState, isNot(contains('_listenToProducts();')));
    expect(initState, isNot(contains('_listenToOrders();')));

    expect(restart, contains('if (refreshToken)'));
    expect(restart, contains('.getIdToken(true)'));
    expect(restart, isNot(contains('.getIdToken(refreshToken)')));
    expect(restart, contains('await _cancelLiveSubscriptions();'));
    expect(restart, contains('_listenToStore();'));
    expect(restart, contains('_listenToProducts();'));
    expect(restart, contains('_listenToOrders();'));
    expect(
      restart.indexOf('await _cancelLiveSubscriptions();'),
      lessThan(restart.indexOf('_listenToStore();')),
    );
  });

  test('all store streams expose errors, closure, and generation guards', () {
    final storeListener = section(
      '  void _listenToStore()',
      '  void _listenToProducts()',
    );
    final productsListener = section(
      '  void _listenToProducts()',
      '  void _listenToOrders()',
    );
    final ordersListener = section(
      '  void _listenToOrders()',
      '  bool _hasSameVisibleOrderState',
    );

    for (final listener in [storeListener, productsListener, ordersListener]) {
      expect(listener, contains('final generation = _liveGeneration;'));
      expect(listener, contains('generation != _liveGeneration'));
      expect(listener, contains('onError:'));
      expect(listener, contains('onDone:'));
      expect(listener, contains('cancelOnError: true'));
      expect(listener, contains('_handleLiveStreamFailure('));
    }
  });

  test(
    'initial event watchdog fails loading and still accepts late recovery',
    () {
      final watchdog = section(
        '  void _startInitialLiveEventWatchdog',
        '  void _markAllLiveResourcesLoading()',
      );
      final ready = section(
        '  void _markLiveResourceReady',
        '  void _handleLiveStreamFailure',
      );
      final failure = section(
        '  void _handleLiveStreamFailure',
        '  bool _isAuthenticationFailure',
      );

      expect(watchdog, contains('_initialLiveEventTimeout'));
      expect(
        watchdog,
        contains("TimeoutException('Initial realtime event timed out.')"),
      );
      expect(watchdog, contains('_handleLiveStreamFailure('));
      expect(ready, contains('_cancelInitialLiveEventWatchdog(resource)'));
      expect(ready, contains('_StoreLiveStatus.ready'));
      expect(failure, contains('_StoreLiveStatus.error'));
      expect(failure, contains('_scheduleLiveRestart('));
      expect(
        RegExp(r'_startInitialLiveEventWatchdog\(').allMatches(source).length,
        greaterThanOrEqualTo(4),
      );
    },
  );

  test(
    'startup and public catalog sync are bounded without automatic rewrite',
    () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final profile = section(
        '  Future<void> _ensureStoreProfile()',
        '  void _listenToStore()',
      );

      expect(mainSource, contains('_storeStartupTimeout'));
      expect(
        RegExp(r'\.timeout\(\s*_storeStartupTimeout').allMatches(mainSource),
        hasLength(2),
      );
      expect(profile, contains('.timeout(_publicCatalogSyncTimeout)'));
      expect(
        profile,
        contains('_StorePublicCatalogSyncOutcome.writeOutcomeUncertain'),
      );
      expect(profile, contains('لم نكرر الكتابة تلقائياً'));
      expect(profile, isNot(contains('unawaited(_syncPublicCatalog')));
    },
  );

  test(
    'store reads active references and trusted public orders without a private order query',
    () {
      final ordersListener = section(
        '  void _listenToOrders()',
        '  bool _hasSameVisibleOrderState',
      );
      final publisher = section(
        '  void _publishMergedOrders',
        '  bool _hasSameVisibleOrderState',
      );

      expect(ordersListener, isNot(contains(".child('orders')")));
      expect(ordersListener, isNot(contains(".orderByChild('storeId')")));
      expect(ordersListener, contains('.limitToLast(150)'));
      expect(ordersListener, contains(".child('operationalOrderRefs')"));
      expect(ordersListener, contains(".child('stores')"));
      expect(ordersListener, contains('.child(storeId)'));
      expect(
        ordersListener,
        contains("_listenToOperationalOrder(orderId, generation)"),
      );
      expect(
        ordersListener,
        contains('watchStorePublicOrder(orderId).listen('),
      );
      expect(publisher, contains('..._pagedOrdersById'));
      expect(publisher, contains('..._recentOrdersById'));
      expect(publisher, contains('..._operationalOrdersById'));
      expect(publisher, contains('merged.values.toList(growable: false)'));
    },
  );

  test(
    'completed store history loads older server pages into the same list',
    () {
      final historyLoader = section(
        '  Future<void> loadOlderStoreOrders({bool reset = false})',
        '  bool _hasSameVisibleOrderState',
      );
      final ordersBody = section(
        '  Widget _ordersListBody()',
        '  Widget _productsPage()',
      );
      final filter = section('  Widget _filterChip(', '  Widget _metric(');

      expect(historyLoader, contains("'getStoreOrderHistoryPage'"));
      expect(historyLoader, contains("'storeId': storeId"));
      expect(historyLoader, contains("'pageSize': _storeHistoryPageSize"));
      expect(historyLoader, contains("'cursor': requestCursor"));
      expect(historyLoader, contains('_pagedOrdersById.addAll(pageOrders)'));
      expect(historyLoader, contains('jsonEncode(nextCursor)'));
      expect(ordersBody, contains('_storeHistoryPaginationControl()'));
      expect(ordersBody, contains('تحميل طلبات أقدم'));
      expect(ordersBody, contains('تم عرض جميع طلبات المتجر السابقة'));
      expect(filter, contains("_ensureStoreHistoryLoaded();"));
    },
  );

  test(
    'active reference listeners share readiness retry and cancellation lifecycle',
    () {
      final authentication = section(
        '  void _listenToAuthenticationRecovery()',
        '  void _requestLiveRestart',
      );
      final cancellation = section(
        '  Future<void> _cancelLiveSubscriptions()',
        '  void _scheduleLiveRestart',
      );
      final publisher = section(
        '  void _publishMergedOrders',
        '  bool _hasSameVisibleOrderState',
      );

      expect(
        authentication,
        contains('_operationalOrderRefsSubscription == null'),
      );
      expect(cancellation, contains('_operationalOrderRefsSubscription!'));
      expect(
        cancellation,
        contains('..._operationalOrderSubscriptions.values'),
      );
      expect(cancellation, contains('_operationalOrderSubscriptions.clear();'));
      expect(
        cancellation,
        contains('_operationalOrderListenerVersions.clear();'),
      );
      expect(cancellation, contains('_referencedOperationalOrderIds.clear();'));
      expect(publisher, contains('!_recentOrdersSnapshotReady'));
      expect(publisher, contains('!_operationalOrderRefsSnapshotReady'));
      expect(
        publisher,
        contains(
          '_initializedOperationalOrderIds.containsAll(\n'
          '          _referencedOperationalOrderIds',
        ),
      );
      expect(
        publisher,
        contains('_markLiveResourceReady(_StoreLiveResource.orders'),
      );
      expect(
        source,
        contains(
          '_operationalOrderListenerVersions[orderId] != listenerVersion',
        ),
      );
    },
  );

  test(
    'new order sound remains deferred while resolved alerts are cancelled',
    () {
      final recentListener = section(
        '  void _listenToOrders()',
        '  void _listenToOperationalOrderRefs',
      );
      final publisher = section(
        '  void _publishMergedOrders',
        '  bool _hasSameVisibleOrderState',
      );

      expect(recentListener, isNot(contains('_playIncomingOrderAlert(')));
      expect(publisher, isNot(contains('_playIncomingOrderAlert(')));
      expect(publisher, contains('final pendingIds = next'));
      expect(publisher, contains('_knownPendingOrderIds = pendingIds;'));
      expect(publisher, contains('for (final orderId in removedPendingIds)'));
      expect(publisher, contains('_syncStoreDispatchTimers(next);'));
      expect(source, contains("type == 'store_urgent_alert_resolved'"));
      expect(source, contains("'cancelAllUrgentAlerts'"));
      expect(source, contains('unawaited(_cancelAllIncomingOrderAlerts())'));
    },
  );

  test('retry timer is singular, bounded, and cancelled around lifecycle', () {
    final retry = section(
      '  void _scheduleLiveRestart',
      '  void _markAllLiveResourcesLoading()',
    );
    final lifecycle = section(
      '  void didChangeAppLifecycleState',
      '  void _startPaymentConfirmationHold',
    );

    expect(
      RegExp(r'Timer\?\s+_liveRetryTimer;').allMatches(source),
      hasLength(1),
    );
    expect(retry, contains('if (_liveRetryTimer != null) return;'));
    expect(retry, contains('Duration(seconds: 30)'));
    expect(lifecycle, contains('AppLifecycleState.resumed'));
    expect(
      lifecycle,
      contains('_requestLiveRestart(resetAttempt: true, refreshToken: true);'),
    );
    expect(lifecycle, contains('AppLifecycleState.paused'));
    expect(lifecycle, contains('_liveRetryTimer?.cancel();'));
  });

  test(
    'orders and products distinguish live failure from a true empty list',
    () {
      final ordersBody = section(
        '  Widget _ordersListBody()',
        '  Widget _productsPage()',
      );
      final productsPage = section(
        '  Widget _productsPage()',
        '  Widget _settingsPage()',
      );

      expect(
        ordersBody,
        contains('_ordersLiveStatus == _StoreLiveStatus.ready'),
      );
      expect(ordersBody, contains('لا توجد طلبات في هذا القسم'));
      expect(ordersBody, contains('تعذر تحديث طلبات المتجر'));
      expect(ordersBody, contains('_liveStatusCard('));

      expect(
        productsPage,
        contains('_productsLiveStatus != _StoreLiveStatus.ready'),
      );
      expect(productsPage, contains('جاري تحميل منتجات المتجر'));
      expect(productsPage, contains('تعذر تحديث منتجات المتجر'));
      expect(productsPage, contains('لا توجد منتجات مسجلة لهذا المتجر حالياً'));
    },
  );
}
