part of sala_store;

class StoreOrderNumberLabel extends StatelessWidget {
  const StoreOrderNumberLabel({
    super.key,
    required this.number,
    required this.onCopy,
  });
  final String number;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'نسخ رقم الطلب $number',
    child: Tooltip(
      message: 'نسخ رقم الطلب',
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.copy_rounded, size: 14, color: appColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  number,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  softWrap: true,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: darkText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

enum _StoreLiveResource { store, products, orders }

enum _StoreLiveStatus { loading, ready, error }

bool storeCourierOnlyChannelReady({
  required String storeStatus,
  required bool storeLockedByAdmin,
  required bool networkAssignmentPending,
  required String customerZoneMode,
  required bool storeExternalDeliveryEnabled,
}) {
  return storeStatus == 'active' &&
      !storeLockedByAdmin &&
      !networkAssignmentPending &&
      customerZoneMode == 'hidden' &&
      storeExternalDeliveryEnabled;
}

String storeReadyHeaderStatusLabel({
  required String storeStatus,
  required bool storeLockedByAdmin,
  required bool networkAssignmentPending,
  required String customerZoneMode,
  required bool storeExternalDeliveryEnabled,
  required bool online,
}) {
  if (storeStatus == 'banned') return 'محظور من الإدارة';
  if (networkAssignmentPending) return 'بانتظار تعيين الفرع والزون';
  final courierOnly =
      customerZoneMode == 'hidden' && storeExternalDeliveryEnabled;
  if (storeLockedByAdmin) {
    return courierOnly
        ? 'طلب مندوبك بانتظار اعتماد الإدارة'
        : 'موقوف من الإدارة';
  }
  if (storeCourierOnlyChannelReady(
    storeStatus: storeStatus,
    storeLockedByAdmin: storeLockedByAdmin,
    networkAssignmentPending: networkAssignmentPending,
    customerZoneMode: customerZoneMode,
    storeExternalDeliveryEnabled: storeExternalDeliveryEnabled,
  )) {
    return 'متاح لطلب مندوبك';
  }
  return online ? 'مفتوح ويستقبل الطلبات' : 'مغلق مؤقتاً';
}

const Set<String> _volatileOrderLocationFields = <String>{
  'driverLat',
  'driverLng',
  'driverLocationUpdatedAt',
};

String storeOperationalOrderContentSignature(Object? value) {
  final tracksExternalDriver =
      value is Map &&
      value['orderSource']?.toString().trim() == 'store_external';
  return sallaRecordContentSignature(
    value,
    ignoredKeys: tracksExternalDriver
        ? const <String>{}
        : _volatileOrderLocationFields,
  );
}

Widget storeOpenStreetMapAttribution() {
  return Align(
    alignment: Alignment.bottomLeft,
    child: Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          unawaited(
            launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication,
            ),
          );
        },
        child: const Padding(
          padding: EdgeInsets.all(3),
          child: Text(
            'flutter_map | © OpenStreetMap contributors',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 10),
          ),
        ),
      ),
    ),
  );
}

class _StoreLiveDriverMap extends StatefulWidget {
  final double latitude;
  final double longitude;

  const _StoreLiveDriverMap({required this.latitude, required this.longitude});

  @override
  State<_StoreLiveDriverMap> createState() => _StoreLiveDriverMapState();
}

class _StoreLiveDriverMapState extends State<_StoreLiveDriverMap> {
  final MapController _mapController = MapController();

  LatLng get _driverPoint => LatLng(widget.latitude, widget.longitude);

  @override
  void didUpdateWidget(covariant _StoreLiveDriverMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude == widget.latitude &&
        oldWidget.longitude == widget.longitude) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(_driverPoint, 16.25);
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = _driverPoint;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 280,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: point,
                initialZoom: 16.25,
                minZoom: 4,
                maxZoom: 19,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.selafood.store',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 70,
                      height: 70,
                      child: Container(
                        decoration: BoxDecoration(
                          color: orangeColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.delivery_dining_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            PositionedDirectional(
              top: 10,
              start: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.09),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.green, size: 11),
                    SizedBox(width: 6),
                    Text(
                      'مباشر',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            storeOpenStreetMapAttribution(),
          ],
        ),
      ),
    );
  }
}

enum _StorePublicCatalogSyncOutcome {
  confirmed,
  readTimedOut,
  writeOutcomeUncertain,
}

Widget buildSelectedStorePage({
  required int pageIndex,
  required Widget Function() dashboardBuilder,
  required Widget Function() ordersBuilder,
  required Widget Function() productsBuilder,
  required Widget Function() settingsBuilder,
}) {
  return switch (pageIndex) {
    0 => dashboardBuilder(),
    1 => ordersBuilder(),
    2 => productsBuilder(),
    3 => settingsBuilder(),
    _ => ordersBuilder(),
  };
}

class StoreHomePage extends StatefulWidget {
  final bool enableRealtime;
  final VoidCallback? onGuestLogin;
  final VoidCallback? onGuestApply;
  bool get isGuest => onGuestLogin != null;
  final int initialPageIndex;
  final List<StoreOrder> initialOrders;
  final List<StoreProduct> initialProducts;

  const StoreHomePage({
    super.key,
    this.enableRealtime = true,
    this.initialPageIndex = 1,
    this.initialOrders = const <StoreOrder>[],
    this.initialProducts = const <StoreProduct>[],
  }) : onGuestLogin = null,
       onGuestApply = null;

  const StoreHomePage.guest({
    super.key,
    required VoidCallback onLogin,
    VoidCallback? onApply,
  }) : onGuestLogin = onLogin,
       onGuestApply = onApply,
       enableRealtime = false,
       initialPageIndex = 1,
       initialOrders = const [],
       initialProducts = const [];

  @override
  State<StoreHomePage> createState() => _StoreHomePageState();
}

class _StoreHomePageState extends State<StoreHomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _storeOperationalRetryNamespace =
      'store_operational_status';
  static const Set<String> _storeFieldsHandledByOtherListeners = <String>{
    'products',
    'updatedAt',
  };
  static const MethodChannel _notificationsChannel = MethodChannel(
    'com.selafood.store/notifications',
  );
  static const MethodChannel _sharedLocationChannel = MethodChannel(
    'com.selafood.store/shared_location',
  );
  static const Duration _initialLiveEventTimeout = Duration(seconds: 15);
  static const Duration _storeMutationWriteTimeout = Duration(seconds: 12);
  static const Duration _publicCatalogSyncTimeout = Duration(seconds: 12);
  StreamSubscription<DatabaseEvent>? _ordersSubscription;
  StreamSubscription<DatabaseEvent>? _operationalOrderRefsSubscription;
  final Map<String, StreamSubscription<Map<String, dynamic>?>>
  _operationalOrderSubscriptions =
      <String, StreamSubscription<Map<String, dynamic>?>>{};
  final Map<String, int> _operationalOrderListenerVersions = <String, int>{};
  StreamSubscription<DatabaseEvent>? _storeSubscription;
  StreamSubscription<DatabaseEvent>? _productsSubscription;
  StreamSubscription<dynamic>? _authStateSubscription;
  StreamSubscription<String>? _messagingTokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  int _pushRegistrationGeneration = 0;
  final SallaPushEventDeduplicator _foregroundPushDeduplicator =
      SallaPushEventDeduplicator();
  final SallaPushEventDeduplicator _openedPushDeduplicator =
      SallaPushEventDeduplicator();
  Timer? _liveRetryTimer;
  final Map<_StoreLiveResource, Timer> _initialLiveEventWatchdogs =
      <_StoreLiveResource, Timer>{};
  int _liveRetryAttempt = 0;
  int _liveGeneration = 0;
  bool _liveRestartInProgress = false;
  bool _liveRestartPending = false;
  bool _pendingTokenRefresh = false;
  bool _authEventInitialized = false;
  bool _appIsResumed = true;
  bool _liveDisposed = false;
  bool _storeProfileEnsured = false;
  bool _ensuringStoreProfile = false;
  _StorePublicCatalogSyncOutcome _lastPublicCatalogSyncOutcome =
      _StorePublicCatalogSyncOutcome.confirmed;
  _StoreLiveStatus _storeLiveStatus = _StoreLiveStatus.loading;
  _StoreLiveStatus _productsLiveStatus = _StoreLiveStatus.loading;
  _StoreLiveStatus _ordersLiveStatus = _StoreLiveStatus.loading;
  String _storeLiveError = '';
  String _productsLiveError = '';
  String _ordersLiveError = '';
  final List<StoreOrder> _orders = [];
  final Map<String, StoreOrder> _recentOrdersById = <String, StoreOrder>{};
  final Map<String, StoreOrder> _pagedOrdersById = <String, StoreOrder>{};
  final Map<String, StoreOrder> _operationalOrdersById = <String, StoreOrder>{};
  final Map<String, String> _operationalOrderContentSignatures =
      <String, String>{};
  final Set<String> _referencedOperationalOrderIds = <String>{};
  final Set<String> _initializedOperationalOrderIds = <String>{};
  bool _recentOrdersSnapshotReady = false;
  bool _operationalOrderRefsSnapshotReady = false;
  Set<String> _knownPendingOrderIds = <String>{};
  bool _ordersInitialized = false;
  static const int _storeHistoryPageSize = 50;
  Map<String, dynamic>? _storeHistoryCursor;
  bool _storeHistoryHasMore = true;
  bool _storeHistoryLoading = false;
  bool _storeHistoryInitialized = false;
  String _storeHistoryError = '';
  int _storeHistoryGeneration = 0;
  List<StoreProduct> _products = [];
  int _pageIndex = 1;
  int _prepMinutes = 25;
  bool _autoDispatchEnabled = true;
  int _dispatchLeadMinutes = defaultDispatchLeadMinutes;
  bool _online = true;
  String _storeStatus = 'active';
  bool _storeLockedByAdmin = false;
  bool _networkAssignmentPending = false;
  String _customerZoneMode = 'normal';
  bool _storeExternalDeliveryEnabled = false;
  String _storeStatusReason = '';
  bool _storeStatusUpdating = false;
  final Map<String, String> _pendingStoreOperationalRequestIds =
      <String, String>{};
  late final Future<void> _storeOperationalIntentRestoreFuture;
  Object? _storeOperationalIntentRestoreError;
  String _lastSettlementAt = '';
  String _lastSettlementMethod = '';
  String _lastSettlementPaymentReference = '';
  int _lastSettlementAmount = 0;
  int _lastSettlementOrderCount = 0;
  Timer? _settlementPreviewTimer;
  bool _settlementPreviewLoading = false;
  bool _settlementPreviewLoaded = false;
  bool _settlementPreviewRefreshPending = false;
  String _settlementPreviewError = '';
  int _trustedOpenSettlementAmount = 0;
  int _trustedOpenSettlementOrderCount = 0;
  int _trustedSettledAmount = 0;
  int _trustedSettledOrderCount = 0;
  final Set<String> _busyProductIds = <String>{};
  final Set<String> _busyStoreSettingKeys = <String>{};
  bool _busy = false;
  bool _sharedLocationInspectionInProgress = false;
  bool _storeExternalComposerOpen = false;
  String _lastSharedLocationFailureId = '';
  String _filter = 'active';
  static const Duration _paymentHoldDuration = Duration(milliseconds: 1250);
  late final AnimationController _paymentHoldController;
  String _paymentHoldOrderKey = '';
  StoreOrder? _paymentHoldOrder;
  String? _ordersContentSignature;
  String? _publishedOrdersContentSignature;
  String? _settlementOrdersContentSignature;
  String? _storeProfileContentSignature;

  @override
  void initState() {
    super.initState();
    _storeOperationalIntentRestoreFuture = widget.enableRealtime
        ? _restorePendingStoreOperationalIntentSafely()
        : Future<void>.value();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.isGuest &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      _sharedLocationChannel.setMethodCallHandler((call) async {
        if (call.method != 'sharedLocationAvailable' || !mounted) return;
        _lastSharedLocationFailureId = '';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_inspectPendingSharedLocation());
        });
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_inspectPendingSharedLocation());
      });
    }
    _pageIndex = widget.initialPageIndex.clamp(0, 3).toInt();
    _orders.addAll(widget.initialOrders);
    for (final order in widget.initialOrders) {
      _recentOrdersById[order.databaseKey] = order;
    }
    _products = List<StoreProduct>.of(widget.initialProducts);
    _knownPendingOrderIds = _orders
        .where(_isNewStoreOrder)
        .map((order) => order.databaseKey)
        .toSet();
    _ordersInitialized = _orders.isNotEmpty;
    _paymentHoldController =
        AnimationController(vsync: this, duration: _paymentHoldDuration)
          ..addStatusListener((status) {
            if (status != AnimationStatus.completed) return;
            final order = _paymentHoldOrder;
            if (order == null) return;
            HapticFeedback.mediumImpact();
            setState(() {
              _paymentHoldOrderKey = '';
              _paymentHoldOrder = null;
            });
            _paymentHoldController.reset();
            unawaited(_confirmDriverPayment(order));
          });
    if (!widget.enableRealtime) {
      _storeLiveStatus = _StoreLiveStatus.ready;
      _productsLiveStatus = _StoreLiveStatus.ready;
      _ordersLiveStatus = _StoreLiveStatus.ready;
      return;
    }
    _listenToAuthenticationRecovery();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestLiveRestart(resetAttempt: true);
      unawaited(_configurePushNotifications());
    });
  }

  String get _storeOperationalRetryEnvironment =>
      Firebase.app().options.projectId.trim();

  Future<void> _restorePendingStoreOperationalIntentSafely() async {
    try {
      final records = await SallaAuthService.loadLocalRetryIntents(
        role: SallaUserRole.store,
        environment: _storeOperationalRetryEnvironment,
        ownerUid: sallaIdentity.uid,
        namespace: _storeOperationalRetryNamespace,
      );
      final payload = records[storeId];
      if (payload == null) return;
      final action = payload['action']?.toString().trim() ?? '';
      final requestId = payload['requestId']?.toString().trim() ?? '';
      final payloadStoreId = payload['storeId']?.toString().trim() ?? '';
      if (payloadStoreId != storeId ||
          !const <String>{'open', 'close'}.contains(action) ||
          requestId.isEmpty ||
          requestId.length > 180) {
        await _clearPersistedStoreOperationalIntent();
        return;
      }
      if (!mounted) return;
      setState(() {
        _pendingStoreOperationalRequestIds
          ..clear()
          ..[action] = requestId;
      });
    } catch (error) {
      _storeOperationalIntentRestoreError = error;
    }
  }

  Future<void> _persistStoreOperationalIntent({
    required String action,
    required String requestId,
  }) {
    return SallaAuthService.saveLocalRetryIntent(
      role: SallaUserRole.store,
      environment: _storeOperationalRetryEnvironment,
      ownerUid: sallaIdentity.uid,
      namespace: _storeOperationalRetryNamespace,
      intentId: storeId,
      payload: <String, Object?>{
        'storeId': storeId,
        'action': action,
        'requestId': requestId,
      },
    );
  }

  Future<void> _clearPersistedStoreOperationalIntent() {
    return SallaAuthService.removeLocalRetryIntent(
      role: SallaUserRole.store,
      environment: _storeOperationalRetryEnvironment,
      ownerUid: sallaIdentity.uid,
      namespace: _storeOperationalRetryNamespace,
      intentId: storeId,
    );
  }

  void _listenToAuthenticationRecovery() {
    _authStateSubscription = SallaAuthService.firebaseAuth
        .idTokenChanges()
        .listen(
          (user) {
            if (_liveDisposed || !mounted) return;
            final authenticatedUid = user?.uid ?? '';
            if (!_authEventInitialized) {
              _authEventInitialized = true;
              if (authenticatedUid == sallaIdentity.uid) return;
            }
            if (authenticatedUid != sallaIdentity.uid) {
              unawaited(_stopLiveForAuthenticationLoss());
              return;
            }
            final needsRecovery =
                _storeLiveStatus == _StoreLiveStatus.error ||
                _productsLiveStatus == _StoreLiveStatus.error ||
                _ordersLiveStatus == _StoreLiveStatus.error ||
                _storeSubscription == null ||
                _productsSubscription == null ||
                _ordersSubscription == null ||
                _operationalOrderRefsSubscription == null;
            if (needsRecovery) {
              _requestLiveRestart(resetAttempt: true);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_liveDisposed || !mounted) return;
            _markAllLiveResourcesFailed(
              'تعذر التحقق من جلسة المتجر مؤقتاً. سنعيد الاتصال تلقائياً.',
            );
            _scheduleLiveRestart(refreshToken: true);
          },
        );
  }

  void _requestLiveRestart({
    bool resetAttempt = false,
    bool refreshToken = false,
  }) {
    if (_liveDisposed || !mounted || !widget.enableRealtime) return;
    if (resetAttempt) _liveRetryAttempt = 0;
    _pendingTokenRefresh = _pendingTokenRefresh || refreshToken;
    _liveRetryTimer?.cancel();
    _liveRetryTimer = null;
    _cancelAllInitialLiveEventWatchdogs();
    if (_liveRestartInProgress) {
      _liveRestartPending = true;
      return;
    }
    final shouldRefreshToken = _pendingTokenRefresh;
    _pendingTokenRefresh = false;
    unawaited(_restartLiveSubscriptions(refreshToken: shouldRefreshToken));
  }

  Future<void> _restartLiveSubscriptions({required bool refreshToken}) async {
    if (_liveDisposed || !mounted || !_appIsResumed || !widget.enableRealtime) {
      return;
    }
    _liveRestartInProgress = true;
    try {
      final user = SallaAuthService.firebaseAuth.currentUser;
      if (user == null || user.uid != sallaIdentity.uid) {
        await _cancelLiveSubscriptions();
        _markAllLiveResourcesFailed(
          'انتهت جلسة المتجر. أعد تسجيل الدخول لاستعادة التحديثات.',
        );
        return;
      }
      if (refreshToken) {
        try {
          final token = await user
              .getIdToken(true)
              .timeout(const Duration(seconds: 12));
          if (token == null || token.trim().isEmpty) {
            throw StateError('Firebase authentication token is unavailable.');
          }
        } catch (error) {
          _markAllLiveResourcesFailed(
            'تعذر تجديد جلسة المتجر مؤقتاً. سنعيد المحاولة تلقائياً.',
          );
          _scheduleLiveRestart(refreshToken: true);
          return;
        }
      }
      final authenticatedUser = SallaAuthService.firebaseAuth.currentUser;
      if (authenticatedUser == null ||
          authenticatedUser.uid != sallaIdentity.uid) {
        await _cancelLiveSubscriptions();
        _markAllLiveResourcesFailed(
          'انتهت جلسة المتجر. أعد تسجيل الدخول لاستعادة التحديثات.',
        );
        return;
      }

      await _cancelLiveSubscriptions();
      if (_liveDisposed || !mounted || !_appIsResumed) return;
      _markAllLiveResourcesLoading();
      _listenToStore();
      _listenToProducts();
      _listenToOrders();
      _scheduleStoreSettlementPreview();
      if (!_storeProfileEnsured) {
        unawaited(_ensureStoreProfile());
      }
      SallaDatabase.instance.reconnectRealtime();
    } finally {
      _liveRestartInProgress = false;
      if (_liveRestartPending && !_liveDisposed && mounted && _appIsResumed) {
        _liveRestartPending = false;
        _requestLiveRestart();
      }
    }
  }

  Future<void> _stopLiveForAuthenticationLoss() async {
    _liveRetryTimer?.cancel();
    _liveRetryTimer = null;
    await _cancelLiveSubscriptions();
    if (_liveDisposed || !mounted) return;
    _markAllLiveResourcesFailed(
      'انتهت جلسة المتجر. أعد تسجيل الدخول لاستعادة التحديثات.',
    );
  }

  Future<void> _cancelLiveSubscriptions() async {
    _liveGeneration += 1;
    _cancelAllInitialLiveEventWatchdogs();
    final subscriptions = <StreamSubscription<dynamic>>[
      if (_storeSubscription != null) _storeSubscription!,
      if (_productsSubscription != null) _productsSubscription!,
      if (_ordersSubscription != null) _ordersSubscription!,
      if (_operationalOrderRefsSubscription != null)
        _operationalOrderRefsSubscription!,
      ..._operationalOrderSubscriptions.values,
    ];
    _storeSubscription = null;
    _productsSubscription = null;
    _ordersSubscription = null;
    _operationalOrderRefsSubscription = null;
    _operationalOrderSubscriptions.clear();
    _operationalOrderListenerVersions.clear();
    _operationalOrdersById.clear();
    _operationalOrderContentSignatures.clear();
    _referencedOperationalOrderIds.clear();
    _initializedOperationalOrderIds.clear();
    _recentOrdersSnapshotReady = false;
    _operationalOrderRefsSnapshotReady = false;
    await Future.wait(
      subscriptions.map((subscription) async {
        try {
          await subscription.cancel();
        } catch (_) {
          // The generation guard below already makes the old stream inert.
        }
      }),
    );
  }

  void _scheduleLiveRestart({bool refreshToken = false}) {
    if (_liveDisposed || !mounted || !_appIsResumed || !widget.enableRealtime) {
      return;
    }
    _pendingTokenRefresh = _pendingTokenRefresh || refreshToken;
    if (_liveRetryTimer != null) return;
    const delays = <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ];
    final delay = delays[_liveRetryAttempt.clamp(0, delays.length - 1).toInt()];
    _liveRetryAttempt += 1;
    _liveRetryTimer = Timer(delay, () {
      _liveRetryTimer = null;
      _requestLiveRestart();
    });
  }

  void _startInitialLiveEventWatchdog(
    _StoreLiveResource resource,
    int generation,
  ) {
    _cancelInitialLiveEventWatchdog(resource);
    _initialLiveEventWatchdogs[resource] = Timer(_initialLiveEventTimeout, () {
      if (_liveDisposed ||
          !mounted ||
          generation != _liveGeneration ||
          !_appIsResumed) {
        return;
      }
      _initialLiveEventWatchdogs.remove(resource);
      _handleLiveStreamFailure(
        resource,
        TimeoutException('Initial realtime event timed out.'),
        generation,
      );
    });
  }

  void _cancelInitialLiveEventWatchdog(_StoreLiveResource resource) {
    _initialLiveEventWatchdogs.remove(resource)?.cancel();
  }

  void _cancelAllInitialLiveEventWatchdogs() {
    for (final timer in _initialLiveEventWatchdogs.values) {
      timer.cancel();
    }
    _initialLiveEventWatchdogs.clear();
  }

  void _markAllLiveResourcesLoading() {
    if (_liveDisposed || !mounted) return;
    setState(() {
      _storeLiveStatus = _StoreLiveStatus.loading;
      _productsLiveStatus = _StoreLiveStatus.loading;
      _ordersLiveStatus = _StoreLiveStatus.loading;
      _storeLiveError = '';
      _productsLiveError = '';
      _ordersLiveError = '';
    });
  }

  void _markAllLiveResourcesFailed(String message) {
    if (_liveDisposed || !mounted) return;
    _cancelAllInitialLiveEventWatchdogs();
    setState(() {
      _storeLiveStatus = _StoreLiveStatus.error;
      _productsLiveStatus = _StoreLiveStatus.error;
      _ordersLiveStatus = _StoreLiveStatus.error;
      _storeLiveError = message;
      _productsLiveError = message;
      _ordersLiveError = message;
    });
  }

  void _markLiveResourceReady(_StoreLiveResource resource, int generation) {
    if (_liveDisposed || !mounted || generation != _liveGeneration) return;
    _cancelInitialLiveEventWatchdog(resource);
    setState(() {
      switch (resource) {
        case _StoreLiveResource.store:
          _storeLiveStatus = _StoreLiveStatus.ready;
          _storeLiveError = '';
          break;
        case _StoreLiveResource.products:
          _productsLiveStatus = _StoreLiveStatus.ready;
          _productsLiveError = '';
          break;
        case _StoreLiveResource.orders:
          _ordersLiveStatus = _StoreLiveStatus.ready;
          _ordersLiveError = '';
          break;
      }
    });
    if (_storeLiveStatus == _StoreLiveStatus.ready &&
        _productsLiveStatus == _StoreLiveStatus.ready &&
        _ordersLiveStatus == _StoreLiveStatus.ready) {
      _liveRetryAttempt = 0;
      _liveRetryTimer?.cancel();
      _liveRetryTimer = null;
      _cancelAllInitialLiveEventWatchdogs();
    }
  }

  void _handleLiveStreamFailure(
    _StoreLiveResource resource,
    Object error,
    int generation, {
    bool streamClosed = false,
  }) {
    if (_liveDisposed || !mounted || generation != _liveGeneration) return;
    _cancelInitialLiveEventWatchdog(resource);
    final message = streamClosed
        ? 'انقطع التحديث اللحظي. سنعيد الاتصال تلقائياً.'
        : _friendlyLiveError(error);
    setState(() {
      switch (resource) {
        case _StoreLiveResource.store:
          _storeLiveStatus = _StoreLiveStatus.error;
          _storeLiveError = message;
          break;
        case _StoreLiveResource.products:
          _productsLiveStatus = _StoreLiveStatus.error;
          _productsLiveError = message;
          break;
        case _StoreLiveResource.orders:
          _ordersLiveStatus = _StoreLiveStatus.error;
          _ordersLiveError = message;
          break;
      }
    });
    _scheduleLiveRestart(refreshToken: _isAuthenticationFailure(error));
  }

  bool _isAuthenticationFailure(Object error) {
    final value = error.toString().toLowerCase();
    return value.contains('permission-denied') ||
        value.contains('permission_denied') ||
        value.contains('permission denied') ||
        value.contains('unauthenticated') ||
        value.contains('auth') ||
        value.contains('token') ||
        value.contains('credential');
  }

  String _friendlyLiveError(Object error) {
    final value = error.toString().toLowerCase();
    if (_isAuthenticationFailure(error)) {
      return 'تعذر التحقق من جلسة المتجر مؤقتاً. سنعيد الاتصال تلقائياً.';
    }
    if (value.contains('network') ||
        value.contains('socket') ||
        value.contains('unavailable') ||
        value.contains('timeout')) {
      return 'تعذر تحديث البيانات بسبب الاتصال. سنعيد المحاولة تلقائياً.';
    }
    return 'تعذر تحديث البيانات اللحظية. سنعيد المحاولة تلقائياً.';
  }

  Future<void> _ensureStoreProfile() async {
    if (_storeProfileEnsured || _ensuringStoreProfile || _liveDisposed) return;
    final generation = _liveGeneration;
    _ensuringStoreProfile = true;
    try {
      final storeRef = database.child('stores').child(storeId);
      final snapshot = await waitForFirebaseResult(
        storeRef.get(),
        debugLabel: 'Store profile verification',
        timeout: const Duration(seconds: 20),
      );
      if (snapshot == null) {
        throw TimeoutException('Store profile verification timed out.');
      }
      final rawValue = snapshot.value;
      if (rawValue is! Map) {
        throw StateError('Store profile is unavailable.');
      }
      final data = Map<String, dynamic>.from(
        rawValue.map((key, value) => MapEntry(key.toString(), value)),
      );
      final trustedStoreId = data['id']?.toString().trim() ?? '';
      final trustedAuthUid = data['authUid']?.toString().trim() ?? '';
      if (trustedStoreId != storeId ||
          trustedAuthUid != sallaIdentity.uid ||
          data['active'] != true) {
        throw StateError('Store account is not linked to this active profile.');
      }

      final safePrepMinutes = firebaseIntValue(
        data['prepMinutes'],
        25,
      ).clamp(minPrepMinutes, maxPrepMinutes).toInt();
      final safeDispatchLeadMinutes = firebaseIntValue(
        data['dispatchLeadMinutes'],
        defaultDispatchLeadMinutes,
      ).clamp(minDispatchLeadMinutes, maxDispatchLeadMinutes).toInt();
      final updates = <String, dynamic>{};
      if (data['prepMinutes'] is! num ||
          (data['prepMinutes'] as num).toInt() != safePrepMinutes) {
        updates['stores/$storeId/prepMinutes'] = safePrepMinutes;
      }
      if (data['autoDispatchEnabled'] is! bool) {
        updates['stores/$storeId/autoDispatchEnabled'] = true;
      }
      if (data['dispatchLeadMinutes'] is! num ||
          (data['dispatchLeadMinutes'] as num).toInt() !=
              safeDispatchLeadMinutes) {
        updates['stores/$storeId/dispatchLeadMinutes'] =
            safeDispatchLeadMinutes;
      }
      if (updates.isNotEmpty) {
        updates['stores/$storeId/updatedAt'] = sallaUtcNowIso();
        await database.update(updates).timeout(const Duration(seconds: 20));
      }
      await _syncPublicCatalog();
      final catalogSyncOutcome = _lastPublicCatalogSyncOutcome;
      _storeProfileEnsured = true;
      if (catalogSyncOutcome != _StorePublicCatalogSyncOutcome.confirmed &&
          !_liveDisposed &&
          mounted &&
          generation == _liveGeneration) {
        final message =
            catalogSyncOutcome ==
                _StorePublicCatalogSyncOutcome.writeOutcomeUncertain
            ? 'انتهت مهلة مزامنة دليل المتجر والنتيجة غير مؤكدة. لم نكرر الكتابة تلقائياً.'
            : 'تأخرت قراءة بيانات دليل المتجر. لم ننفذ كتابة تلقائية، وستبقى البيانات الحالية.';
        _message(message, error: true);
      }
    } catch (error, stackTrace) {
      debugPrint('Store profile sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!_liveDisposed && mounted && generation == _liveGeneration) {
        _handleLiveStreamFailure(_StoreLiveResource.store, error, generation);
      }
    } finally {
      _ensuringStoreProfile = false;
    }
  }

  Future<void> _syncPublicCatalog() async {
    _lastPublicCatalogSyncOutcome = _StorePublicCatalogSyncOutcome.confirmed;
    final DataSnapshot snapshot;
    try {
      snapshot = await database
          .child('stores')
          .child(storeId)
          .get()
          .timeout(_publicCatalogSyncTimeout);
    } on TimeoutException {
      _lastPublicCatalogSyncOutcome =
          _StorePublicCatalogSyncOutcome.readTimedOut;
      return;
    }
    if (snapshot.value is! Map) {
      return;
    }
    final data = (snapshot.value as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final publicCatalog = <String, dynamic>{
      'id': storeId,
      'name': data['name']?.toString() ?? storeName,
      'prepMinutes': firebaseIntValue(
        data['prepMinutes'],
        25,
      ).clamp(minPrepMinutes, maxPrepMinutes).toInt(),
      'updatedAt': ServerValue.timestamp,
    };
    for (final field in <String>[
      'address',
      'lat',
      'lng',
      'storeLat',
      'storeLng',
      'serviceZoneId',
      'serviceZoneName',
    ]) {
      final value = data[field];
      if (value != null && value.toString().trim().isNotEmpty) {
        publicCatalog[field] = value;
      }
    }
    // The server owns menuSections/products and their mirrored revisions.
    // This client only refreshes public store metadata field-by-field.
    final updates = <String, dynamic>{};
    for (final entry in publicCatalog.entries) {
      updates['storeCatalog/$storeId/${entry.key}'] = entry.value;
      updates['storeCatalogPublic/$storeId/${entry.key}'] = entry.value;
    }
    try {
      await database.update(updates).timeout(_publicCatalogSyncTimeout);
    } on TimeoutException {
      // A Realtime Database write may still commit after the local Future
      // times out. Do not rewrite it automatically; live readers reconcile it.
      _lastPublicCatalogSyncOutcome =
          _StorePublicCatalogSyncOutcome.writeOutcomeUncertain;
    }
  }

  void _listenToStore() {
    final generation = _liveGeneration;
    _startInitialLiveEventWatchdog(_StoreLiveResource.store, generation);
    _storeSubscription = database
        .child('stores')
        .child(storeId)
        .onValue
        .listen(
          (event) {
            if (_liveDisposed || !mounted || generation != _liveGeneration) {
              return;
            }
            final value = event.snapshot.value;
            if (value is! Map) {
              _handleLiveStreamFailure(
                _StoreLiveResource.store,
                StateError('Store profile is unavailable.'),
                generation,
              );
              return;
            }
            _markLiveResourceReady(_StoreLiveResource.store, generation);
            final contentSignature = sallaRecordContentSignature(
              value,
              ignoredKeys: _storeFieldsHandledByOtherListeners,
            );
            if (contentSignature == _storeProfileContentSignature) return;
            _storeProfileContentSignature = contentSignature;
            setState(() {
              final status = value['storeStatus']?.toString() ?? 'active';
              _storeStatus = status;
              _storeLockedByAdmin =
                  value['globalOperationLock'] == true ||
                  (status != 'active' &&
                      (value['storeStatusLocked'] == true ||
                          status == 'banned'));
              _networkAssignmentPending =
                  value['networkAssignmentPending'] == true ||
                  value['networkAssignmentStatus'] ==
                      'pending_admin_assignment';
              _customerZoneMode =
                  value['customerZoneMode']?.toString().trim().toLowerCase() ??
                  'normal';
              _storeExternalDeliveryEnabled =
                  value['storeExternalDeliveryEnabled'] == true;
              _storeStatusReason =
                  value['statusReason']?.toString().trim() ?? '';
              _online =
                  value['isOnline'] != false &&
                  value['acceptingOrders'] != false &&
                  status == 'active';
              _prepMinutes = firebaseIntValue(
                value['prepMinutes'],
                25,
              ).clamp(minPrepMinutes, maxPrepMinutes).toInt();
              _autoDispatchEnabled = value['autoDispatchEnabled'] != false;
              _dispatchLeadMinutes = firebaseIntValue(
                value['dispatchLeadMinutes'],
                defaultDispatchLeadMinutes,
              ).clamp(minDispatchLeadMinutes, maxDispatchLeadMinutes).toInt();
              _lastSettlementAt = value['lastSettlementAt']?.toString() ?? '';
              _lastSettlementMethod =
                  value['lastSettlementMethod']?.toString() ?? '';
              _lastSettlementPaymentReference =
                  value['lastSettlementPaymentReference']?.toString() ?? '';
              _lastSettlementAmount = firebaseIntValue(
                value['lastSettlementAmount'],
              );
              _lastSettlementOrderCount = firebaseIntValue(
                value['lastSettlementOrderCount'],
              );
            });
            _scheduleStoreSettlementPreview();
            _syncStoreDispatchTimers(_orders);
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleLiveStreamFailure(
              _StoreLiveResource.store,
              error,
              generation,
            );
          },
          onDone: () {
            _handleLiveStreamFailure(
              _StoreLiveResource.store,
              StateError('Store stream closed.'),
              generation,
              streamClosed: true,
            );
          },
          cancelOnError: true,
        );
  }

  void _listenToProducts() {
    final generation = _liveGeneration;
    _startInitialLiveEventWatchdog(_StoreLiveResource.products, generation);
    _productsSubscription = database
        .child('stores')
        .child(storeId)
        .child('products')
        .onValue
        .listen(
          (event) {
            if (_liveDisposed || !mounted || generation != _liveGeneration) {
              return;
            }
            _markLiveResourceReady(_StoreLiveResource.products, generation);
            final value = event.snapshot.value;
            final next = <StoreProduct>[];
            if (value is Map) {
              for (final entry in value.entries) {
                if (entry.value is! Map) continue;
                next.add(
                  StoreProduct.fromFirebase(
                    entry.key.toString(),
                    (entry.value as Map).map(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
                  ),
                );
              }
            }
            next.sort(compareStoreMenuProducts);
            if (!mounted || generation != _liveGeneration) return;
            setState(() => _products = next);
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleLiveStreamFailure(
              _StoreLiveResource.products,
              error,
              generation,
            );
          },
          onDone: () {
            _handleLiveStreamFailure(
              _StoreLiveResource.products,
              StateError('Products stream closed.'),
              generation,
              streamClosed: true,
            );
          },
          cancelOnError: true,
        );
  }

  void _listenToOrders() {
    final generation = _liveGeneration;
    _startInitialLiveEventWatchdog(_StoreLiveResource.orders, generation);
    _recentOrdersSnapshotReady = false;
    _operationalOrderRefsSnapshotReady = false;
    _referencedOperationalOrderIds.clear();
    _initializedOperationalOrderIds.clear();
    _ordersSubscription = database
        .child('operationalOrderRefs')
        .child('stores')
        .child(storeId)
        .limitToLast(150)
        .onValue
        .listen(
          (event) {
            if (_liveDisposed || !mounted || generation != _liveGeneration) {
              return;
            }
            _recentOrdersSnapshotReady = true;
            final value = event.snapshot.value;
            final contentSignature = sallaCollectionContentSignature(
              value,
              ignoredRecordKeys: _volatileOrderLocationFields,
            );
            if (contentSignature != _ordersContentSignature) {
              _ordersContentSignature = contentSignature;
              final next = <String, StoreOrder>{};
              if (value is Map) {
                for (final entry in value.entries) {
                  final order = _storeOrderFromRealtimeValue(
                    entry.key.toString(),
                    entry.value is Map
                        ? (entry.value as Map)['publicOrder']
                        : null,
                  );
                  if (order != null) {
                    next[order.databaseKey] = order;
                  }
                }
              }
              _recentOrdersById
                ..clear()
                ..addAll(next);
            }
            _publishMergedOrders(generation);
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleLiveStreamFailure(
              _StoreLiveResource.orders,
              error,
              generation,
            );
          },
          onDone: () {
            _handleLiveStreamFailure(
              _StoreLiveResource.orders,
              StateError('Orders stream closed.'),
              generation,
              streamClosed: true,
            );
          },
          cancelOnError: true,
        );
    _listenToOperationalOrderRefs(generation);
    _ensureStoreHistoryLoaded();
  }

  void _listenToOperationalOrderRefs(int generation) {
    _operationalOrderRefsSubscription = database
        .child('operationalOrderRefs')
        .child('stores')
        .child(storeId)
        .onValue
        .listen(
          (event) {
            if (_liveDisposed || !mounted || generation != _liveGeneration) {
              return;
            }
            final value = event.snapshot.value;
            final nextIds = <String>{};
            if (value is Map) {
              for (final entry in value.entries) {
                final orderId = entry.key.toString().trim();
                if (orderId.isNotEmpty && entry.value != null) {
                  nextIds.add(orderId);
                }
              }
            }

            final removedIds = _referencedOperationalOrderIds.difference(
              nextIds,
            );
            _referencedOperationalOrderIds
              ..clear()
              ..addAll(nextIds);
            _operationalOrderRefsSnapshotReady = true;

            for (final orderId in removedIds) {
              _operationalOrderListenerVersions[orderId] =
                  (_operationalOrderListenerVersions[orderId] ?? 0) + 1;
              final subscription = _operationalOrderSubscriptions.remove(
                orderId,
              );
              if (subscription != null) {
                unawaited(subscription.cancel());
              }
              _initializedOperationalOrderIds.remove(orderId);
              _operationalOrdersById.remove(orderId);
              _operationalOrderContentSignatures.remove(orderId);
              unawaited(_refreshFinishedStoreOrder(orderId, generation));
            }
            for (final orderId in nextIds) {
              _listenToOperationalOrder(orderId, generation);
            }
            _publishMergedOrders(generation);
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleLiveStreamFailure(
              _StoreLiveResource.orders,
              error,
              generation,
            );
          },
          onDone: () {
            _handleLiveStreamFailure(
              _StoreLiveResource.orders,
              StateError('Operational order references stream closed.'),
              generation,
              streamClosed: true,
            );
          },
          cancelOnError: true,
        );
  }

  void _listenToOperationalOrder(String orderId, int generation) {
    if (_operationalOrderSubscriptions.containsKey(orderId)) return;
    final listenerVersion =
        (_operationalOrderListenerVersions[orderId] ?? 0) + 1;
    _operationalOrderListenerVersions[orderId] = listenerVersion;
    final subscription = watchStorePublicOrder(orderId).listen(
      (value) {
        if (_liveDisposed ||
            !mounted ||
            generation != _liveGeneration ||
            _operationalOrderListenerVersions[orderId] != listenerVersion ||
            !_referencedOperationalOrderIds.contains(orderId)) {
          return;
        }
        _initializedOperationalOrderIds.add(orderId);
        final contentSignature = storeOperationalOrderContentSignature(value);
        if (_operationalOrderContentSignatures[orderId] != contentSignature) {
          _operationalOrderContentSignatures[orderId] = contentSignature;
          final order = _storeOrderFromRealtimeValue(orderId, value);
          if (order == null || _isTerminalStoreOrder(order)) {
            _operationalOrdersById.remove(orderId);
          } else {
            _operationalOrdersById[orderId] = order;
          }
        }
        _publishMergedOrders(generation);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_operationalOrderListenerVersions[orderId] != listenerVersion ||
            !_referencedOperationalOrderIds.contains(orderId)) {
          return;
        }
        _handleLiveStreamFailure(_StoreLiveResource.orders, error, generation);
      },
      onDone: () {
        if (_operationalOrderListenerVersions[orderId] != listenerVersion ||
            !_referencedOperationalOrderIds.contains(orderId)) {
          return;
        }
        _handleLiveStreamFailure(
          _StoreLiveResource.orders,
          StateError('Operational order stream closed.'),
          generation,
          streamClosed: true,
        );
      },
      cancelOnError: true,
    );
    _operationalOrderSubscriptions[orderId] = subscription;
  }

  StoreOrder? _storeOrderFromRealtimeValue(String orderId, Object? value) {
    if (value is! Map) return null;
    final data = value.map((key, value) => MapEntry(key.toString(), value));
    if (data['storeId']?.toString() != storeId ||
        storeOrderWasCancelledByCustomerBeforeAcceptance(data)) {
      return null;
    }
    return StoreOrder.fromFirebase(orderId, data);
  }

  Future<void> _refreshFinishedStoreOrder(
    String orderId,
    int generation,
  ) async {
    try {
      final value = await readStorePublicOrder(orderId);
      if (_liveDisposed ||
          !mounted ||
          generation != _liveGeneration ||
          _referencedOperationalOrderIds.contains(orderId))
        return;
      final order = _storeOrderFromRealtimeValue(orderId, value);
      if (order != null) _pagedOrdersById[orderId] = order;
      _publishedOrdersContentSignature = null;
      _publishMergedOrders(generation);
    } catch (_) {
      // History retry remains visible instead of assuming a missing response
      // means the order was deleted or an uncertain write failed.
      if (mounted && !_liveDisposed && generation == _liveGeneration) {
        setState(
          () =>
              _storeHistoryError = 'تعذر تحديث الطلب المكتمل. أعد تحميل السجل.',
        );
      }
    }
  }

  void _publishMergedOrders(int generation) {
    if (_liveDisposed ||
        !mounted ||
        generation != _liveGeneration ||
        !_recentOrdersSnapshotReady ||
        !_operationalOrderRefsSnapshotReady ||
        !_initializedOperationalOrderIds.containsAll(
          _referencedOperationalOrderIds,
        )) {
      return;
    }

    final merged = <String, StoreOrder>{
      ..._pagedOrdersById,
      ..._recentOrdersById,
      ..._operationalOrdersById,
    };
    final next = merged.values.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final operationalSignatures =
        _operationalOrderContentSignatures.entries.toList(growable: false)
          ..sort((left, right) => left.key.compareTo(right.key));
    final publishedSignature = <String>[
      _ordersContentSignature ?? '',
      ...(_pagedOrdersById.keys.toList(growable: false)..sort()),
      for (final entry in operationalSignatures) '${entry.key}:${entry.value}',
    ].join('|');
    if (publishedSignature == _publishedOrdersContentSignature) {
      if (_ordersLiveStatus != _StoreLiveStatus.ready ||
          _ordersLiveError.isNotEmpty) {
        _markLiveResourceReady(_StoreLiveResource.orders, generation);
      }
      return;
    }
    _publishedOrdersContentSignature = publishedSignature;
    _markLiveResourceReady(_StoreLiveResource.orders, generation);
    final settlementSignature =
        (next
                .map(
                  (order) =>
                      '${order.databaseKey}:${order.isStoreSettlementRecord}:'
                      '${order.storeSettlementPaid}:'
                      '${order.storeSettlementDisplayAmount}',
                )
                .toList()
              ..sort())
            .join('|');
    if (settlementSignature != _settlementOrdersContentSignature) {
      _settlementOrdersContentSignature = settlementSignature;
      _scheduleStoreSettlementPreview();
    }

    final pendingIds = next
        .where(_isNewStoreOrder)
        .map((order) => order.databaseKey)
        .toSet();
    final removedPendingIds = _ordersInitialized
        ? _knownPendingOrderIds.difference(pendingIds)
        : const <String>{};
    _knownPendingOrderIds = pendingIds;
    _ordersInitialized = true;
    for (final orderId in removedPendingIds) {
      unawaited(_cancelIncomingOrderAlert(orderId));
    }
    setState(
      () => _orders
        ..clear()
        ..addAll(next),
    );
    _syncStoreDispatchTimers(next);
  }

  Map<String, dynamic>? _initialStoreHistoryCursor() {
    // Live references contain active orders only, not the newest history page.
    return null;
  }

  void _ensureStoreHistoryLoaded() {
    if (!widget.enableRealtime ||
        _storeHistoryInitialized ||
        _storeHistoryLoading) {
      return;
    }
    unawaited(loadOlderStoreOrders());
  }

  Future<void> loadOlderStoreOrders({bool reset = false}) async {
    if (_storeHistoryLoading || _liveDisposed) return;
    final requestCursor = reset
        ? _initialStoreHistoryCursor()
        : (_storeHistoryInitialized
              ? _storeHistoryCursor
              : _initialStoreHistoryCursor());
    final generation = ++_storeHistoryGeneration;
    final authenticatedUid = sallaIdentity.uid;
    if (mounted) {
      setState(() {
        _storeHistoryLoading = true;
        _storeHistoryError = '';
        if (reset) {
          _pagedOrdersById.clear();
          _storeHistoryCursor = null;
          _storeHistoryHasMore = true;
          _storeHistoryInitialized = false;
        }
      });
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
            'getStoreOrderHistoryPage',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
          );
      final response = await callable
          .call<dynamic>(<String, dynamic>{
            'storeId': storeId,
            'pageSize': _storeHistoryPageSize,
            if (requestCursor != null) 'cursor': requestCursor,
          })
          .timeout(const Duration(seconds: 30));
      final rawPage = response.data;
      if (rawPage is! Map) {
        throw const FormatException('استجابة سجل الطلبات غير صالحة.');
      }
      final pageOrders = <String, StoreOrder>{};
      final rawOrders = rawPage['orders'];
      if (rawOrders is List) {
        for (final rawOrder in rawOrders) {
          if (rawOrder is! Map) continue;
          final data = rawOrder.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final orderKey = data['key']?.toString().trim() ?? '';
          if (orderKey.isEmpty || data['storeId']?.toString() != storeId) {
            continue;
          }
          final order = _storeOrderFromRealtimeValue(orderKey, data);
          if (order != null) pageOrders[orderKey] = order;
        }
      }
      final rawCursor = rawPage['nextCursor'];
      final nextCursor = rawCursor is Map
          ? rawCursor.map((key, value) => MapEntry(key.toString(), value))
          : null;
      final cursorAdvanced =
          nextCursor != null &&
          jsonEncode(nextCursor) != jsonEncode(requestCursor);
      if (!mounted ||
          _liveDisposed ||
          generation != _storeHistoryGeneration ||
          sallaIdentity.uid != authenticatedUid) {
        return;
      }
      setState(() {
        _pagedOrdersById.addAll(pageOrders);
        // A settlement can change while the terminal order has no live ref.
        // The same page keys are not proof of unchanged financial display.
        _publishedOrdersContentSignature = null;
        _storeHistoryCursor = nextCursor;
        _storeHistoryHasMore = rawPage['hasMore'] == true && cursorAdvanced;
        _storeHistoryInitialized = true;
      });
      _publishMergedOrders(_liveGeneration);
    } catch (error) {
      debugPrint('Store order history failed: $error');
      if (!mounted || _liveDisposed || generation != _storeHistoryGeneration) {
        return;
      }
      setState(() {
        _storeHistoryInitialized = true;
        _storeHistoryError =
            'تعذر تحميل طلبات أقدم. تحقق من الإنترنت ثم أعد المحاولة.';
      });
    } finally {
      if (mounted && !_liveDisposed && generation == _storeHistoryGeneration) {
        setState(() => _storeHistoryLoading = false);
      }
    }
  }

  bool _hasSameVisibleOrderState(StoreOrder left, StoreOrder right) {
    return left.databaseKey == right.databaseKey &&
        left.status == right.status &&
        left.storeStage == right.storeStage &&
        left.driverStage == right.driverStage &&
        left.dispatchStatus == right.dispatchStatus &&
        left.driverId == right.driverId &&
        left.offeredDriverId == right.offeredDriverId &&
        left.offerExpiresAt == right.offerExpiresAt &&
        left.storePaymentConfirmedAt == right.storePaymentConfirmedAt &&
        left.storeSettlementStatus == right.storeSettlementStatus;
  }

  void _applyCommittedOrderSnapshot(
    StoreOrder originalOrder,
    Object? rawValue,
  ) {
    if (!mounted || rawValue is! Map) return;
    final data = rawValue.map((key, value) => MapEntry(key.toString(), value));
    if (data['storeId']?.toString() != storeId) return;
    final savedOrder = StoreOrder.fromFirebase(originalOrder.databaseKey, data);
    _applyCommittedStoreOrder(originalOrder, savedOrder);
  }

  void _applyCommittedStoreOrder(
    StoreOrder originalOrder,
    StoreOrder savedOrder,
  ) {
    if (!mounted) return;
    final index = _orders.indexWhere(
      (item) => item.databaseKey == originalOrder.databaseKey,
    );
    if (index < 0) return;
    final visibleOrder = _orders[index];
    if (_hasSameVisibleOrderState(visibleOrder, savedOrder)) return;
    if (!_hasSameVisibleOrderState(visibleOrder, originalOrder)) {
      // The realtime stream already delivered a newer state. Keep it as the
      // final authority instead of replacing it with this transaction result.
      return;
    }
    setState(() {
      final currentIndex = _orders.indexWhere(
        (item) => item.databaseKey == originalOrder.databaseKey,
      );
      if (currentIndex < 0 ||
          !_hasSameVisibleOrderState(_orders[currentIndex], originalOrder)) {
        return;
      }
      _orders[currentIndex] = savedOrder;
      _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
    _syncStoreDispatchTimers(_orders);
  }

  void _syncStoreDispatchTimers(List<StoreOrder> orders) {
    // Firebase Functions own driver dispatch. The store app only writes prep
    // time, readiness, and auto-dispatch preferences so offers stay centralized.
    // No local timers are needed here. The operational Functions read the order
    // fields and schedule driver offers independently of the store app lifecycle.
  }

  int get _safeDispatchLeadMinutes => _dispatchLeadMinutes
      .clamp(minDispatchLeadMinutes, maxDispatchLeadMinutes)
      .toInt();

  String _dispatchLeadLabel(int minutes) {
    if (minutes <= 0) return 'عند جاهزية الطلب';
    if (minutes == 1) return 'قبل الجاهزية بدقيقة';
    return 'قبل الجاهزية بـ $minutes دقيقة';
  }

  String _driverRequestTextForPrep(int selectedMinutes) {
    if (!_autoDispatchEnabled) {
      return 'التوزيع التلقائي متوقف حالياً. لن يتم طلب السائقين إلا بعد تشغيله من الإعدادات.';
    }
    final leadMinutes = _safeDispatchLeadMinutes;
    if (leadMinutes == 0) {
      return 'سيتم طلب أقرب سائق عند جاهزية الطلب، بعد $selectedMinutes دقيقة تقريباً.';
    }
    final driverRequestMinutes = selectedMinutes - leadMinutes;
    if (driverRequestMinutes <= 0) {
      return 'سيتم طلب أقرب سائق فور قبول الطلب لأن نافذة الإرسال ${_dispatchLeadLabel(leadMinutes)}.';
    }
    return 'سيتم طلب أقرب سائق ${_dispatchLeadLabel(leadMinutes)}، أي بعد $driverRequestMinutes دقيقة تقريباً.';
  }

  Future<void> _cancelIncomingOrderAlert(String orderId) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _notificationsChannel.invokeMethod<void>('cancelUrgentAlert', {
        'orderId': normalizedOrderId,
      });
    } catch (_) {
      // The Firebase state is already correct even if Android removed the alert.
    }
  }

  Future<void> _cancelAllIncomingOrderAlerts() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _notificationsChannel.invokeMethod<void>('cancelAllUrgentAlerts');
    } catch (_) {
      // The canonical Firebase state remains authoritative during teardown.
    }
  }

  Future<void> _playRoutineFluxNotification() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _notificationsChannel.invokeMethod<void>('playFluxNotification');
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  bool _acceptStorePush(
    RemoteMessage message,
    SallaPushEventDeduplicator deduplicator,
  ) {
    final data = Map<String, dynamic>.from(message.data);
    return sallaPushTargetsCurrentAccount(
          data,
          role: 'store',
          entityId: storeId,
        ) &&
        deduplicator.accept(data, messageId: message.messageId ?? '');
  }

  Future<void> _configurePushNotifications() async {
    final ownerStoreId = storeId;
    final generation = ++_pushRegistrationGeneration;
    try {
      final messaging = FirebaseMessaging.instance;
      await _messagingTokenSubscription?.cancel();
      _messagingTokenSubscription = null;
      await _foregroundMessageSubscription?.cancel();
      _foregroundMessageSubscription = null;
      await _messageOpenedSubscription?.cancel();
      _messageOpenedSubscription = null;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveMessagingToken(
          token,
          expectedStoreId: ownerStoreId,
          expectedGeneration: generation,
        );
      }
      if (!mounted ||
          generation != _pushRegistrationGeneration ||
          ownerStoreId != storeId) {
        return;
      }
      _messagingTokenSubscription = messaging.onTokenRefresh.listen(
        (token) => unawaited(
          _saveMessagingToken(
            token,
            expectedStoreId: ownerStoreId,
            expectedGeneration: generation,
          ),
        ),
      );
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((
        message,
      ) {
        if (!_acceptStorePush(message, _foregroundPushDeduplicator)) return;
        final type = message.data['type']?.toString() ?? '';
        if (type == 'store_urgent_alert_resolved') {
          unawaited(
            _cancelIncomingOrderAlert(
              message.data['orderId']?.toString() ?? '',
            ),
          );
        } else if (type == 'store_driver_arrived' && mounted) {
          unawaited(_playRoutineFluxNotification());
          final body = message.notification?.body?.trim();
          _message(
            body?.isNotEmpty == true
                ? body!
                : 'وصل السائق إلى المتجر لاستلام الطلب',
          );
        }
      });
      _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _openOrderFromPushMessage,
      );
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        unawaited(_openOrderFromPushMessage(initialMessage));
      }
    } catch (_) {
      // Realtime order updates remain active if push registration is unavailable.
    }
  }

  Future<void> _openOrderFromPushMessage(RemoteMessage message) async {
    if (!_acceptStorePush(message, _openedPushDeduplicator)) return;
    final type = message.data['type']?.toString() ?? '';
    if (type == 'store_urgent_alert_resolved') {
      await _cancelIncomingOrderAlert(
        message.data['orderId']?.toString() ?? '',
      );
      return;
    }
    final orderKey = message.data['orderId']?.toString() ?? '';
    if (orderKey.isEmpty || !mounted) return;
    setState(() {
      _filter = 'active';
    });
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    final order = _orders.cast<StoreOrder?>().firstWhere(
      (item) =>
          item?.databaseKey == orderKey ||
          item?.number == message.data['orderNumber']?.toString(),
      orElse: () => null,
    );
    if (order == null) {
      try {
        final raw = await readStorePublicOrder(orderKey);
        if (raw != null) {
          final data = raw.map((key, value) => MapEntry(key.toString(), value));
          if (data['storeId']?.toString() == storeId) {
            _showOrderDetails(StoreOrder.fromFirebase(orderKey, data));
            return;
          }
        }
      } catch (error) {
        debugPrint('Open store order from push failed: $error');
      }
      _message('فتحنا صفحة الطلبات. انتظر لحظة حتى يظهر الطلب الجديد');
      return;
    }
    _showOrderDetails(order);
  }

  Future<void> _saveMessagingToken(
    String token, {
    required String expectedStoreId,
    required int expectedGeneration,
  }) async {
    if (!mounted ||
        token.trim().isEmpty ||
        expectedGeneration != _pushRegistrationGeneration ||
        expectedStoreId != storeId) {
      return;
    }
    await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('manageNotificationDevice')
        .call<dynamic>({
          'action': 'register',
          'role': 'store',
          'token': token,
          'platform': defaultTargetPlatform.name,
        })
        .timeout(const Duration(seconds: 12));
  }

  Future<void> _removeMessagingToken() async {
    _pushRegistrationGeneration += 1;
    _foregroundPushDeduplicator.clear();
    _openedPushDeduplicator.clear();
    final tokenSubscription = _messagingTokenSubscription;
    _messagingTokenSubscription = null;
    try {
      await tokenSubscription?.cancel();
    } catch (_) {}
    final foregroundSubscription = _foregroundMessageSubscription;
    _foregroundMessageSubscription = null;
    try {
      await foregroundSubscription?.cancel();
    } catch (_) {}
    final openedSubscription = _messageOpenedSubscription;
    _messageOpenedSubscription = null;
    try {
      await openedSubscription?.cancel();
    } catch (_) {}

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 6),
      );
    } catch (_) {
      token = null;
    }
    if (token != null && token.isNotEmpty) {
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('manageNotificationDevice')
            .call<dynamic>({
              'action': 'unregister',
              'role': 'store',
              'token': token,
              'platform': defaultTargetPlatform.name,
            })
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Local token deletion below still stops delivery to this installation.
      }
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Signing out must continue even if push cleanup fails.
    }
  }

  @override
  void dispose() {
    _liveDisposed = true;
    _storeHistoryGeneration += 1;
    _appIsResumed = false;
    WidgetsBinding.instance.removeObserver(this);
    if (!widget.isGuest &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      _sharedLocationChannel.setMethodCallHandler(null);
    }
    _paymentHoldController.dispose();
    _liveRetryTimer?.cancel();
    _liveRetryTimer = null;
    _cancelAllInitialLiveEventWatchdogs();
    _settlementPreviewTimer?.cancel();
    _settlementPreviewTimer = null;
    _authStateSubscription?.cancel();
    _authStateSubscription = null;
    unawaited(_cancelLiveSubscriptions());
    _messagingTokenSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
    if (!widget.isGuest) unawaited(_cancelAllIncomingOrderAlerts());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.isGuest) return;
    if (state == AppLifecycleState.resumed) {
      _appIsResumed = true;
      _lastSharedLocationFailureId = '';
      unawaited(_inspectPendingSharedLocation());
      _requestLiveRestart(resetAttempt: true, refreshToken: true);
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appIsResumed = false;
      _liveRetryTimer?.cancel();
      _liveRetryTimer = null;
      _cancelAllInitialLiveEventWatchdogs();
    }
  }

  void _startPaymentConfirmationHold(StoreOrder order) {
    final canConfirm =
        !order.isCancelled &&
        !order.isDelivered &&
        const {
          'accepted',
          'preparing',
          'readyForPickup',
        }.contains(order.storeStage) &&
        order.driverStage == 'arrivedStore' &&
        order.driverId.trim().isNotEmpty &&
        order.storePaymentConfirmedAt.trim().isEmpty;
    if (_busy || !canConfirm) return;
    _cancelPaymentConfirmationHold();
    HapticFeedback.selectionClick();
    setState(() {
      _paymentHoldOrderKey = order.databaseKey;
      _paymentHoldOrder = order;
    });
    _paymentHoldController.forward(from: 0);
  }

  void _cancelPaymentConfirmationHold() {
    if (_paymentHoldController.status == AnimationStatus.completed) return;
    _paymentHoldController.stop();
    _paymentHoldController.reset();
    if (!mounted) return;
    if (_paymentHoldOrderKey.isEmpty) return;
    setState(() {
      _paymentHoldOrderKey = '';
      _paymentHoldOrder = null;
    });
  }

  Future<void> _confirmDeferredReturn(
    StoreOrder order, {
    required bool goodsComplete,
  }) async {
    if (_busy || !order.usesDeferredSettlement) return;
    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('confirmDeferredOrderReturn');
      final response = await waitForFirebaseResult(
        callable.call<Map<String, dynamic>>({
          'orderId': order.databaseKey,
          'goodsComplete': goodsComplete,
          'note': goodsComplete
              ? 'استلم المتجر المواد كاملة'
              : 'أبلغ المتجر عن نقص في المواد المرتجعة',
        }),
        debugLabel: 'Confirm deferred order return',
        timeout: const Duration(seconds: 25),
      );
      if (response == null) {
        _message('انتهت مهلة التأكيد. تحقق من الاتصال ثم حاول مرة أخرى.');
        return;
      }
      final savedOrder = await readStorePublicOrder(order.databaseKey);
      if (savedOrder != null) _applyCommittedOrderSnapshot(order, savedOrder);
      if (!mounted) return;
      _message(
        goodsComplete
            ? 'تم تأكيد وصول المواد وإغلاق الطلب مالياً'
            : 'تم تسجيل النقص وتحويل الطلب إلى مراجعة الإدارة',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      _message(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'تعذر تأكيد الإرجاع. تحقق من حالة الطلب وحاول مرة أخرى.',
      );
    } catch (error) {
      debugPrint('Deferred order return confirmation failed: $error');
      if (mounted) {
        _message('تعذر تأكيد الإرجاع. تحقق من الاتصال وحاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _storeOrderActionRequestId(StoreOrder order, String action) {
    final seed =
        '${order.databaseKey}|$action|${order.updatedAt.trim()}|store_action_v1';
    var hash = 0x811C9DC5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final safeOrderId = order.databaseKey
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .substring(0, order.databaseKey.length.clamp(0, 72).toInt());
    return 'store_${action}_${safeOrderId}_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  bool _storeActionIsApplied(StoreOrder order, String action) {
    return switch (action) {
      'accept' =>
        order.storeStage != 'awaitingAcceptance' && order.status != 'cancelled',
      'reject' => order.status == 'cancelled' && order.storeStage == 'rejected',
      'ready' => const {
        'readyForPickup',
        'handedToDriver',
      }.contains(order.storeStage),
      'confirm_driver_payment' => order.storePaymentConfirmedAt.isNotEmpty,
      _ => false,
    };
  }

  Future<StoreOrder?> _readLatestStoreOrder(StoreOrder order) async {
    final value = await readStorePublicOrder(order.databaseKey);
    if (value == null) return null;
    final data = value.map(
      (key, mapValue) => MapEntry(key.toString(), mapValue),
    );
    if (data['storeId']?.toString() != storeId) return null;
    return StoreOrder.fromFirebase(order.databaseKey, data);
  }

  Future<StoreOrder?> _performStoreOrderAction(
    StoreOrder originalOrder,
    String action, {
    String rejectionReason = '',
    int? prepMinutes,
  }) async {
    var sourceOrder = originalOrder;
    if (sourceOrder.updatedAt.trim().isEmpty) {
      sourceOrder = await _readLatestStoreOrder(originalOrder) ?? originalOrder;
    }
    final expectedUpdatedAt = sourceOrder.updatedAt.trim();
    if (expectedUpdatedAt.isEmpty) {
      throw StateError('تعذر التحقق من آخر تحديث للطلب.');
    }
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'performStoreOrderAction',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
        );
    final payload = <String, dynamic>{
      'orderId': sourceOrder.databaseKey,
      'action': action,
      'requestId': _storeOrderActionRequestId(sourceOrder, action),
      'expectedUpdatedAt': expectedUpdatedAt,
      if (rejectionReason.trim().isNotEmpty)
        'rejectionReason': rejectionReason.trim(),
      if (prepMinutes != null) 'prepMinutes': prepMinutes,
    };
    final response = await waitForFirebaseResult(
      callable.call<dynamic>(payload),
      debugLabel: 'Store order action $action',
      timeout: const Duration(seconds: 30),
    );
    if (response != null) {
      final responseData = response.data;
      if (responseData is Map && responseData['order'] is Map) {
        final orderData = (responseData['order'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final saved = StoreOrder.fromFirebase(
          sourceOrder.databaseKey,
          orderData,
        );
        _applyCommittedOrderSnapshot(originalOrder, orderData);
        return saved;
      }
    }
    final latest = await _readLatestStoreOrder(originalOrder);
    if (latest != null) {
      _applyCommittedStoreOrder(originalOrder, latest);
      if (_storeActionIsApplied(latest, action)) return latest;
    }
    return null;
  }

  Future<void> _updateOrder(
    StoreOrder order,
    String action, {
    String rejectionReason = '',
    int? prepMinutes,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selectedPrepMinutes = (prepMinutes ?? _prepMinutes)
          .clamp(minPrepMinutes, maxPrepMinutes)
          .toInt();
      final committedOrder = await _performStoreOrderAction(
        order,
        action,
        rejectionReason: rejectionReason,
        prepMinutes: action == 'accept' ? selectedPrepMinutes : null,
      );
      if (!mounted) return;
      final committed = committedOrder != null;
      if (committed && (action == 'accept' || action == 'reject')) {
        unawaited(_cancelIncomingOrderAlert(order.databaseKey));
      }
      _message(
        committed
            ? 'تم تحديث الطلب ${order.number}'
            : 'لم يصل تأكيد التحديث. حدّث الطلب ثم أعد المحاولة بنفس الإجراء.',
        error: !committed,
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      _message(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'تعذر تنفيذ إجراء الطلب. حدّث الحالة وحاول مرة أخرى.',
        error: true,
      );
    } catch (error, stackTrace) {
      debugPrint('Store order action failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _message(
          'تعذر تحديث الطلب. تحقق من الاتصال وحاول مرة أخرى.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDriverPayment(StoreOrder order) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final committedOrder = await _performStoreOrderAction(
        order,
        'confirm_driver_payment',
      );
      if (!mounted) return;
      final committed = committedOrder != null;
      _message(
        committed
            ? 'تم تأكيد دفع السائق للطلب ${order.number}'
            : 'لم يصل تأكيد الدفع. حدّث الطلب ثم أعد المحاولة.',
        error: !committed,
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      _message(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'تعذر تأكيد دفع السائق. حدّث الطلب وحاول مجدداً.',
        error: true,
      );
    } catch (error, stackTrace) {
      debugPrint('Store driver payment confirmation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _message(
          'تعذر تأكيد دفع السائق. تحقق من الاتصال وحاول مجدداً.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setOnline(bool value) async {
    if (widget.isGuest) {
      await _guestAccess();
      return;
    }
    if (_storeLockedByAdmin) {
      _message('حالة المتجر مقفلة من الإدارة حالياً', error: true);
      return;
    }
    if (_storeStatusUpdating) return;
    await _storeOperationalIntentRestoreFuture;
    if (_storeOperationalIntentRestoreError != null) {
      _message(
        'تعذر استعادة معرّف محاولة حالة المتجر بأمان. أعد فتح التطبيق.',
        error: true,
      );
      return;
    }
    if (!mounted) return;
    final requestedAction = value ? 'open' : 'close';
    final pendingAction = _pendingStoreOperationalRequestIds.isEmpty
        ? ''
        : _pendingStoreOperationalRequestIds.keys.first;
    final action = pendingAction.isEmpty ? requestedAction : pendingAction;
    if (action == 'close' && _hasActiveStoreOrders) {
      _message(
        'لا يمكن جعل المتجر غير متصل قبل إنهاء أو إلغاء الطلبات النشطة',
        error: true,
      );
      return;
    }
    if (pendingAction.isNotEmpty) {
      _message(
        action == 'open'
            ? 'جارٍ استكمال مزامنة فتح المتجر السابقة أولاً'
            : 'جارٍ استكمال مزامنة إيقاف المتجر السابقة أولاً',
      );
    }
    final requestId = _pendingStoreOperationalRequestIds.putIfAbsent(
      action,
      () => 'store_${action}_${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      setState(() => _storeStatusUpdating = true);
      await _persistStoreOperationalIntent(
        action: action,
        requestId: requestId,
      );
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
            'setStoreOperationalAvailability',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          );
      final result = await callable.call<Map<String, dynamic>>({
        'storeId': storeId,
        'action': action,
        'requestId': requestId,
      });
      if (result.data['ok'] != true) {
        throw StateError('لم يؤكد الخادم حالة المتجر.');
      }
      await _clearPersistedStoreOperationalIntent();
      _pendingStoreOperationalRequestIds.remove(action);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      _message(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'تعذر تحديث حالة المتجر بأمان.',
        error: true,
      );
    } catch (_) {
      if (mounted) {
        _message('تعذر تحديث حالة المتجر. تحقق من الاتصال.', error: true);
      }
    } finally {
      if (mounted) setState(() => _storeStatusUpdating = false);
    }
  }

  void _showUncertainMutationMessage(String subject) {
    _message(
      'انتهت مهلة تحديث $subject والنتيجة غير مؤكدة. انتظر إعادة القراءة اللحظية قبل المحاولة مجدداً؛ لن يعيد التطبيق الكتابة تلقائياً.',
      error: true,
    );
  }

  Future<void> _setPrepMinutes(int value) async {
    final safeValue = value.clamp(minPrepMinutes, maxPrepMinutes).toInt();
    const actionKey = 'prep_minutes';
    if (_busyStoreSettingKeys.contains(actionKey) ||
        safeValue == _prepMinutes) {
      return;
    }
    setState(() => _busyStoreSettingKeys.add(actionKey));
    try {
      final now = sallaUtcNowIso();
      await database
          .update({
            'stores/$storeId/prepMinutes': safeValue,
            'stores/$storeId/updatedAt': now,
            'storeCatalog/$storeId/prepMinutes': safeValue,
            'storeCatalog/$storeId/updatedAt': ServerValue.timestamp,
            'storeCatalogPublic/$storeId/prepMinutes': safeValue,
            'storeCatalogPublic/$storeId/updatedAt': ServerValue.timestamp,
          })
          .timeout(_storeMutationWriteTimeout);
      if (mounted) _message('تم تحديث وقت التحضير');
    } on TimeoutException {
      if (mounted) {
        _showUncertainMutationMessage('وقت التحضير');
      }
    } catch (error) {
      debugPrint('Store prep minutes update failed: $error');
      if (mounted) {
        _message('تعذر تحديث وقت التحضير. تحقق من الاتصال.', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busyStoreSettingKeys.remove(actionKey));
      }
    }
  }

  Future<void> _setAutoDispatchEnabled(bool value) async {
    const actionKey = 'auto_dispatch';
    if (_busyStoreSettingKeys.contains(actionKey) ||
        value == _autoDispatchEnabled) {
      return;
    }
    setState(() => _busyStoreSettingKeys.add(actionKey));
    try {
      final now = sallaUtcNowIso();
      await database
          .update({
            'stores/$storeId/autoDispatchEnabled': value,
            'stores/$storeId/updatedAt': now,
          })
          .timeout(_storeMutationWriteTimeout);
      if (mounted) {
        _message(
          value ? 'تم تشغيل التوزيع التلقائي' : 'تم إيقاف التوزيع التلقائي',
        );
      }
    } on TimeoutException {
      if (mounted) {
        _showUncertainMutationMessage('التوزيع التلقائي');
      }
    } catch (error) {
      debugPrint('Store auto dispatch update failed: $error');
      if (mounted) {
        _message('تعذر تحديث التوزيع التلقائي. تحقق من الاتصال.', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busyStoreSettingKeys.remove(actionKey));
      }
    }
  }

  Future<void> _setDispatchLeadMinutes(int value) async {
    final safeValue = value
        .clamp(minDispatchLeadMinutes, maxDispatchLeadMinutes)
        .toInt();
    const actionKey = 'dispatch_lead_minutes';
    if (_busyStoreSettingKeys.contains(actionKey) ||
        safeValue == _dispatchLeadMinutes) {
      return;
    }
    setState(() => _busyStoreSettingKeys.add(actionKey));
    try {
      final now = sallaUtcNowIso();
      await database
          .update({
            'stores/$storeId/dispatchLeadMinutes': safeValue,
            'stores/$storeId/updatedAt': now,
          })
          .timeout(_storeMutationWriteTimeout);
      if (mounted) _message('تم تحديث توقيت إرسال الطلب للسائقين');
    } on TimeoutException {
      if (mounted) {
        _showUncertainMutationMessage('توقيت إرسال الطلب للسائقين');
      }
    } catch (error) {
      debugPrint('Store dispatch lead update failed: $error');
      if (mounted) {
        _message('تعذر تحديث توقيت التوزيع. تحقق من الاتصال.', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busyStoreSettingKeys.remove(actionKey));
      }
    }
  }

  Future<void> _setProductAvailability(
    StoreProduct product,
    bool available,
  ) async {
    if (_busyProductIds.contains(product.id) ||
        product.available == available) {
      return;
    }
    await _runStoreMenuMutation(
      product: product,
      action: 'setProductAvailability',
      valueKey: 'available',
      value: available,
      successMessage: available
          ? 'أصبح المنتج متاحاً للطلب'
          : 'تم إيقاف المنتج مؤقتاً',
    );
  }

  String _storeMenuRequestId(
    StoreProduct product,
    String action,
    Object value,
  ) {
    String safe(String input) =>
        input.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    return [
      'store_menu',
      safe(action),
      safe(storeId),
      safe(product.id),
      product.revision,
      safe(value.toString()),
      DateTime.now().microsecondsSinceEpoch,
    ].join('_');
  }

  void _applyStoreMenuMutationResponse(
    StoreProduct previous,
    Map<dynamic, dynamic> response,
  ) {
    final rawProduct = response['product'];
    if (rawProduct is! Map || !mounted) return;
    final productData = <String, dynamic>{...previous.toMap()}
      ..addAll(rawProduct.map((key, value) => MapEntry(key.toString(), value)));
    productData['revision'] ??= response['revision'];
    final updated = StoreProduct.fromFirebase(previous.id, productData);
    setState(() {
      final index = _products.indexWhere((item) => item.id == previous.id);
      if (index < 0) return;
      _products[index] = updated;
      _products.sort(compareStoreMenuProducts);
    });
  }

  String _safeStoreMenuFunctionMessage(FirebaseFunctionsException error) {
    final raw = error.message?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim() ?? '';
    if (raw.isEmpty || raw.length > 220 || raw.contains('://')) {
      return 'تعذر تنفيذ التغيير المطلوب في قائمة المتجر.';
    }
    return raw;
  }

  String _storeMenuFunctionReason(FirebaseFunctionsException error) {
    final details = error.details;
    if (details is! Map) return '';
    return details['reason']?.toString().trim() ?? '';
  }

  Future<void> _runStoreMenuMutation({
    required StoreProduct product,
    required String action,
    required String valueKey,
    required Object value,
    required String successMessage,
    String? requestId,
  }) async {
    if (_busyProductIds.contains(product.id)) return;
    final operationRequestId =
        requestId ?? _storeMenuRequestId(product, action, value);
    setState(() => _busyProductIds.add(product.id));
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
            'manageStoreMenu',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
          );
      final result = await callable
          .call<dynamic>(<String, dynamic>{
            'action': action,
            'storeId': storeId,
            'productId': product.id,
            valueKey: value,
            'expectedRevision': product.revision,
            'requestId': operationRequestId,
          })
          .timeout(const Duration(seconds: 30));
      final response = result.data;
      if (response is! Map || response['ok'] != true) {
        throw const FormatException('استجابة تحديث قائمة المتجر غير صالحة.');
      }
      _applyStoreMenuMutationResponse(product, response);
      if (mounted) _message(successMessage);
    } on TimeoutException {
      if (mounted) {
        _showUncertainMutationMessage('قائمة المتجر');
      }
    } on FirebaseFunctionsException catch (error) {
      debugPrint('Store menu mutation failed (${error.code}).');
      if (!mounted) return;
      final reason = _storeMenuFunctionReason(error);
      final conflict =
          error.code == 'aborted' || reason == 'store_menu_stale_revision';
      final canRetry = const {
        'internal',
        'resource-exhausted',
        'unavailable',
        'unknown',
      }.contains(error.code);
      final serverMessage =
          const {
            'failed-precondition',
            'invalid-argument',
            'not-found',
            'permission-denied',
          }.contains(error.code)
          ? _safeStoreMenuFunctionMessage(error)
          : '';
      _message(
        conflict
            ? 'تغير المنتج من جهاز آخر. انتظر التحديث الحي ثم حاول مجدداً.'
            : serverMessage.isNotEmpty
            ? serverMessage
            : 'تعذر تحديث قائمة المتجر. تحقق من الاتصال وأعد المحاولة.',
        error: true,
        actionLabel: canRetry ? 'إعادة المحاولة' : null,
        onAction: canRetry
            ? () => _runStoreMenuMutation(
                product: product,
                action: action,
                valueKey: valueKey,
                value: value,
                successMessage: successMessage,
                requestId: operationRequestId,
              )
            : null,
      );
    } catch (error) {
      debugPrint('Store menu mutation response failed: $error');
      if (mounted) {
        _message(
          'تعذر تأكيد تحديث قائمة المتجر. أعد المحاولة.',
          error: true,
          actionLabel: 'إعادة المحاولة',
          onAction: () => _runStoreMenuMutation(
            product: product,
            action: action,
            valueKey: valueKey,
            value: value,
            successMessage: successMessage,
            requestId: operationRequestId,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyProductIds.remove(product.id));
      }
    }
  }

  Future<void> _setProductStockQuantity(
    StoreProduct product,
    int stockQuantity,
  ) async {
    final safeStock = stockQuantity < 0
        ? -1
        : stockQuantity.clamp(0, 9999).toInt();
    await _runStoreMenuMutation(
      product: product,
      action: 'setProductStock',
      valueKey: 'stockQuantity',
      value: safeStock,
      successMessage: safeStock == 0
          ? 'تم تسجيل نفاد المنتج وإيقاف توفره تلقائياً'
          : product.available
          ? 'تم تحديث مخزون المنتج'
          : 'تم تحديث المخزون. فعّل توفر المنتج بخطوة مستقلة عند جاهزيته.',
    );
  }

  String _productOfferRequestId(StoreProduct product) {
    String safe(String value) =>
        value.replaceAll(RegExp(r'[.#$\[\]/]'), '_').trim();
    return [
      'store_offer',
      safe(storeId),
      safe(product.id),
      DateTime.now().microsecondsSinceEpoch,
    ].join('_');
  }

  Future<void> _saveProductOffer(
    StoreProduct product, {
    required bool enabled,
    required int offerPrice,
    required int offerEndsAtMs,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'setProductOffer',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        );
    final result = await callable.call(<String, dynamic>{
      'storeId': storeId,
      'productId': product.id,
      'requestId': _productOfferRequestId(product),
      'offer': enabled,
      'offerPrice': enabled ? offerPrice : null,
      'offerFunding': enabled ? 'store' : null,
      'offerStartsAtMs': null,
      'offerEndsAtMs': enabled && offerEndsAtMs > 0 ? offerEndsAtMs : null,
      'expectedRevision': product.offerRevision,
    });
    final data = result.data;
    if (data is! Map || data['ok'] != true) {
      throw StateError('لم يؤكد الخادم حفظ العرض');
    }
  }

  void _showProductOfferSheet(StoreProduct product) {
    final priceController = TextEditingController(
      text: product.offerPrice > 0
          ? formatStoreAmountInput('${product.offerPrice}')
          : '',
    );
    var enabled = product.offer;
    var offerEndsAtMs = product.offerEndsAtMs;
    var saving = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            String endDateLabel() {
              if (offerEndsAtMs <= 0) return 'بلا نهاية محددة';
              final date = DateTime.fromMillisecondsSinceEpoch(
                offerEndsAtMs,
              ).subtract(const Duration(milliseconds: 1));
              return 'حتى ${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  20 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'عرض ${product.name}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'العرض ممول من المتجر، ويعتمده الخادم في الفاتورة ولا يُجمع مع قسيمة SALLA10.',
                      style: TextStyle(
                        color: mutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: enabled,
                      activeThumbColor: appColor,
                      title: const Text(
                        'تفعيل العرض',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        'السعر الأساسي ${formatIqd(product.price)}',
                      ),
                      onChanged: (value) =>
                          setSheetState(() => enabled = value),
                    ),
                    if (enabled) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: priceController,
                        textDirection: TextDirection.ltr,
                        inputFormatters: const [StoreAmountInputFormatter()],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'سعر العرض بالدينار',
                          prefixIcon: const Icon(Icons.local_offer_rounded),
                          filled: true,
                          fillColor: bgColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final now = DateTime.now();
                                final current = offerEndsAtMs > 0
                                    ? DateTime.fromMillisecondsSinceEpoch(
                                        offerEndsAtMs,
                                      ).subtract(const Duration(days: 1))
                                    : now.add(const Duration(days: 7));
                                final selected = await showDatePicker(
                                  context: sheetContext,
                                  initialDate: current,
                                  firstDate: now,
                                  lastDate: now.add(const Duration(days: 365)),
                                  helpText: 'آخر يوم للعرض',
                                );
                                if (selected == null || !sheetContext.mounted) {
                                  return;
                                }
                                setSheetState(() {
                                  offerEndsAtMs = DateTime(
                                    selected.year,
                                    selected.month,
                                    selected.day + 1,
                                  ).millisecondsSinceEpoch;
                                });
                              },
                              icon: const Icon(Icons.event_busy_rounded),
                              label: Text(endDateLabel()),
                            ),
                          ),
                          if (offerEndsAtMs > 0) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'إزالة نهاية العرض',
                              onPressed: () =>
                                  setSheetState(() => offerEndsAtMs = 0),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final offerPrice =
                                  parseStoreAmountInput(priceController.text) ??
                                  0;
                              if (enabled &&
                                  (offerPrice <= 0 ||
                                      offerPrice >= product.price)) {
                                _message(
                                  'سعر العرض يجب أن يكون أقل من السعر الأساسي',
                                  error: true,
                                );
                                return;
                              }
                              setSheetState(() => saving = true);
                              try {
                                await _saveProductOffer(
                                  product,
                                  enabled: enabled,
                                  offerPrice: offerPrice,
                                  offerEndsAtMs: offerEndsAtMs,
                                );
                                if (!mounted || !sheetContext.mounted) return;
                                Navigator.pop(sheetContext);
                                _message(
                                  enabled ? 'تم حفظ العرض' : 'تم إيقاف العرض',
                                );
                              } on FirebaseFunctionsException catch (error) {
                                if (!mounted) return;
                                _message(
                                  error.message?.trim().isNotEmpty == true
                                      ? error.message!.trim()
                                      : 'تعذر حفظ العرض',
                                  error: true,
                                );
                              } catch (_) {
                                if (mounted) {
                                  _message('تعذر حفظ العرض', error: true);
                                }
                              } finally {
                                if (sheetContext.mounted) {
                                  setSheetState(() => saving = false);
                                }
                              }
                            },
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(saving ? 'جارٍ الحفظ...' : 'حفظ العرض'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _message(
    String text, {
    bool error = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : appColor,
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              ),
      ),
    );
  }

  bool _isTerminalStoreOrder(StoreOrder order) =>
      order.isCancelled || order.isDelivered;

  bool _isNewStoreOrder(StoreOrder order) =>
      !_isTerminalStoreOrder(order) && order.storeStage == 'awaitingAcceptance';

  bool _isReadyStoreOrder(StoreOrder order) =>
      !_isTerminalStoreOrder(order) && order.storeStage == 'readyForPickup';

  bool _isReturningStoreOrder(StoreOrder order) =>
      !_isTerminalStoreOrder(order) && order.storeStage == 'returningToStore';

  bool _needsStoreAction(StoreOrder order) =>
      _isNewStoreOrder(order) ||
      _isReadyStoreOrder(order) ||
      _isReturningStoreOrder(order);

  List<StoreOrder> get _visibleOrders {
    return _orders.where((order) {
      if (_filter == 'new') return _isNewStoreOrder(order);
      if (_filter == 'ready') return _isReadyStoreOrder(order);
      if (_filter == 'returning') return _isReturningStoreOrder(order);
      if (_filter == 'completed') {
        return !order.isCancelled && order.isDelivered;
      }
      if (_filter == 'cancelled') return order.isCancelled;
      return !_isTerminalStoreOrder(order);
    }).toList();
  }

  bool get _hasActiveStoreOrders {
    return _orders.any((order) => !_isTerminalStoreOrder(order));
  }

  Future<void> _requestSignOut() async {
    if (_hasActiveStoreOrders) {
      _message(
        'لا يمكن تسجيل الخروج قبل إنهاء أو إلغاء الطلبات النشطة',
        error: true,
      );
      return;
    }
    final shouldSignOut = await showSallaLifecycleSafeDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تسجيل الخروج'),
            content: const Text(
              'هل تريد تسجيل الخروج من حساب المتجر؟ لن تصلك إشعارات طلبات هذا المتجر بعد الخروج.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('تسجيل الخروج'),
                style: FilledButton.styleFrom(backgroundColor: appColor),
              ),
            ],
          ),
        );
      },
    );
    if (shouldSignOut != true) return;
    await _cancelAllIncomingOrderAlerts();
    await _removeMessagingToken();
    await SallaAuthService.signOut();
  }

  String get _storeHeaderStatusLabel {
    if (_storeLiveStatus == _StoreLiveStatus.loading) {
      return 'جاري تحديث حالة المتجر...';
    }
    if (_storeLiveStatus == _StoreLiveStatus.error) {
      return 'تعذر تحديث حالة المتجر';
    }
    return storeReadyHeaderStatusLabel(
      storeStatus: _storeStatus,
      storeLockedByAdmin: _storeLockedByAdmin,
      networkAssignmentPending: _networkAssignmentPending,
      customerZoneMode: _customerZoneMode,
      storeExternalDeliveryEnabled: _storeExternalDeliveryEnabled,
      online: _online,
    );
  }

  bool get _courierOnlyChannelReady => storeCourierOnlyChannelReady(
    storeStatus: _storeStatus,
    storeLockedByAdmin: _storeLockedByAdmin,
    networkAssignmentPending: _networkAssignmentPending,
    customerZoneMode: _customerZoneMode,
    storeExternalDeliveryEnabled: _storeExternalDeliveryEnabled,
  );

  bool get _courierOnlyAwaitingApproval =>
      !_networkAssignmentPending &&
      _customerZoneMode == 'hidden' &&
      _storeExternalDeliveryEnabled &&
      _storeLockedByAdmin;

  Color get _storeHeaderStatusColor {
    if (_storeLiveStatus == _StoreLiveStatus.loading) return Colors.orange;
    if (_storeLiveStatus == _StoreLiveStatus.error) return Colors.red;
    if (_networkAssignmentPending) return Colors.orange;
    if (_courierOnlyChannelReady) return appColor;
    if (_courierOnlyAwaitingApproval) return Colors.orange;
    return _online ? appColor : Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.isGuest ? const ValueKey('store_guest_orders_home') : null,
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isGuest ? 'متجر تجريبي' : storeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: darkText,
                fontSize: 19,
              ),
            ),
            Text(
              widget.isGuest
                  ? 'وضع الاستكشاف · دون حساب'
                  : _storeHeaderStatusLabel,
              style: TextStyle(
                color: _storeHeaderStatusColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          _storeStatusPill(),
          PopupMenuButton<int>(
            tooltip: 'المزيد',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (widget.isGuest && value != 1) {
                unawaited(_guestAccess());
                return;
              }
              setState(() => _pageIndex = value);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 1,
                child: ListTile(
                  leading: Icon(Icons.receipt_long_rounded),
                  title: Text('الطلبات'),
                ),
              ),
              PopupMenuItem(
                value: 0,
                child: ListTile(
                  leading: Icon(Icons.analytics_rounded),
                  title: Text('نظرة عامة'),
                ),
              ),
              PopupMenuItem(
                value: 2,
                child: ListTile(
                  leading: Icon(Icons.inventory_2_rounded),
                  title: Text('المنتجات والمخزون'),
                ),
              ),
              PopupMenuItem(
                value: 3,
                child: ListTile(
                  leading: Icon(Icons.settings_rounded),
                  title: Text('إعدادات المتجر'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: widget.isGuest
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onGuestLogin,
                        child: const Text('تسجيل الدخول'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _guestApply,
                        child: const Text('إنشاء حساب'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          if (_pageIndex == 0 || _pageIndex == 1)
            _storeExternalDeliveryBanner(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_pageIndex),
                child: buildSelectedStorePage(
                  pageIndex: _pageIndex,
                  dashboardBuilder: _dashboard,
                  ordersBuilder: _ordersPage,
                  productsBuilder: _productsPage,
                  settingsBuilder: _settingsPage,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _guestApply() {
    if (widget.onGuestApply != null) {
      widget.onGuestApply!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StoreApplicationPage()),
    );
  }

  bool _guestPromptOpen = false;
  Future<void> _guestAccess() async {
    if (!widget.isGuest || _guestPromptOpen || !mounted) return;
    _guestPromptOpen = true;
    try {
      await showStoreGuestAccess(
        context,
        onLogin: widget.onGuestLogin!,
        onApply: _guestApply,
      );
    } finally {
      _guestPromptOpen = false;
    }
  }

  Widget _storeExternalDeliveryBanner() {
    if (_networkAssignmentPending) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 3),
        child: Container(
          key: const ValueKey<String>('store_pending_network_assignment'),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF97316)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: Color(0xFFF97316)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الحساب مربوط وبانتظار اعتماد الإدارة',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _storeStatusReason.isNotEmpty
                    ? '$_storeStatusReason. ستتمكن من إنشاء طلب مندوبك بعد أن تعيّن الإدارة الفرع والزون وتعتمد التشغيل.'
                    : 'ستتمكن من إنشاء طلب مندوبك بعد أن تعيّن الإدارة الفرع والزون وتعتمد التشغيل.',
                style: const TextStyle(
                  color: Color(0xFF9A3412),
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 3),
      child: Semantics(
        button: true,
        label: 'طلب مندوبك لإنشاء طلب جديد',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey<String>('store_request_your_courier_banner'),
            onTap: _busy ? null : () => unawaited(_openStoreExternalDelivery()),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF0F8F80), Color(0xFF0B5F68)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF0A746E)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0B5F68).withValues(alpha: 0.27),
                    blurRadius: 22,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 86,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF5EEAD4), Color(0xFF2DD4BF)],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        10,
                        12,
                        12,
                        12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.09),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.delivery_dining_rounded,
                              color: Colors.white,
                              size: 31,
                            ),
                          ),
                          const SizedBox(width: 11),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'طلب مندوبك',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 19,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'أنشئ طلباً لمندوب سلة بخطوات واضحة',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFFD8F6F1),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.bolt_rounded,
                                      color: Color(0xFFFFD166),
                                      size: 14,
                                    ),
                                    SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        'فوري حسب المسافة',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Color(0xFFFFE8AF),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 7),
                                    Icon(
                                      Icons.schedule_rounded,
                                      color: Color(0xFF99F6E4),
                                      size: 13,
                                    ),
                                    SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        'مجدول 5,000',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Color(0xFFCFFFF6),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _busy
                                ? const SizedBox(
                                    key: ValueKey<String>(
                                      'store_request_courier_busy',
                                    ),
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Container(
                                    key: const ValueKey<String>(
                                      'store_request_courier_ready',
                                    ),
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x24000000),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.arrow_back_rounded,
                                      color: appColor,
                                      size: 23,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, String>?> _pendingSharedLocation() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final raw = await _sharedLocationChannel.invokeMethod<Object?>(
      'peekPending',
    );
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final text = raw['text']?.toString().trim() ?? '';
    if (id.isEmpty || text.isEmpty) return null;
    return <String, String>{'id': id, 'text': text};
  }

  Future<void> _ackSharedLocation(String id) async {
    if (id.trim().isEmpty ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _sharedLocationChannel.invokeMethod<bool>('ackPending', {'id': id});
    } catch (_) {
      // يبقى الإدخال محفوظاً في Android ليعاد حسمه، ولا ينشأ طلب تلقائياً.
    }
  }

  Future<void> _inspectPendingSharedLocation() async {
    if (!mounted ||
        !_appIsResumed ||
        _busy ||
        _sharedLocationInspectionInProgress ||
        _storeExternalComposerOpen ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _sharedLocationInspectionInProgress = true;
    try {
      final pending = await _pendingSharedLocation();
      if (!mounted || pending == null) return;
      final id = pending['id']!;
      if (_lastSharedLocationFailureId == id) return;
      final source = pending['text']!;
      final point =
          sallaParseSharedLocationText(source) ??
          await sallaResolveSharedLocationText(source);
      if (!mounted) return;
      if (point == null) {
        _lastSharedLocationFailureId = id;
        _message(
          'تعذر قراءة رابط الموقع. تحقق من الاتصال ثم افتح الرابط أو شاركه مرة أخرى.',
        );
        return;
      }
      await _openStoreExternalDelivery(
        initialDeliveryPoint: point,
        sharedLocationId: id,
      );
    } on MissingPluginException {
      // لا توجد قناة Android في اختبارات Flutter أو المنصات الأخرى.
    } on PlatformException {
      // يحتفظ Android بالإدخال نفسه لإعادة المحاولة عند استئناف التطبيق.
    } finally {
      _sharedLocationInspectionInProgress = false;
    }
  }

  Future<void> _openStoreExternalDelivery({
    SallaGeoPoint? initialDeliveryPoint,
    String sharedLocationId = '',
  }) async {
    if (widget.isGuest) {
      await _guestAccess();
      return;
    }
    if (_storeExternalComposerOpen) return;
    _storeExternalComposerOpen = true;
    StoreOrder? created;
    var importedLocationApplied = false;
    try {
      var reviewedDeliveryPoint = initialDeliveryPoint;
      if (reviewedDeliveryPoint != null && sharedLocationId.isNotEmpty) {
        reviewedDeliveryPoint = await Navigator.of(context).push<SallaGeoPoint>(
          MaterialPageRoute(
            builder: (_) => _StoreExternalDeliveryMapPickerPage(
              initialPoint: reviewedDeliveryPoint,
            ),
          ),
        );
        if (!mounted) return;
        if (reviewedDeliveryPoint == null) {
          _lastSharedLocationFailureId = sharedLocationId;
          await _ackSharedLocation(sharedLocationId);
          _message('لم يعتمد موقع المستلم، ولم يُنشأ أي طلب.');
          return;
        }
        _lastSharedLocationFailureId = '';
      }
      created = await showStoreExternalDeliveryComposer(
        context,
        initialDeliveryPoint: reviewedDeliveryPoint,
        onInitialDeliveryPointApplied: sharedLocationId.isEmpty
            ? null
            : () {
                importedLocationApplied = true;
                unawaited(_ackSharedLocation(sharedLocationId));
              },
      );
    } finally {
      _storeExternalComposerOpen = false;
    }
    if (importedLocationApplied) {
      await _ackSharedLocation(sharedLocationId);
    }
    if (!mounted) return;
    if (created != null) {
      setState(() => _pageIndex = 1);
      _message('تم إنشاء ${created.number} عبر الخادم بنجاح.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showOrderDetails(created!);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_inspectPendingSharedLocation());
    });
  }

  Widget _storeStatusPill() {
    final liveReady = _storeLiveStatus == _StoreLiveStatus.ready;
    final pendingAction = _pendingStoreOperationalRequestIds.isEmpty
        ? ''
        : _pendingStoreOperationalRequestIds.keys.first;
    final hasPendingStatusIntent = pendingAction.isNotEmpty;
    final pillColor = hasPendingStatusIntent
        ? Colors.orange
        : !liveReady
        ? (_storeLiveStatus == _StoreLiveStatus.error
              ? Colors.red
              : Colors.orange)
        : _courierOnlyChannelReady
        ? appColor
        : _courierOnlyAwaitingApproval
        ? Colors.orange
        : (_online ? appColor : Colors.red);
    final pillLabel = widget.isGuest
        ? 'معاينة'
        : hasPendingStatusIntent
        ? (pendingAction == 'open' ? 'استكمال الفتح' : 'استكمال الإيقاف')
        : !liveReady
        ? (_storeLiveStatus == _StoreLiveStatus.error ? 'غير متصل' : 'يتصل')
        : _courierOnlyChannelReady
        ? 'طلب مندوبك'
        : _courierOnlyAwaitingApproval
        ? 'بانتظار الإدارة'
        : (_storeStatus == 'banned'
              ? 'محظور'
              : _networkAssignmentPending
              ? 'بانتظار الإدارة'
              : _storeLockedByAdmin
              ? 'موقوف'
              : _online
              ? 'مفتوح'
              : 'مغلق');
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.isGuest
            ? () => unawaited(_guestAccess())
            : _courierOnlyChannelReady ||
                  _courierOnlyAwaitingApproval ||
                  _storeLockedByAdmin ||
                  _storeStatusUpdating ||
                  (!liveReady && !hasPendingStatusIntent)
            ? null
            : () => _setOnline(
                hasPendingStatusIntent ? pendingAction == 'open' : !_online,
              ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: pillColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: pillColor.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 5, backgroundColor: pillColor),
              const SizedBox(width: 7),
              Text(
                pillLabel,
                style: TextStyle(
                  color: pillColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scheduleStoreSettlementPreview() {
    if (_liveDisposed || !mounted || !widget.enableRealtime) return;
    _settlementPreviewTimer?.cancel();
    _settlementPreviewTimer = Timer(const Duration(milliseconds: 450), () {
      _settlementPreviewTimer = null;
      unawaited(_loadStoreSettlementPreview());
    });
  }

  Future<void> _loadStoreSettlementPreview() async {
    if (_liveDisposed || !mounted || !widget.enableRealtime) return;
    if (_settlementPreviewLoading) {
      _settlementPreviewRefreshPending = true;
      return;
    }
    setState(() {
      _settlementPreviewLoading = true;
      _settlementPreviewError = '';
    });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
            'settleStoreDues',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          );
      final response = await waitForFirebaseResult(
        callable.call<dynamic>({'action': 'preview', 'storeId': storeId}),
        debugLabel: 'Store settlement preview',
        timeout: const Duration(seconds: 35),
      );
      if (response == null) {
        throw TimeoutException('Store settlement preview timed out.');
      }
      final data = response.data;
      if (data is! Map || data['stores'] is! Map) {
        throw StateError('Store settlement preview is incomplete.');
      }
      final stores = data['stores'] as Map;
      final rawPreview = stores[storeId];
      if (rawPreview is! Map) {
        throw StateError('Store settlement preview is missing.');
      }
      if (!mounted || _liveDisposed) return;
      setState(() {
        _trustedOpenSettlementAmount = firebaseIntValue(rawPreview['amount']);
        _trustedOpenSettlementOrderCount = firebaseIntValue(
          rawPreview['orderCount'],
        );
        _trustedSettledAmount = firebaseIntValue(rawPreview['settledAmount']);
        _trustedSettledOrderCount = firebaseIntValue(
          rawPreview['settledOrderCount'],
        );
        _settlementPreviewLoaded = true;
        _settlementPreviewError = '';
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted || _liveDisposed) return;
      setState(() {
        _settlementPreviewError = error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'تعذر تحميل الرصيد الكامل للمتجر.';
      });
    } catch (error) {
      debugPrint('Store settlement preview failed: $error');
      if (!mounted || _liveDisposed) return;
      setState(() {
        _settlementPreviewError =
            'تعذر تحميل الرصيد الكامل. تحقق من الاتصال ثم أعد المحاولة.';
      });
    } finally {
      if (mounted && !_liveDisposed) {
        final refreshAgain = _settlementPreviewRefreshPending;
        setState(() {
          _settlementPreviewLoading = false;
          _settlementPreviewRefreshPending = false;
        });
        if (refreshAgain) _scheduleStoreSettlementPreview();
      }
    }
  }

  List<StoreOrder> get _deliveredSettlementOrders =>
      _orders.where((order) => order.isStoreSettlementRecord).toList();

  int get _openStoreSettlementTotal {
    if (_settlementPreviewLoaded) return _trustedOpenSettlementAmount;
    return _deliveredSettlementOrders.fold<int>(
      0,
      (sum, order) =>
          sum +
          (order.storeSettlementPaid ? 0 : order.storeSettlementDisplayAmount),
    );
  }

  int get _settledStoreSettlementTotal {
    if (_settlementPreviewLoaded) return _trustedSettledAmount;
    return _deliveredSettlementOrders.fold<int>(
      0,
      (sum, order) =>
          sum +
          (order.storeSettlementPaid ? order.storeSettlementDisplayAmount : 0),
    );
  }

  int get _openStoreSettlementOrders => _settlementPreviewLoaded
      ? _trustedOpenSettlementOrderCount
      : _deliveredSettlementOrders
            .where((order) => !order.storeSettlementPaid)
            .length;

  Widget _storeFinanceSummary() {
    final openOrders =
        _deliveredSettlementOrders
            .where((order) => !order.storeSettlementPaid)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final settledOrders =
        _deliveredSettlementOrders
            .where((order) => order.storeSettlementPaid)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: orangeColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: orangeColor,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مستحقات المتجر',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: darkText,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'الرصيد من السجل الكامل، ويعتمد الدفع بعد التحويل فعلياً.',
                        style: TextStyle(
                          color: mutedText,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_settlementPreviewLoading) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(minHeight: 3),
              ),
            ],
            if (_settlementPreviewError.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.10)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      color: Colors.red,
                      size: 19,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _settlementPreviewLoaded
                            ? 'تعذر تحديث الرصيد الكامل؛ بقي آخر رصيد موثوق معروضاً.'
                            : 'تعذر تحميل الرصيد الكامل؛ المعروض مؤقتاً من أحدث الطلبات.',
                        style: const TextStyle(
                          color: mutedText,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إعادة المحاولة',
                      onPressed: _settlementPreviewLoading
                          ? null
                          : _loadStoreSettlementPreview,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      color: appColor,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _financeMetric(
                    'بانتظار الدفع',
                    formatIqd(_openStoreSettlementTotal),
                    orangeColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _financeMetric(
                    _settlementPreviewLoaded
                        ? 'مدفوع • $_trustedSettledOrderCount طلب'
                        : 'مدفوع',
                    formatIqd(_settledStoreSettlementTotal),
                    appColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _openStoreSettlementOrders == 0
                    ? 'لا توجد طلبات مكتملة بانتظار تسوية حالياً.'
                    : '$_openStoreSettlementOrders طلب مكتمل بانتظار اعتماد الدفع من الإدارة.',
                style: const TextStyle(
                  color: mutedText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: appColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: appColor.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.price_check_rounded,
                      color: appColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'آخر دفعة من الإدارة',
                          style: TextStyle(
                            color: darkText,
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _lastSettlementAmount <= 0
                              ? 'لم تُسجل دفعة مستحقات بعد.'
                              : '${formatIqd(_lastSettlementAmount)} • $_lastSettlementOrderCount طلب • ${_lastSettlementMethod.isEmpty ? 'طريقة غير محددة' : _lastSettlementMethod} • ${_lastSettlementAt.isEmpty ? 'بدون وقت' : _lastSettlementAt}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: mutedText,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                        ),
                        if (_lastSettlementPaymentReference
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'مرجع الدفع: $_lastSettlementPaymentReference',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: appColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (openOrders.isNotEmpty || settledOrders.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _settlementOrderHint(
                      title: 'آخر طلب مفتوح',
                      order: openOrders.isEmpty ? null : openOrders.first,
                      color: orangeColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _settlementOrderHint(
                      title: 'آخر طلب مدفوع',
                      order: settledOrders.isEmpty ? null : settledOrders.first,
                      color: appColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _settlementOrderHint({
    required String title,
    required StoreOrder? order,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: mutedText,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            order == null ? '-' : order.number,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            order == null
                ? 'لا يوجد'
                : formatIqd(order.storeSettlementDisplayAmount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: darkText,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          if (order != null &&
              order.storeSettlementPaymentReference.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'مرجع: ${order.storeSettlementPaymentReference}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _financeMetric(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: mutedText,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboard() {
    final newOrders = _orders.where(_isNewStoreOrder).length;
    final preparing = _orders
        .where(
          (order) =>
              !_isTerminalStoreOrder(order) &&
              (order.storeStage == 'accepted' ||
                  order.storeStage == 'preparing'),
        )
        .length;
    final ready = _orders.where(_isReadyStoreOrder).length;
    final returning = _orders.where(_isReturningStoreOrder).length;
    final todayTotal = _orders
        .where(
          (order) =>
              order.createdAt.day == DateTime.now().day && !order.isCancelled,
        )
        .fold<int>(0, (sum, order) => sum + order.storeNetAmount);
    return RefreshIndicator(
      onRefresh: () async => _ensureStoreProfile(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [appColor, Color(0xFF075E54)],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: appColor.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مركز تشغيل المتجر',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 23,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'اقبل الطلبات، جهّزها، وتابع السائق من شاشة واحدة.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _heroMiniMetric(
                        'جديد',
                        '$newOrders',
                        Icons.notifications_active_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _heroMiniMetric(
                        'جاهز',
                        '$ready',
                        Icons.inventory_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _heroMiniMetric(
                        'إرجاع',
                        '$returning',
                        Icons.keyboard_return_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_storeLiveStatus != _StoreLiveStatus.ready) ...[
            _liveStatusCard(
              status: _storeLiveStatus,
              loadingText: 'جاري تحميل حالة المتجر وإعداداته...',
              errorText: _storeLiveError.isEmpty
                  ? 'تعذر تحديث حالة المتجر. سنعيد المحاولة تلقائياً.'
                  : _storeLiveError,
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 650 ? 4 : 2;
              const gap = 10.0;
              final cardWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              final metrics = [
                _metric(
                  'طلبات جديدة',
                  '$newOrders',
                  Icons.notifications_active,
                  orangeColor,
                ),
                _metric(
                  'قيد التحضير',
                  '$preparing',
                  Icons.soup_kitchen,
                  appColor,
                ),
                _metric(
                  'جاهزة',
                  '$ready',
                  Icons.inventory_rounded,
                  Colors.blue,
                ),
                _metric(
                  'مستحقات اليوم',
                  formatIqd(todayTotal),
                  Icons.payments,
                  Colors.purple,
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: metrics
                    .map((metric) => SizedBox(width: cardWidth, child: metric))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          _storeFinanceSummary(),
          const SizedBox(height: 18),
          _sectionTitle('تحتاج إجراء الآن'),
          const SizedBox(height: 8),
          if (_ordersLiveStatus != _StoreLiveStatus.ready)
            _liveStatusCard(
              status: _ordersLiveStatus,
              loadingText: _orders.isEmpty
                  ? 'جاري تحميل الطلبات العاجلة...'
                  : 'جاري تحديث الطلبات مع الاحتفاظ بآخر بيانات ظاهرة.',
              errorText: _ordersLiveError.isEmpty
                  ? 'تعذر تحديث الطلبات العاجلة. سنعيد المحاولة تلقائياً.'
                  : _ordersLiveError,
            ),
          ..._orders.where(_needsStoreAction).take(5).map(_orderCard),
          if (_ordersLiveStatus == _StoreLiveStatus.ready &&
              !_orders.any(_needsStoreAction))
            _empty('لا توجد طلبات عاجلة حالياً'),
        ],
      ),
    );
  }

  Widget _heroMiniMetric(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ordersPage() {
    final newCount = _orders.where(_isNewStoreOrder).length;
    final readyCount = _orders.where(_isReadyStoreOrder).length;
    final returningCount = _orders.where(_isReturningStoreOrder).length;
    return Column(
      children: [
        Container(
          key: const ValueKey<String>('store_orders_compact_summary'),
          margin: const EdgeInsets.fromLTRB(16, 7, 16, 2),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x090F172A),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: appColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: appColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'طلبات المتجر',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: darkText,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              _compactCounter('جديد', newCount, orangeColor),
              const SizedBox(width: 4),
              _compactCounter('جاهز', readyCount, Colors.blue),
              const SizedBox(width: 4),
              _compactCounter('إرجاع', returningCount, Colors.red),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _filterChip('active', 'النشطة'),
              _filterChip('courier_report', 'سجل طلب مندوبك'),
              _filterChip('new', 'الجديدة'),
              _filterChip('ready', 'الجاهزة'),
              _filterChip('returning', 'الإرجاع'),
              _filterChip('completed', 'المكتملة'),
              _filterChip('cancelled', 'الملغاة'),
            ],
          ),
        ),
        if (!widget.isGuest &&
            const {'completed', 'cancelled'}.contains(_filter))
          _storeHistorySummaryCard(),
        Expanded(child: _ordersListBody()),
      ],
    );
  }

  Widget _ordersListBody() {
    if (widget.isGuest) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        children: [
          _empty('لا توجد طلبات في هذا القسم'),
          const Text(
            'استكشف التبويبات؛ تظهر طلبات متجرك بعد تسجيل الدخول.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, height: 1.5),
          ),
        ],
      );
    }
    if (_filter == 'courier_report') {
      return StoreCourierReport(
        key: ValueKey('courier_report_${sallaIdentity.uid}_$storeId'),
        expectedStoreId: storeId,
        loadPage: loadStoreCourierReportPage,
        onOpenOrder: _showOrderDetails,
      );
    }
    final visibleOrders = _visibleOrders;
    final showStatus = _ordersLiveStatus != _StoreLiveStatus.ready;
    final showEmpty =
        _ordersLiveStatus == _StoreLiveStatus.ready && visibleOrders.isEmpty;
    final showHistoryControl = const {
      'completed',
      'cancelled',
    }.contains(_filter);
    final leadingItems = (showStatus ? 1 : 0) + (showEmpty ? 1 : 0);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      itemCount:
          visibleOrders.length + leadingItems + (showHistoryControl ? 1 : 0),
      itemBuilder: (context, index) {
        if (showStatus && index == 0) {
          return _liveStatusCard(
            status: _ordersLiveStatus,
            loadingText: _orders.isEmpty
                ? 'جاري تحميل طلبات المتجر...'
                : 'جاري تحديث الطلبات مع الاحتفاظ بآخر بيانات ظاهرة.',
            errorText: _ordersLiveError.isEmpty
                ? 'تعذر تحديث طلبات المتجر. سنعيد المحاولة تلقائياً.'
                : _ordersLiveError,
          );
        }
        if (showEmpty && index == (showStatus ? 1 : 0)) {
          return _empty('لا توجد طلبات في هذا القسم');
        }
        final orderIndex = index - leadingItems;
        if (orderIndex >= visibleOrders.length) {
          return _storeHistoryPaginationControl();
        }
        return _orderCard(visibleOrders[orderIndex]);
      },
    );
  }

  Widget _storeHistoryPaginationControl() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      child: Column(
        children: [
          if (_storeHistoryError.isNotEmpty) ...[
            Text(
              _storeHistoryError,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_storeHistoryHasMore || _storeHistoryLoading)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _storeHistoryLoading
                    ? null
                    : () => unawaited(loadOlderStoreOrders()),
                icon: _storeHistoryLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  _storeHistoryLoading
                      ? 'جارٍ تحميل طلبات أقدم...'
                      : 'تحميل طلبات أقدم',
                ),
              ),
            )
          else if (_storeHistoryInitialized)
            const Text(
              'تم عرض جميع طلبات المتجر السابقة',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }

  Widget _storeProductThumbnail(StoreProduct product) {
    final imagePath = product.preferredThumbnailPath;
    final fallback = Container(
      color: (product.available ? appColor : Colors.grey).withValues(
        alpha: 0.10,
      ),
      alignment: Alignment.center,
      child: Icon(
        product.archived
            ? Icons.archive_outlined
            : product.available
            ? Icons.check_circle_rounded
            : Icons.remove_circle_outline,
        color: product.available ? appColor : Colors.grey,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: imagePath.startsWith('http://') || imagePath.startsWith('https://')
          ? Image.network(
              imagePath,
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallback,
            )
          : fallback,
    );
  }

  Widget _productsPage() {
    final leading = <Widget>[
      _sectionTitle('توفر المنتجات'),
      const SizedBox(height: 5),
      const Text(
        'يمكنك إدارة التوفر والمخزون والعروض هنا. إنشاء الصنف وصوره وترتيبه يبقى من لوحة الإدارة.',
        style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      if (_productsLiveStatus != _StoreLiveStatus.ready) ...[
        _liveStatusCard(
          status: _productsLiveStatus,
          loadingText: _products.isEmpty
              ? 'جاري تحميل منتجات المتجر...'
              : 'جاري تحديث المنتجات مع الاحتفاظ بآخر بيانات ظاهرة.',
          errorText: _productsLiveError.isEmpty
              ? 'تعذر تحديث منتجات المتجر. سنعيد المحاولة تلقائياً.'
              : _productsLiveError,
        ),
        const SizedBox(height: 10),
      ],
      if (_productsLiveStatus == _StoreLiveStatus.ready && _products.isEmpty)
        _empty('لا توجد منتجات مسجلة لهذا المتجر حالياً'),
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: leading.length + _products.length,
      itemBuilder: (context, index) {
        if (index < leading.length) return leading[index];
        final product = _products[index - leading.length];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: _storeProductThumbnail(product),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: darkText,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.offerIsActiveNow
                                ? '${product.category} • ${product.unit} • عرض ${formatIqd(product.offerPrice)} بدلاً من ${formatIqd(product.price)} • ${product.stockText}'
                                : '${product.category} • ${product.unit} • ${formatIqd(product.price)} • ${product.stockText}',
                            style: const TextStyle(
                              color: mutedText,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          if (product.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              product.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'ترتيب القسم ${product.categoryDisplayOrder} • ترتيب الصنف ${product.displayOrder} • مراجعة ${product.revision}',
                            style: const TextStyle(
                              color: Colors.black45,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                            ),
                          ),
                          if (product.archived ||
                              !product.categoryActive ||
                              !product.hasCompleteMenuMedia)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                product.archived
                                    ? 'صنف مؤرشف — للقراءة فقط'
                                    : !product.categoryActive
                                    ? 'القسم متوقف — لا يمكن تفعيل الصنف حتى يُفعّل القسم'
                                    : 'صور الصنف غير مكتملة — أكمل الصورة والمصغرة من لوحة الإدارة قبل التفعيل',
                                style: TextStyle(
                                  color: product.archived
                                      ? Colors.red.shade700
                                      : Colors.orange.shade800,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          _busyProductIds.contains(product.id) ||
                              !product.canManageAvailability
                          ? null
                          : () => _showProductOfferSheet(product),
                      icon: Icon(
                        product.offer
                            ? Icons.local_offer_rounded
                            : Icons.local_offer_outlined,
                      ),
                      label: Text(
                        product.offerIsActiveNow
                            ? 'عرض نشط'
                            : product.offer
                            ? 'عرض مجدول'
                            : 'إضافة عرض',
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'نقص المخزون',
                      onPressed:
                          !product.archived &&
                              product.stockQuantity > 0 &&
                              !_busyProductIds.contains(product.id)
                          ? () => _setProductStockQuantity(
                              product,
                              product.stockQuantity - 1,
                            )
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        product.stockQuantity < 0
                            ? 'غير محدد'
                            : '${product.stockQuantity}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'زيادة المخزون',
                      onPressed:
                          _busyProductIds.contains(product.id) ||
                              product.archived
                          ? null
                          : () => _setProductStockQuantity(
                              product,
                              product.stockQuantity < 0
                                  ? 1
                                  : product.stockQuantity + 1,
                            ),
                      icon: const Icon(Icons.add_rounded),
                    ),
                    TextButton.icon(
                      onPressed:
                          _busyProductIds.contains(product.id) ||
                              product.archived
                          ? null
                          : () => _setProductStockQuantity(product, 0),
                      icon: const Icon(Icons.block_rounded),
                      label: const Text('نفد'),
                    ),
                    Container(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      decoration: BoxDecoration(
                        color: product.available
                            ? appColor.withValues(alpha: 0.08)
                            : Colors.grey.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.available ? 'متوفر' : 'متوقف',
                            style: TextStyle(
                              color: product.available ? appColor : mutedText,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Switch(
                            value: product.available,
                            activeThumbColor: appColor,
                            onChanged:
                                _busyProductIds.contains(product.id) ||
                                    !product.canManageAvailability
                                ? null
                                : (value) {
                                    if (value && product.stockQuantity == 0) {
                                      _message(
                                        'زد المخزون أولاً، ثم فعّل توفر المنتج بخطوة مستقلة.',
                                        error: true,
                                      );
                                      return;
                                    }
                                    if (value &&
                                        !product.hasCompleteMenuMedia) {
                                      _message(
                                        'أكمل صورة الصنف والمصغرة من لوحة الإدارة أولاً.',
                                        error: true,
                                      );
                                      return;
                                    }
                                    _setProductAvailability(product, value);
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_busyProductIds.contains(product.id)) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 3),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _settingsPage() {
    final dispatchLeadOptions = <int>{
      0,
      3,
      5,
      10,
      15,
      20,
      30,
      45,
      60,
      _dispatchLeadMinutes,
    }.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: appColor,
                  child: Icon(Icons.storefront, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 10),
                Text(
                  storeName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                Text(
                  'رمز المتجر: $storeId',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_requestSignOut()),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('تسجيل الخروج'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_storeLiveStatus != _StoreLiveStatus.ready) ...[
          _liveStatusCard(
            status: _storeLiveStatus,
            loadingText: 'جاري تحميل إعدادات المتجر...',
            errorText: _storeLiveError.isEmpty
                ? 'تعذر تحديث إعدادات المتجر. سنعيد المحاولة تلقائياً.'
                : _storeLiveError,
          ),
          const SizedBox(height: 10),
        ],
        if (_busyStoreSettingKeys.isNotEmpty) ...[
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 10),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: StorePublicLinks(
              onRequestDeletion: () {
                final expectedStore = storeId;
                final expectedUid = sallaIdentity.uid;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StorePrivacyRequestPage(
                      storeId: expectedStore,
                      call: (payload) async {
                        if (storeId != expectedStore ||
                            sallaIdentity.uid != expectedUid)
                          throw StateError('تغير حساب المتجر.');
                        final response =
                            await FirebaseFunctions.instanceFor(
                                  region: 'europe-west1',
                                )
                                .httpsCallable(
                                  'manageStoreRecord',
                                  options: HttpsCallableOptions(
                                    timeout: const Duration(seconds: 35),
                                  ),
                                )
                                .call<dynamic>(payload);
                        if (storeId != expectedStore ||
                            sallaIdentity.uid != expectedUid)
                          throw StateError('تغير حساب المتجر.');
                        if (response.data is! Map)
                          throw const FormatException(
                            'استجابة الخصوصية غير صالحة.',
                          );
                        return Map<String, dynamic>.from(response.data as Map);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: _online,
                activeThumbColor: appColor,
                title: const Text(
                  'استقبال الطلبات',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  _storeStatus == 'banned'
                      ? 'المتجر محظور من الإدارة ولا يمكن فتحه من التطبيق'
                      : _networkAssignmentPending
                      ? 'بانتظار أن تعيّن الإدارة الفرع والزون وتعتمد التشغيل'
                      : _storeLockedByAdmin
                      ? 'المتجر موقوف من الإدارة ولا يمكن فتحه من التطبيق'
                      : _online && _hasActiveStoreOrders
                      ? 'لديك طلبات نشطة، لا يمكن الإغلاق قبل إنهائها'
                      : _online
                      ? 'المتجر مفتوح'
                      : 'المتجر مغلق',
                ),
                onChanged:
                    _storeLiveStatus != _StoreLiveStatus.ready ||
                        _storeLockedByAdmin ||
                        _storeStatusUpdating
                    ? null
                    : _setOnline,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: appColor),
                title: const Text(
                  'وقت التحضير الافتراضي',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('$_prepMinutes دقيقة'),
                trailing: DropdownButton<int>(
                  value: _prepMinutes,
                  underline: const SizedBox.shrink(),
                  items: const [5, 10, 15, 20, 25, 30, 35, 40, 45]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value د'),
                        ),
                      )
                      .toList(),
                  onChanged:
                      _storeLiveStatus != _StoreLiveStatus.ready ||
                          _busyStoreSettingKeys.contains('prep_minutes')
                      ? null
                      : (value) {
                          if (value != null) _setPrepMinutes(value);
                        },
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _autoDispatchEnabled,
                activeThumbColor: appColor,
                secondary: const Icon(
                  Icons.delivery_dining_rounded,
                  color: appColor,
                ),
                title: const Text(
                  'التوزيع التلقائي للسائقين',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  _autoDispatchEnabled
                      ? 'يبدأ البحث عن سائق قبل جاهزية الطلب حسب الوقت المحدد'
                      : 'لن يتم إرسال الطلب تلقائياً للسائقين حتى يتم تشغيله',
                ),
                onChanged:
                    _storeLiveStatus == _StoreLiveStatus.ready &&
                        !_busyStoreSettingKeys.contains('auto_dispatch')
                    ? _setAutoDispatchEnabled
                    : null,
              ),
              const Divider(height: 1),
              ListTile(
                enabled:
                    _storeLiveStatus == _StoreLiveStatus.ready &&
                    _autoDispatchEnabled,
                leading: Icon(
                  Icons.alarm_on_rounded,
                  color: _autoDispatchEnabled ? appColor : mutedText,
                ),
                title: const Text(
                  'إرسال للسائق قبل الجاهزية',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  _dispatchLeadMinutes == 0
                      ? 'يرسل عند جاهزية الطلب'
                      : 'يرسل قبل وقت الجاهزية بـ $_dispatchLeadMinutes دقيقة',
                ),
                trailing: DropdownButton<int>(
                  value: _dispatchLeadMinutes,
                  underline: const SizedBox.shrink(),
                  items: dispatchLeadOptions
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value == 0 ? 'عند الجاهزية' : '$value د'),
                        ),
                      )
                      .toList(),
                  onChanged:
                      _storeLiveStatus == _StoreLiveStatus.ready &&
                          _autoDispatchEnabled &&
                          !_busyStoreSettingKeys.contains(
                            'dispatch_lead_minutes',
                          )
                      ? (value) {
                          if (value != null) _setDispatchLeadMinutes(value);
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _storeFinanceSummary(),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: Icon(
              _storeLiveStatus == _StoreLiveStatus.ready
                  ? Icons.cloud_done_rounded
                  : _storeLiveStatus == _StoreLiveStatus.error
                  ? Icons.cloud_off_rounded
                  : Icons.cloud_sync_rounded,
              color: _storeHeaderStatusColor,
            ),
            title: Text(
              _storeLiveStatus == _StoreLiveStatus.ready
                  ? 'متصل بنظام Salla'
                  : _storeLiveStatus == _StoreLiveStatus.error
                  ? 'تعذر تحديث الاتصال'
                  : 'جاري الاتصال بنظام Salla',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'الطلبات والمخزون والمراحل متزامنة عبر Firebase Realtime Database.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        selectedColor: appColor.withValues(alpha: 0.14),
        labelStyle: TextStyle(
          color: selected ? appColor : Colors.black87,
          fontWeight: FontWeight.w900,
        ),
        onSelected: (_) {
          setState(() => _filter = value);
          if (!widget.isGuest &&
              const {'completed', 'cancelled'}.contains(value)) {
            _ensureStoreHistoryLoaded();
          }
        },
      ),
    );
  }

  Widget _metric(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: darkText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: mutedText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactCounter(String label, int value, Color color) {
    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _storeHistorySummaryCard() {
    final total = _orders.length;
    final platformOrders = _orders
        .where((order) => !order.isStoreExternal)
        .length;
    final externalOrders = _orders
        .where((order) => order.isStoreExternal)
        .length;
    final deliveredOrders = _orders.where((order) => order.isDelivered).length;
    final cancelledOrders = _orders.where((order) => order.isCancelled).length;
    final complete =
        _storeHistoryInitialized &&
        !_storeHistoryHasMore &&
        !_storeHistoryLoading;

    return Container(
      key: const ValueKey<String>('store_order_history_summary'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: appColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  color: appColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complete ? 'ملخص كامل سجل المتجر' : 'ملخص السجل المحمّل',
                      style: const TextStyle(
                        color: darkText,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      complete
                          ? 'يشمل جميع الطلبات السابقة والحالية.'
                          : 'تزداد الأعداد عند تحميل طلبات أقدم.',
                      style: const TextStyle(
                        color: mutedText,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_storeHistoryLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _orderMetaChip(
                Icons.receipt_long_rounded,
                'الكل $total',
                darkText,
              ),
              _orderMetaChip(
                Icons.shopping_bag_outlined,
                'من منصة سلة $platformOrders',
                Colors.blue,
              ),
              _orderMetaChip(
                Icons.local_shipping_outlined,
                'طلب مندوبك $externalOrders',
                orangeColor,
              ),
              _orderMetaChip(
                Icons.task_alt_rounded,
                'مكتملة $deliveredOrders',
                Colors.green,
              ),
              _orderMetaChip(
                Icons.cancel_outlined,
                'ملغاة $cancelledOrders',
                Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderMetaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyOrderNumber(StoreOrder order) async {
    await Clipboard.setData(ClipboardData(text: order.number));
    if (!mounted) return;
    _message('تم نسخ رقم الطلب ${order.number}');
  }

  Widget _orderCard(StoreOrder order) {
    final color = storeStageColor(order.storeStage);
    final isExternal = order.isStoreExternal;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      color: isExternal ? const Color(0xFFFFFBEB) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isExternal
              ? orangeColor.withValues(alpha: 0.24)
              : Colors.transparent,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showOrderDetails(order),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      order.storeStage == 'returningToStore'
                          ? Icons.keyboard_return_rounded
                          : isExternal
                          ? Icons.local_shipping_rounded
                          : Icons.receipt_long_rounded,
                      color: isExternal ? orangeColor : color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StoreOrderNumberLabel(
                          key: ValueKey(
                            'copy_order_number_${order.databaseKey}',
                          ),
                          number: order.number,
                          onCopy: () => unawaited(_copyOrderNumber(order)),
                        ),
                        if (order.customerName.trim().isNotEmpty)
                          Text(
                            order.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: darkText,
                            ),
                          ),
                        const SizedBox(height: 3),
                        Text(
                          order.isStoreExternal
                              ? '${order.sourceLabel} • ${timeAgo(order.createdAt)} • إلى ${order.deliveryAreaName}'
                              : '${order.sourceLabel} • ${timeAgo(order.createdAt)} • ${order.items.length} أصناف',
                          style: const TextStyle(
                            color: mutedText,
                            fontWeight: FontWeight.w800,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      storeStageLabel(order.storeStage),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Tooltip(
                    message: 'طباعة الطلب',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _printOrderReceipt(order),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: darkText.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.print_rounded,
                          color: darkText,
                          size: 17,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (isExternal) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: orangeColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.pin_drop_rounded,
                        color: orangeColor,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${order.deliveryAreaName} • ${storeExternalServiceTypeLabel(order.storeExternalServiceType)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: darkText,
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'كروة ${formatIqd(order.deliveryFee)}',
                        style: const TextStyle(
                          color: orangeColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  _orderMetaChip(
                    Icons.storefront_rounded,
                    order.usesDeferredSettlement
                        ? 'تسوية آجلة مع الشركة'
                        : 'من السائق ${formatIqd(order.driverPaysStoreAmount)}',
                    appColor,
                  ),
                  _orderMetaChip(
                    Icons.payments_outlined,
                    'الإجمالي ${formatIqd(order.customerTotalToCollect)}',
                    isExternal ? orangeColor : Colors.purple,
                  ),
                  _orderMetaChip(
                    Icons.payment_rounded,
                    order.paymentMethod,
                    Colors.blueGrey,
                  ),
                  if (order.storePaymentConfirmedAt.trim().isNotEmpty)
                    _orderMetaChip(
                      Icons.verified_rounded,
                      'دفع السائق مؤكد',
                      Colors.green,
                    )
                  else if (order.driverName.trim().isNotEmpty &&
                      order.requiresDriverCashPayment)
                    _orderMetaChip(
                      Icons.lock_clock_rounded,
                      'ينتظر تأكيد الدفع',
                      orangeColor,
                    ),
                ],
              ),
              if (order.responsibleDriverName.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  '${order.responsibleDriverLabel}: ${order.responsibleDriverName}'
                  '${order.isCancelled || order.isDelivered ? '' : ' • ${driverStageLabel(order.driverStage)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.8,
                  ),
                ),
              ] else if (order.isCancelled) ...[
                const SizedBox(height: 5),
                const Text(
                  'أُلغي الطلب قبل تعيين سائق',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.8,
                  ),
                ),
              ] else if (const {
                'accepted',
                'preparing',
                'readyForPickup',
              }.contains(order.storeStage)) ...[
                const SizedBox(height: 5),
                Text(
                  storeDriverPlanningText(order),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: orangeColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.8,
                  ),
                ),
              ],
              if (order.items.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  order.items
                      .take(2)
                      .map((item) => '${item.quantity}× ${item.name}')
                      .join('، '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: mutedText,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.8,
                  ),
                ),
              ],
              if (order.customerRating > 0) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: orangeColor,
                      size: 19,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${order.customerRating}/5 من الزبون',
                      style: const TextStyle(
                        color: orangeColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (order.ratingComment.trim().isNotEmpty) ...[
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          order.ratingComment,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 6),
              _orderActions(order),
            ],
          ),
        ),
      ),
    );
  }

  void _showAcceptOrderSheet(StoreOrder order) {
    var selectedMinutes = 15.clamp(minPrepMinutes, maxPrepMinutes).toInt();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void setMinutes(int value) {
              setSheetState(() {
                selectedMinutes = value
                    .clamp(minPrepMinutes, maxPrepMinutes)
                    .toInt();
              });
            }

            final readyAt = DateTime.now().add(
              Duration(minutes: selectedMinutes),
            );
            final readyTime =
                '${readyAt.hour.toString().padLeft(2, '0')}:${readyAt.minute.toString().padLeft(2, '0')}';
            final driverRequestText = _driverRequestTextForPrep(
              selectedMinutes,
            );

            Widget stepButton({
              required IconData icon,
              required VoidCallback? onPressed,
              bool filled = false,
            }) {
              final button = Icon(
                icon,
                color: onPressed == null
                    ? mutedText.withValues(alpha: 0.45)
                    : (filled ? Colors.white : appColor),
              );
              return SizedBox(
                width: 44,
                height: 44,
                child: filled
                    ? IconButton.filled(onPressed: onPressed, icon: button)
                    : IconButton.filledTonal(
                        onPressed: onPressed,
                        icon: button,
                      ),
              );
            }

            Widget minutePill(int minutes) {
              final selected = selectedMinutes == minutes;
              return ChoiceChip(
                selected: selected,
                label: Text(
                  '$minutes د',
                  style: TextStyle(
                    color: selected ? Colors.white : darkText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                selectedColor: appColor,
                backgroundColor: bgColor,
                checkmarkColor: Colors.white,
                side: BorderSide(
                  color: selected
                      ? appColor
                      : Colors.black.withValues(alpha: 0.06),
                ),
                onSelected: (_) => setMinutes(minutes),
              );
            }

            Widget itemTile(StoreOrderItem item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.04),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: appColor.withValues(alpha: 0.10),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          color: appColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          if (item.unit.trim().isNotEmpty)
                            Text(
                              item.unit,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: mutedText,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget prepDurationCard() {
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: appColor.withValues(alpha: 0.10)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: appColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.timer_rounded,
                            color: appColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مدة تحضير الطلب',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'حدد وقت التجهيز قبل قبول الطلب.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: mutedText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        stepButton(
                          icon: Icons.remove_rounded,
                          onPressed: selectedMinutes <= minPrepMinutes
                              ? null
                              : () => setMinutes(selectedMinutes - 1),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              const Text(
                                'جاهز خلال',
                                style: TextStyle(
                                  color: mutedText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 160),
                                child: Text(
                                  '$selectedMinutes دقيقة',
                                  key: ValueKey(selectedMinutes),
                                  style: const TextStyle(
                                    color: appColor,
                                    fontSize: 31,
                                    height: 1.1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                'وقت الجاهزية: $readyTime',
                                style: const TextStyle(
                                  color: darkText,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        stepButton(
                          icon: Icons.add_rounded,
                          filled: true,
                          onPressed: selectedMinutes >= maxPrepMinutes
                              ? null
                              : () => setMinutes(selectedMinutes + 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [5, 10, 15, 20, 25, 30, 35, 40, 45]
                            .map(
                              (minutes) => Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 7,
                                ),
                                child: minutePill(minutes),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: orangeColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delivery_dining_rounded,
                            color: orangeColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              driverRequestText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: darkText,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.92,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: appColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                color: appColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'قبول ${order.number}',
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    order.usesDeferredSettlement
                                        ? 'تسوية آجلة مع الشركة'
                                        : 'من السائق ${formatIqd(order.driverPaysStoreAmount)}',
                                    style: const TextStyle(
                                      color: mutedText,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        prepDurationCard(),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.04),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'أصناف الطلب',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${order.items.length} صنف',
                                      style: const TextStyle(
                                        color: appColor,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (order.items.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: Text(
                                      'لا توجد أصناف مسجلة لهذا الطلب.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: mutedText,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: order.items.length,
                                  itemBuilder: (context, index) =>
                                      itemTile(order.items[index]),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('رجوع'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () {
                                        Navigator.pop(sheetContext);
                                        unawaited(
                                          _updateOrder(
                                            order,
                                            'accept',
                                            prepMinutes: selectedMinutes,
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('قبول وبدء التجهيز'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: appColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _orderActions(StoreOrder order) {
    final primary = _primaryOrderActions(order);
    if (!order.canCancelStoreExternalDelivery) return primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        primary,
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final cancelled =
                        await cancelStoreExternalDeliveryFromStore(
                          context,
                          order,
                        );
                    if (cancelled && mounted) {
                      _message('تم إلغاء ${order.number} عبر الخادم.');
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('إلغاء طلب التوصيل الخارجي'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }

  Widget _primaryOrderActions(StoreOrder order) {
    switch (order.storeStage) {
      case 'awaitingAcceptance':
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _showAcceptOrderSheet(order),
                icon: const Icon(Icons.check_rounded),
                label: const Text('قبول الطلب'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _message('اضغط مطولاً لاختيار سبب الرفض'),
              onLongPress: _busy ? null : () => _showRejectReasons(order),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('رفض'),
            ),
          ],
        );
      case 'accepted':
      case 'preparing':
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _updateOrder(order, 'ready'),
            icon: const Icon(Icons.inventory_rounded),
            label: const Text('جاهز للاستلام'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        );
      case 'readyForPickup':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.delivery_dining_rounded, color: Colors.blue, size: 17),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'بانتظار وصول السائق واستلام الطلب',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        );
      case 'returningToStore':
        if (!order.usesDeferredSettlement) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'هذا طلب دفع مباشر، وتتم معالجة رفض الزبون مالياً من الإدارة من دون إرجاع للمتجر.',
              style: TextStyle(
                color: Colors.deepOrange,
                fontWeight: FontWeight.w900,
                height: 1.4,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.keyboard_return_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'طلب الدفع الآجل راجع للمتجر. أكد النتيجة بعد وصول السائق والمواد.',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'اضغط مطولاً إذا وصلت المواد كاملة. إذا وُجد نقص، سجله ليبقى الطلب معلقاً لمراجعة الإدارة من دون تنفيذ مالي.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _confirmDeferredReturn(
                            order,
                            goodsComplete: false,
                          ),
                    icon: const Icon(Icons.report_problem_outlined),
                    label: const Text('يوجد نقص'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () =>
                              _message('اضغط مطولاً لتأكيد وصول المواد كاملة'),
                    onLongPress: _busy
                        ? null
                        : () => _confirmDeferredReturn(
                            order,
                            goodsComplete: true,
                          ),
                    icon: const Icon(Icons.done_all_rounded),
                    label: const Text('وصلت كاملة'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        );
      default:
        return Text(
          driverStageLabel(order.driverStage),
          style: const TextStyle(color: Colors.black54),
        );
    }
  }

  void _showRejectReasons(StoreOrder order) {
    const reasons = [
      (
        Icons.store_mall_directory_outlined,
        'المتجر مغلق حالياً',
        'المتجر مغلق ولا يستطيع تنفيذ الطلب الآن.',
      ),
      (
        Icons.inventory_2_outlined,
        'الأصناف المطلوبة غير متوفرة',
        'بعض الأصناف المطلوبة غير متوفرة في المخزون.',
      ),
      (
        Icons.schedule_rounded,
        'وقت التجهيز غير مناسب',
        'وقت التجهيز الحالي أطول من الوقت المقبول للطلب.',
      ),
      (
        Icons.warning_amber_rounded,
        'تعذر تنفيذ الطلب',
        'تعذر على المتجر تنفيذ الطلب في الوقت الحالي.',
      ),
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سبب رفض ${order.number}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'سيظهر هذا السبب للزبون ولوحة الإدارة.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...reasons.map(
                    (reason) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        tileColor: bgColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.withValues(alpha: 0.09),
                          child: Icon(reason.$1, color: Colors.red),
                        ),
                        title: Text(
                          reason.$2,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(reason.$3),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _updateOrder(
                            order,
                            'reject',
                            rejectionReason: reason.$3,
                          );
                        },
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          color: Colors.red,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'اختر سبباً واضحاً حتى يعرف الزبون والإدارة سبب الرفض.',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printOrderReceipt(StoreOrder order) async {
    try {
      final bytes = await _buildOrderReceiptPdf(order);
      await Printing.layoutPdf(
        name: 'salla-order-${order.number}.pdf',
        format: PdfPageFormat.roll80,
        onLayout: (_) async => bytes,
      );
    } catch (error, stackTrace) {
      debugPrint('Store order print failed: $error\n$stackTrace');
      if (mounted) {
        _message('تعذرت طباعة الطلب. تحقق من خدمة الطباعة في الهاتف');
      }
    }
  }

  Future<Uint8List> _buildOrderReceiptPdf(StoreOrder order) async {
    final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
    final bold = await PdfGoogleFonts.notoNaskhArabicBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final createdAt = order.createdAt;
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  storeName,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'طلب مطبخ / تجهيز',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          _pdfDivider(),
          _pdfKeyValue('رقم الطلب', order.number, bold: true),
          _pdfKeyValue(
            'وقت الطلب',
            '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')} - ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
          ),
          _pdfKeyValue('الحالة', storeStageLabel(order.storeStage)),
          _pdfKeyValue('الدفع', order.paymentMethod),
          _pdfDivider(),
          _pdfKeyValue('الزبون', order.customerName),
          if (order.phone.trim().isNotEmpty)
            _pdfKeyValue('الهاتف', order.phone),
          if (order.address.trim().isNotEmpty)
            _pdfKeyValue('العنوان', order.address),
          if (order.note.trim().isNotEmpty) ...[
            _pdfDivider(),
            pw.Text(
              'ملاحظة الزبون',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(order.note, style: const pw.TextStyle(fontSize: 9)),
          ],
          _pdfDivider(),
          pw.Text(
            'الأصناف',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          ...order.items.map(_pdfOrderItem),
          _pdfDivider(),
          _pdfKeyValue(
            order.usesDeferredSettlement
                ? 'طريقة تسوية المتجر'
                : order.storePaymentConfirmedAt.trim().isNotEmpty
                ? 'المبلغ المستلم من السائق'
                : 'المبلغ المطلوب من السائق',
            order.usesDeferredSettlement
                ? 'دفع آجل مع الشركة'
                : formatIqd(order.driverPaysStoreAmount),
            bold: true,
          ),
          if (order.driverName.trim().isNotEmpty)
            _pdfKeyValue('السائق', order.driverName),
          _pdfDivider(),
          pw.Center(
            child: pw.Text(
              'يرجى مطابقة الأصناف قبل التسليم',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _pdfDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      child: pw.Container(height: 0.6, color: PdfColors.grey500),
    );
  }

  pw.Widget _pdfKeyValue(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: 9.5,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 58,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(child: pw.Text(value, style: style)),
        ],
      ),
    );
  }

  pw.Widget _pdfOrderItem(StoreOrderItem item) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 24,
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  '${item.quantity}x',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Expanded(
                child: pw.Text(
                  item.name,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (item.unit.trim().isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Padding(
              padding: const pw.EdgeInsetsDirectional.only(start: 29),
              child: pw.Text(
                item.unit,
                style: const pw.TextStyle(fontSize: 8.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showOrderDetails(StoreOrder order) {
    final orderStream = watchStorePublicOrder(order.databaseKey);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StreamBuilder<Map<String, dynamic>?>(
        stream: orderStream,
        builder: (context, snapshot) {
          var currentOrder = order;
          final value = snapshot.data;
          if (value != null) {
            currentOrder = StoreOrder.fromFirebase(
              order.databaseKey,
              value.map((key, value) => MapEntry(key.toString(), value)),
            );
          }
          return Directionality(
            textDirection: TextDirection.rtl,
            child: SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.90,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'تفاصيل ${currentOrder.number}',
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _printOrderReceipt(currentOrder),
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: const Text('طباعة'),
                          style: FilledButton.styleFrom(
                            backgroundColor: darkText,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            minimumSize: const Size(0, 38),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _liveDriverCard(currentOrder),
                    const SizedBox(height: 12),
                    _detail('مصدر الطلب', currentOrder.sourceLabel),
                    _detail(
                      currentOrder.isStoreExternal ? 'المستلم' : 'الزبون',
                      currentOrder.customerName,
                    ),
                    if (currentOrder.isStoreExternal) ...[
                      _storeExternalOrderSummary(currentOrder),
                      const SizedBox(height: 8),
                    ],
                    _detail('الدفع', currentOrder.paymentMethod),
                    driverSettlementCard(currentOrder),
                    const SizedBox(height: 8),
                    driverPaymentConfirmationCard(currentOrder),
                    const SizedBox(height: 10),
                    _detail(
                      'حالة المتجر',
                      storeStageLabel(currentOrder.storeStage),
                    ),
                    _detail(
                      'حالة السائق',
                      driverStageLabel(currentOrder.driverStage),
                    ),
                    _detail(
                      'توقيت السائق',
                      storeDriverPlanningText(currentOrder),
                    ),
                    if (currentOrder.note.trim().isNotEmpty)
                      _detail(
                        currentOrder.isStoreExternal
                            ? 'ملاحظة الوصول'
                            : 'ملاحظة الزبون',
                        currentOrder.note,
                      ),
                    if (currentOrder.customerRating > 0) ...[
                      _detail(
                        'تقييم المتجر',
                        '${currentOrder.customerRating}/5',
                      ),
                      if (currentOrder.ratingComment.trim().isNotEmpty)
                        _detail('تعليق التقييم', currentOrder.ratingComment),
                    ],
                    const SizedBox(height: 12),
                    _sectionTitle('الأصناف'),
                    const SizedBox(height: 7),
                    ...currentOrder.items.map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: appColor.withValues(alpha: 0.1),
                          child: Text('${item.quantity}'),
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(item.unit),
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 14),
                    _orderActions(currentOrder),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _liveDriverCard(StoreOrder order) {
    final responsibleDriverName = order.responsibleDriverName;
    final hasDriver = responsibleDriverName.isNotEmpty;
    final arrived = order.driverStage == 'arrivedStore';
    final pickedUp = const {
      'pickedUp',
      'arrivedCustomer',
      'delivered',
    }.contains(order.driverStage);
    final title = order.isCancelled
        ? hasDriver
              ? 'كان الطلب مع $responsibleDriverName عند الإلغاء'
              : 'أُلغي قبل تعيين سائق'
        : order.isDelivered
        ? hasDriver
              ? 'سلّم $responsibleDriverName الطلب'
              : 'تم تسليم الطلب'
        : !hasDriver
        ? order.autoDispatchEnabled
              ? 'السائق مجدول للطلب'
              : 'التوزيع التلقائي متوقف'
        : arrived
        ? 'وصل السائق إلى المتجر'
        : pickedUp
        ? 'استلم السائق الطلب'
        : 'تم تعيين $responsibleDriverName';
    final subtitle = order.isCancelled
        ? 'محفوظ في سجل الطلبات الملغاة'
        : order.isDelivered
        ? 'محفوظ في سجل الطلبات المكتملة'
        : !hasDriver
        ? storeDriverPlanningText(order)
        : order.driverPhone.trim().isEmpty
        ? driverStageLabel(order.driverStage)
        : '${driverStageLabel(order.driverStage)} • ${order.driverPhone}';
    final color = order.isCancelled
        ? Colors.red
        : order.isDelivered
        ? Colors.green
        : arrived
        ? orangeColor
        : pickedUp
        ? Colors.blue
        : appColor;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.delivery_dining_rounded, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (order.hasTrustedLiveDriverLocation) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  const Icon(Icons.my_location_rounded, color: appColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'موقع السائق الحي',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          _storeDriverLocationAge(order),
                          style: const TextStyle(
                            color: mutedText,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => unawaited(_openStoreDriverTracking(order)),
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('تتبع'),
                    style: FilledButton.styleFrom(backgroundColor: appColor),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _storeDriverLocationAge(StoreOrder order) {
    final updatedAt = order.driverLocationUpdatedAt;
    if (updatedAt == null) return 'وقت التحديث غير متاح';
    final difference = DateTime.now().toUtc().difference(updatedAt.toUtc());
    if (difference.isNegative || difference.inSeconds < 20) {
      return 'تحديث الآن';
    }
    if (difference.inMinutes < 1) {
      return 'آخر تحديث قبل ${difference.inSeconds} ثانية';
    }
    if (difference.inHours < 1) {
      return 'آخر تحديث قبل ${difference.inMinutes} دقيقة';
    }
    return 'آخر تحديث قبل ${difference.inHours} ساعة';
  }

  Future<void> _openStoreDriverTracking(StoreOrder order) {
    if (!order.hasTrustedLiveDriverLocation) {
      if (mounted) _message('موقع السائق غير متاح الآن.', error: true);
      return Future<void>.value();
    }

    final orderStream = watchStorePublicOrder(order.databaseKey);
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (trackingContext) => StreamBuilder<Map<String, dynamic>?>(
        stream: orderStream,
        builder: (context, snapshot) {
          var currentOrder = order;
          final value = snapshot.data;
          if (value != null) {
            final data = value.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            if (data['storeId']?.toString() == storeId) {
              currentOrder = StoreOrder.fromFirebase(order.databaseKey, data);
            }
          }
          final hasLiveLocation = currentOrder.hasTrustedLiveDriverLocation;
          final driverLabel = currentOrder.driverName.trim().isEmpty
              ? 'سائق الطلب ${currentOrder.number}'
              : currentOrder.driverName.trim();
          return Directionality(
            textDirection: TextDirection.rtl,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: appColor.withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Icon(
                            Icons.near_me_rounded,
                            color: appColor,
                            size: 27,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'تتبع السائق مباشرة',
                                style: TextStyle(
                                  color: darkText,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                driverLabel,
                                style: const TextStyle(
                                  color: mutedText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () => Navigator.of(trackingContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'إغلاق',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (hasLiveLocation) ...[
                      _StoreLiveDriverMap(
                        latitude: currentOrder.driverLat!,
                        longitude: currentOrder.driverLng!,
                      ),
                      const SizedBox(height: 12),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: hasLiveLocation
                          ? Container(
                              key: const ValueKey('live-driver-location'),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    appColor.withValues(alpha: 0.13),
                                    Colors.teal.withValues(alpha: 0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: appColor.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 13,
                                        height: 13,
                                        decoration: const BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      const Expanded(
                                        child: Text(
                                          'الموقع الحي متصل',
                                          style: TextStyle(
                                            color: darkText,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.gps_fixed_rounded,
                                        color: appColor,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      _storeDriverLocationAge(currentOrder),
                                      style: const TextStyle(
                                        color: mutedText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  const Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      'يتحدث تلقائياً من تطبيق السائق ما دام الطلب معه.',
                                      style: TextStyle(
                                        color: mutedText,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              key: const ValueKey('closed-driver-location'),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.16),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.location_off_rounded,
                                    color: Colors.orange,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'انتهى تتبع اقتراب السائق بعد استلامه الطلب من المتجر.',
                                      style: TextStyle(
                                        color: darkText,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    if (hasLiveLocation) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () =>
                            unawaited(_launchStoreDriverMap(currentOrder)),
                        icon: const Icon(Icons.map_rounded),
                        label: const Text('فتح الموقع على الخريطة'),
                        style: FilledButton.styleFrom(
                          backgroundColor: appColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _launchStoreDriverMap(StoreOrder order) async {
    if (!order.hasTrustedLiveDriverLocation) {
      if (mounted) _message('موقع السائق غير متاح الآن.', error: true);
      return;
    }
    final lat = order.driverLat!;
    final lng = order.driverLng!;
    final label = order.driverName.trim().isEmpty
        ? 'سائق الطلب ${order.number}'
        : order.driverName.trim();
    final nativeUri = Uri(
      scheme: 'geo',
      path: '$lat,$lng',
      queryParameters: <String, String>{'q': '$lat,$lng($label)'},
    );
    var opened = false;
    try {
      opened = await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened) return;
    final fallback = Uri.parse(
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng',
    );
    try {
      opened = await launchUrl(fallback, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      _message('تعذر فتح تطبيق الخرائط الآن.', error: true);
    }
  }

  Widget _storeExternalOrderSummary(StoreOrder order) {
    final scheduled = order.storeExternalServiceType != 'immediate';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orangeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: orangeColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'لقطة التوصيل الخارجي',
            style: TextStyle(color: orangeColor, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _detail('المنطقة', order.deliveryAreaName),
          _detail(
            'هاتف المستلم',
            order.phone.trim().isEmpty ? '-' : order.phone,
          ),
          _detail('نوع الخدمة', scheduled ? 'مجدول' : 'فوري'),
          if (scheduled && order.scheduledDeliveryAt != null)
            _detail(
              'ساعة التوصيل',
              storeExternalScheduledClockLabel(
                context,
                order.scheduledDeliveryAt!,
              ),
            ),
          if (order.storeExternalLate)
            _detail('حالة الموعد', 'متأخر — يبقى الطلب فعالاً'),
          const Divider(height: 18),
          _detail('مبلغ البضاعة', formatIqd(order.storeGrossAmount)),
          _detail('الكروة الإجمالية', formatIqd(order.deliveryFee)),
          _detail('رسم الخدمة', formatIqd(order.serviceFee)),
          _detail(
            'الإجمالي المطلوب من المستلم',
            formatIqd(order.customerTotalToCollect),
          ),
          _detail(
            'المبلغ الذي يدفعه السائق للمتجر',
            formatIqd(order.driverPaysStoreAmount),
          ),
        ],
      ),
    );
  }

  Widget driverSettlementCard(StoreOrder order) {
    final driverPhone = order.driverPhone.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: appColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            order.usesDeferredSettlement
                ? 'طريقة تسوية المتجر'
                : order.storePaymentConfirmedAt.trim().isNotEmpty
                ? 'المبلغ المستلم من السائق'
                : 'المبلغ المطلوب من السائق',
            style: TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            order.usesDeferredSettlement
                ? 'دفع آجل مع الشركة'
                : formatIqd(order.driverPaysStoreAmount),
            style: const TextStyle(
              color: appColor,
              fontWeight: FontWeight.w900,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.delivery_dining_rounded,
                color: appColor,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  order.driverName.trim().isEmpty
                      ? 'سيظهر رقم السائق بعد قبول الطلب'
                      : driverPhone.isEmpty
                      ? 'السائق: ${order.driverName} • الرقم غير متوفر بعد'
                      : 'السائق: ${order.driverName} • $driverPhone',
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget driverPaymentConfirmationCard(StoreOrder order) {
    if (!order.requiresDriverCashPayment) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: appColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: appColor.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            const Icon(Icons.credit_card_rounded, color: appColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                order.usesDeferredSettlement
                    ? 'لا تستلم نقداً من السائق؛ يُضاف صافي هذا الطلب إلى مستحقات المتجر لدى الشركة بعد التسليم.'
                    : 'هذا الطلب لا يحتاج تأكيد استلام مبلغ نقدي من السائق.',
                style: const TextStyle(
                  color: darkText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final confirmed = order.storePaymentConfirmedAt.trim().isNotEmpty;
    final canConfirm =
        const {
          'accepted',
          'preparing',
          'readyForPickup',
        }.contains(order.storeStage) &&
        order.driverStage == 'arrivedStore' &&
        order.driverId.trim().isNotEmpty;
    final color = confirmed ? Colors.green : orangeColor;
    final title = confirmed ? 'تم تأكيد دفع السائق' : 'تأكيد دفع السائق';
    final subtitle = confirmed
        ? 'تم اعتماد استلام المبلغ، ويستطيع السائق متابعة خطوات الطلب.'
        : order.driverName.trim().isEmpty
        ? 'سيظهر زر التأكيد بعد تعيين السائق ووصوله إلى المتجر.'
        : !order.driverArrivedAtStore
        ? 'بانتظار أن يؤكد السائق وصوله إلى المتجر قبل استلام المبلغ.'
        : 'اضغط مطولاً بعد استلام ${formatIqd(order.driverPaysStoreAmount)} من ${order.driverName}.';
    return AnimatedBuilder(
      animation: _paymentHoldController,
      builder: (context, _) {
        final isHolding = _paymentHoldOrderKey == order.databaseKey;
        final progress = isHolding ? _paymentHoldController.value : 0.0;
        final buttonTitle = isHolding ? 'استمر بالضغط' : title;
        final buttonSubtitle = isHolding
            ? 'اكتمال الشريط يؤكد استلام الدفع.'
            : subtitle;
        final disabled = _busy || confirmed || !canConfirm;

        return Listener(
          onPointerDown: disabled
              ? null
              : (_) => _startPaymentConfirmationHold(order),
          onPointerUp: (_) => _cancelPaymentConfirmationHold(),
          onPointerCancel: (_) => _cancelPaymentConfirmationHold(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_busy) return;
              if (confirmed) {
                _message('تم تأكيد دفع السائق مسبقاً');
              } else if (order.driverId.trim().isEmpty) {
                _message('بانتظار تعيين السائق أولاً');
              } else if (!order.driverArrivedAtStore) {
                _message('بانتظار وصول السائق إلى المتجر أولاً');
              } else {
                _message('اضغط مطولاً حتى يكتمل الشريط');
              }
            },
            child: AnimatedScale(
              scale: isHolding ? 0.985 : 1,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: color.withValues(alpha: isHolding ? 0.34 : 0.13),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: isHolding ? 0.12 : 0.06),
                      blurRadius: isHolding ? 13 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    children: [
                      PositionedDirectional(
                        bottom: 0,
                        start: 0,
                        end: 0,
                        child: Container(
                          height: 5,
                          color: color.withValues(alpha: 0.08),
                          alignment: AlignmentDirectional.centerStart,
                          child: FractionallySizedBox(
                            widthFactor: progress.clamp(0, 1).toDouble(),
                            alignment: AlignmentDirectional.centerStart,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    color.withValues(alpha: 0.55),
                                    color,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 9, 10, 13),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                confirmed
                                    ? Icons.verified_rounded
                                    : isHolding
                                    ? Icons.touch_app_rounded
                                    : Icons.back_hand_rounded,
                                color: color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          buttonTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (!confirmed && canConfirm)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: color.withValues(
                                              alpha: 0.09,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          ),
                                          child: Text(
                                            isHolding
                                                ? '${(progress * 100).clamp(0, 100).round()}%'
                                                : 'ضغط مطوّل',
                                            style: TextStyle(
                                              color: color,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    buttonSubtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detail(String title, String value, {bool important = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title: ',
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w800,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: important ? appColor : Colors.black87,
                fontWeight: important ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
    );
  }

  Widget _liveStatusCard({
    required _StoreLiveStatus status,
    required String loadingText,
    required String errorText,
  }) {
    final failed = status == _StoreLiveStatus.error;
    return Card(
      color: failed ? Colors.red.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (failed)
              Icon(Icons.cloud_off_rounded, color: Colors.red.shade700)
            else
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: orangeColor,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                failed ? errorText : loadingText,
                style: TextStyle(
                  color: failed ? Colors.red.shade800 : Colors.orange.shade900,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
            ),
            if (failed) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () =>
                    _requestLiveRestart(resetAttempt: true, refreshToken: true),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatIqd(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return '${buffer.toString()} د.ع';
}

String timeAgo(DateTime date) {
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return 'الآن';
  if (difference.inMinutes < 60) return 'منذ ${difference.inMinutes} د';
  if (difference.inHours < 24) return 'منذ ${difference.inHours} س';
  return 'منذ ${difference.inDays} يوم';
}

String storeStageLabel(String stage) {
  switch (stage) {
    case 'awaitingAcceptance':
      return 'طلب جديد';
    case 'accepted':
      return 'تم القبول';
    case 'preparing':
      return 'قيد التحضير';
    case 'readyForPickup':
      return 'جاهز للاستلام';
    case 'handedToDriver':
      return 'استلمه السائق';
    case 'returningToStore':
      return 'إرجاع للمتجر';
    case 'rejected':
      return 'مرفوض';
    case 'cancelled':
      return 'ملغي';
    default:
      return stage;
  }
}

Color storeStageColor(String stage) {
  switch (stage) {
    case 'awaitingAcceptance':
      return orangeColor;
    case 'accepted':
    case 'preparing':
      return appColor;
    case 'readyForPickup':
      return Colors.blue;
    case 'handedToDriver':
      return Colors.purple;
    case 'returningToStore':
      return Colors.red;
    case 'rejected':
    case 'cancelled':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

String driverStageLabel(String stage) {
  switch (stage) {
    case 'waitingForStore':
      return 'بانتظار المتجر';
    case 'searchingDriver':
      return 'جار البحث عن سائق';
    case 'offered':
      return 'بانتظار موافقة السائق';
    case 'accepted':
      return 'وافق السائق';
    case 'arrivedStore':
      return 'السائق وصل للمتجر';
    case 'pickedUp':
      return 'استلم السائق الطلب';
    case 'arrivedCustomer':
      return 'وصل إلى الزبون';
    case 'returningToStore':
      return 'السائق يرجع الطلب للمتجر';
    case 'delivered':
      return 'تم التسليم';
    case 'cancelled':
      return 'ملغي';
    default:
      return stage;
  }
}

String storeDriverPlanningText(StoreOrder order) {
  if (order.driverName.trim().isNotEmpty) {
    return driverStageLabel(order.driverStage);
  }
  if (!order.autoDispatchEnabled || order.dispatchStatus == 'manualDispatch') {
    return 'التوزيع التلقائي متوقف ويحتاج تعيين سائق يدوياً';
  }
  if (order.dispatchStatus == 'searchingDriver' ||
      order.driverStage == 'searchingDriver' ||
      order.storeStage == 'readyForPickup') {
    return 'بدأ البحث عن سائق الآن';
  }
  final scheduledAt = order.driverDispatchScheduledAt;
  if (scheduledAt == null) {
    return 'سيبدأ البحث عن سائق قبل جاهزية الطلب';
  }
  final remaining = scheduledAt.difference(DateTime.now());
  if (!remaining.isNegative && remaining.inMinutes > 0) {
    return 'سيبدأ البحث عن سائق بعد ${remaining.inMinutes} د';
  }
  return 'بدأ وقت إرسال الطلب للسائق';
}
