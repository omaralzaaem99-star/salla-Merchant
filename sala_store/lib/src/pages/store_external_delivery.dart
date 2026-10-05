part of sala_store;

const String _storeExternalCreateRetryNamespace =
    'store_external_delivery_create_v1';
const String _storeExternalCancelRetryNamespace =
    'store_external_delivery_cancel_v1';

bool _storeExternalOutcomeMayBeUnknown(Object error) {
  if (error is TimeoutException) return true;
  return error is FirebaseFunctionsException &&
      const <String>{
        'deadline-exceeded',
        'unavailable',
        'internal',
        'unknown',
      }.contains(error.code);
}

String _storeExternalErrorMessage(Object error) {
  if (_storeExternalOutcomeMayBeUnknown(error)) {
    return 'النتيجة غير مؤكدة. احتفظنا بمعرّف المحاولة والحمولة نفسيهما؛ شخّص الحالة قبل إعادة الإرسال.';
  }
  if (error is FirebaseFunctionsException) {
    final message = error.message?.trim() ?? '';
    if (message.isNotEmpty) return message;
    if (error.code == 'permission-denied') {
      return 'حساب المتجر غير مخول لهذه العملية.';
    }
  }
  return 'تعذر تنفيذ عملية التوصيل الخارجي. حدّث البيانات وحاول مجدداً.';
}

String _storeExternalReviewErrorMessage(Object error) {
  // The quote is read-only: a network failure here is not an unknown creation.
  if (_storeExternalOutcomeMayBeUnknown(error)) {
    return 'تعذر الاتصال لحساب الكروة. تحقق من الإنترنت ثم اضغط المراجعة مجدداً. لم يُنشأ أي طلب.';
  }
  return 'لم يُنشأ أي طلب. ${_storeExternalErrorMessage(error)}';
}

String _newStoreExternalRequestId(String action) {
  final safeStoreId = storeId
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
      .substring(0, storeId.length.clamp(0, 48).toInt());
  return 'store_external_${action}_${safeStoreId}_${DateTime.now().microsecondsSinceEpoch}';
}

FirebaseFunctions get _storeExternalFunctions =>
    FirebaseFunctions.instanceFor(region: 'europe-west1');

DateTime? storeExternalScheduledDateTimeForClock({
  required DateTime now,
  required TimeOfDay clock,
}) {
  var selected = DateTime(
    now.year,
    now.month,
    now.day,
    clock.hour,
    clock.minute,
  );
  if (!selected.isAfter(now)) {
    selected = selected.add(const Duration(days: 1));
  }
  if (selected.isAfter(now.add(const Duration(hours: 12)))) return null;
  return selected;
}

String storeExternalScheduledClockLabel(
  BuildContext context,
  DateTime scheduledAt,
) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(scheduledAt.toLocal()),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

String storeExternalServiceTypeLabel(String serviceType) {
  switch (serviceType) {
    case sallaCourierServiceImmediate:
      return 'فوري';
    case sallaCourierServiceFlexibleSixHours:
      return 'خلال 6 ساعات';
    case sallaCourierServiceNextDayTwelveHours:
      return 'اليوم التالي • خلال 12 ساعة';
    default:
      return 'مجدول';
  }
}

Future<StoreOrder?> showStoreExternalDeliveryComposer(
  BuildContext context, {
  SallaGeoPoint? initialDeliveryPoint,
  VoidCallback? onInitialDeliveryPointApplied,
}) {
  return showSallaLifecycleSafeModalBottomSheet<StoreOrder>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF4F7F7),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => _StoreExternalDeliveryComposer(
      initialDeliveryPoint: initialDeliveryPoint,
      onInitialDeliveryPointApplied: onInitialDeliveryPointApplied,
    ),
  );
}

Future<StoreExternalDeliveryArea?> showStoreExternalDeliveryAreaPicker(
  BuildContext context, {
  required List<StoreExternalDeliveryArea> areas,
  String selectedAreaId = '',
  bool scheduled = false,
  SallaGeoPoint? labelPoint,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final selected = await showModalBottomSheet<StoreExternalDeliveryArea>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF8FAFC),
    builder: (_) => _StoreExternalDeliveryAreaPicker(
      areas: areas,
      selectedAreaId: selectedAreaId,
      scheduled: scheduled,
      labelPoint: labelPoint,
    ),
  );
  // يمنع استعادة تركيز حقل المبلغ بعد إغلاق ورقة المناطق.
  FocusManager.instance.primaryFocus?.unfocus();
  return selected;
}

class _StoreExternalDeliveryAreaPicker extends StatefulWidget {
  final List<StoreExternalDeliveryArea> areas;
  final String selectedAreaId;
  final bool scheduled;
  final SallaGeoPoint? labelPoint;

  const _StoreExternalDeliveryAreaPicker({
    required this.areas,
    required this.selectedAreaId,
    required this.scheduled,
    this.labelPoint,
  });

  @override
  State<_StoreExternalDeliveryAreaPicker> createState() =>
      _StoreExternalDeliveryAreaPickerState();
}

class _StoreExternalDeliveryAreaPickerState
    extends State<_StoreExternalDeliveryAreaPicker> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(StoreExternalDeliveryArea area) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(area);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(0xFFE0F2F1),
                      child: Icon(Icons.route_rounded, color: appColor),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.labelPoint == null
                                ? 'اختر منطقة التسليم'
                                : 'أكد اسم منطقة الدبوس',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: darkText,
                            ),
                          ),
                          Text(
                            widget.labelPoint == null
                                ? 'المناطق من الأقرب لمتجرك إلى الأبعد؛ الكروة حسب نوع الطلب المحدد.'
                                : 'الأقرب أولاً للمساعدة فقط، وليس تحديداً لحدود المنطقة. اختر الاسم الصحيح؛ الدبوس والكروة لا يتغيران.',
                            key: const ValueKey(
                              'store_external_area_proximity_hint',
                            ),
                            style: TextStyle(
                              color: mutedText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('store_external_area_search'),
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      key: const ValueKey(
                        'store_external_flexible_search_clear',
                      ),
                      tooltip: 'مسح البحث',
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    hintText: 'اكتب جزءاً من اسم المنطقة أو الشارع أو المجمع',
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) {
                      final scores = {
                        for (final area in widget.areas)
                          area.id: area.searchScore(value.text),
                      };
                      final rows = widget.areas
                          .where((area) => scores[area.id] != null)
                          .toList(growable: false);
                      final point = widget.labelPoint;
                      if (point != null) {
                        double distance(StoreExternalDeliveryArea area) {
                          final anchor = area.pricingAnchor;
                          return anchor == null
                              ? double.infinity
                              : sallaGeoDistanceKm(
                                  point.lat,
                                  point.lng,
                                  anchor.lat,
                                  anchor.lng,
                                );
                        }

                        rows.sort((a, b) {
                          final match = scores[a.id]!.compareTo(scores[b.id]!);
                          if (match != 0) return match;
                          final order = distance(a).compareTo(distance(b));
                          return order != 0 ? order : a.id.compareTo(b.id);
                        });
                      } else {
                        // The trusted configuration supplies this store's
                        // distance. Sorting must not change fees or selection.
                        double distance(StoreExternalDeliveryArea area) =>
                            area.distanceKm.isFinite && area.distanceKm >= 0
                            ? area.distanceKm
                            : double.infinity;
                        rows.sort((a, b) {
                          final match = scores[a.id]!.compareTo(scores[b.id]!);
                          if (match != 0) return match;
                          final order = distance(a).compareTo(distance(b));
                          return order != 0 ? order : a.id.compareTo(b.id);
                        });
                      }
                      if (rows.isEmpty) {
                        return const Center(
                          child: Text('لا توجد منطقة مطابقة'),
                        );
                      }
                      return ListView.builder(
                        key: const PageStorageKey<String>(
                          'store_external_area_list',
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        scrollCacheExtent: const ScrollCacheExtent.pixels(240),
                        itemCount: rows.length + 1,
                        itemBuilder: (context, index) {
                          if (index == rows.length) {
                            return const _StoreExternalKeyboardGap(minimum: 18);
                          }
                          final area = rows[index];
                          return _StoreExternalDeliveryAreaTile(
                            key: ValueKey<String>(
                              'store_external_area_${area.id}',
                            ),
                            area: area,
                            selected: area.id == widget.selectedAreaId,
                            scheduled: widget.scheduled,
                            labelOnly: widget.labelPoint != null,
                            onTap: () => _select(area),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreExternalDeliveryAreaTile extends StatelessWidget {
  final StoreExternalDeliveryArea area;
  final bool selected;
  final bool scheduled;
  final VoidCallback onTap;
  final bool labelOnly;

  const _StoreExternalDeliveryAreaTile({
    super.key,
    required this.area,
    required this.selected,
    required this.scheduled,
    required this.onTap,
    this.labelOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? const Color(0xFFE7F2F0) : Colors.white,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 19),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    area.nameAr,
                    style: const TextStyle(fontSize: 16, color: darkText),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_rounded, color: appColor, size: 20),
                ],
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    labelOnly
                        ? 'اختيار الاسم فقط'
                        : area.requiresDeliveryPin
                        ? 'الأجرة بعد تحديد الدبوس'
                        : formatIqd(
                            scheduled ? area.scheduledFee : area.immediateFee,
                          ),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 15,
                      color: appColor,
                      fontWeight: FontWeight.w800,
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
}

Future<SallaGeoPoint> _storeExternalCurrentLocation() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
    const Duration(seconds: 5),
  );
  if (!serviceEnabled) {
    throw StateError('فعّل خدمة الموقع من الهاتف ثم حاول مرة أخرى.');
  }
  var permission = await Geolocator.checkPermission().timeout(
    const Duration(seconds: 5),
  );
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission().timeout(
      const Duration(seconds: 20),
    );
  }
  if (permission == LocationPermission.denied) {
    throw StateError('اسمح لتطبيق المتجر باستخدام الموقع ثم حاول مرة أخرى.');
  }
  if (permission == LocationPermission.deniedForever) {
    throw StateError('فعّل صلاحية الموقع لتطبيق المتجر من إعدادات الهاتف.');
  }
  var best = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      timeLimit: Duration(seconds: 14),
    ),
  );
  for (var attempt = 0; attempt < 2 && best.accuracy > 35; attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 550));
    try {
      final next = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (next.accuracy < best.accuracy) best = next;
    } catch (_) {
      break;
    }
  }
  return SallaGeoPoint(best.latitude, best.longitude);
}

class _StoreExternalDeliveryMapPickerPage extends StatefulWidget {
  final SallaGeoPoint? initialPoint;

  const _StoreExternalDeliveryMapPickerPage({this.initialPoint});

  @override
  State<_StoreExternalDeliveryMapPickerPage> createState() =>
      _StoreExternalDeliveryMapPickerPageState();
}

class _StoreExternalDeliveryMapPickerPageState
    extends State<_StoreExternalDeliveryMapPickerPage> {
  final MapController _mapController = MapController();
  late LatLng _point;
  late bool _ready;
  bool _locating = false;
  int _pointRevision = 0;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPoint;
    _point = LatLng(initial?.lat ?? 33.3152, initial?.lng ?? 44.3661);
    _ready = initial != null;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_locating) return;
    final revision = _pointRevision;
    setState(() {
      _locating = true;
      _error = '';
    });
    try {
      final location = await _storeExternalCurrentLocation();
      if (!mounted || revision != _pointRevision) return;
      final next = LatLng(location.lat, location.lng);
      setState(() {
        _point = next;
        _pointRevision += 1;
        _ready = true;
      });
      _mapController.move(next, 18);
    } catch (error) {
      if (mounted && revision == _pointRevision) {
        setState(() {
          _error = error is StateError
              ? error.message.toString()
              : 'تعذر تحديد الموقع الحالي. حرّك الخريطة وحدد الدبوس يدوياً.';
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _save() {
    if (!_ready) {
      setState(() => _error = 'اضغط على الخريطة لتحديد موقع التسليم أولاً.');
      return;
    }
    Navigator.of(context).pop(SallaGeoPoint(_point.latitude, _point.longitude));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text('حدد موقع التسليم الدقيق'),
          actions: [
            IconButton(
              tooltip: 'موقعي الحالي',
              onPressed: _locating ? null : _locate,
              icon: _locating
                  ? const SizedBox.square(
                      dimension: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _point,
                            initialZoom: _ready ? 17 : 11,
                            minZoom: 4,
                            maxZoom: 19,
                            onTap: (_, point) {
                              setState(() {
                                _pointRevision += 1;
                                _point = point;
                                _ready = true;
                                _error = '';
                              });
                              _mapController.move(point, 18);
                            },
                            onPositionChanged: (camera, hasGesture) {
                              if (!hasGesture) return;
                              _pointRevision += 1;
                              _point = camera.center;
                              if (!_ready && mounted)
                                setState(() => _ready = true);
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.selafood.store',
                            ),
                            storeOpenStreetMapAttribution(),
                          ],
                        ),
                        const IgnorePointer(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 38),
                              child: Icon(
                                Icons.location_pin,
                                color: orangeColor,
                                size: 52,
                              ),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          start: 12,
                          end: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Text(
                              'حرّك الخريطة حتى يصبح الدبوس فوق الموقع المرسل، ثم راجعه واحفظه.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      _ready ? 'اعتماد الموقع للمراجعة' : 'حدد نقطة أولاً',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoreExternalDestinationPreview extends StatelessWidget {
  final double latitude;
  final double longitude;

  const _StoreExternalDestinationPreview({
    required this.latitude,
    required this.longitude,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 150,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 16.5,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
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
                  width: 48,
                  height: 48,
                  child: const Icon(
                    Icons.location_pin,
                    color: orangeColor,
                    size: 46,
                  ),
                ),
              ],
            ),
            storeOpenStreetMapAttribution(),
          ],
        ),
      ),
    );
  }
}

class _StoreExternalKeyboardGap extends StatelessWidget {
  final double minimum;

  const _StoreExternalKeyboardGap({required this.minimum});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: minimum + MediaQuery.viewInsetsOf(context).bottom);
  }
}

Future<String?> showStoreExternalCancellationReasonDialog(
  BuildContext context, {
  required String orderNumber,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _StoreExternalCancellationReasonDialog(orderNumber: orderNumber),
  );
}

class _StoreExternalCancellationReasonDialog extends StatefulWidget {
  const _StoreExternalCancellationReasonDialog({required this.orderNumber});

  final String orderNumber;

  @override
  State<_StoreExternalCancellationReasonDialog> createState() =>
      _StoreExternalCancellationReasonDialogState();
}

class _StoreExternalCancellationReasonDialogState
    extends State<_StoreExternalCancellationReasonDialog> {
  final TextEditingController _reasonController = TextEditingController();
  String _validationError = '';

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _validationError = 'اكتب سبب الإلغاء أولاً.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('إلغاء ${widget.orderNumber}'),
      content: TextField(
        key: const ValueKey<String>('store_external_cancel_reason'),
        controller: _reasonController,
        autofocus: true,
        maxLength: 500,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _confirm(),
        decoration: InputDecoration(
          labelText: 'سبب الإلغاء',
          errorText: _validationError.isEmpty ? null : _validationError,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('رجوع'),
        ),
        FilledButton(
          key: const ValueKey<String>('store_external_cancel_confirm'),
          onPressed: _confirm,
          child: const Text('تأكيد الإلغاء'),
        ),
      ],
    );
  }
}

class _StoreExternalDeliveryComposer extends StatefulWidget {
  final SallaGeoPoint? initialDeliveryPoint;
  final VoidCallback? onInitialDeliveryPointApplied;

  const _StoreExternalDeliveryComposer({
    this.initialDeliveryPoint,
    this.onInitialDeliveryPointApplied,
  });

  @override
  State<_StoreExternalDeliveryComposer> createState() =>
      _StoreExternalDeliveryComposerState();
}

class _StoreExternalDeliveryComposerState
    extends State<_StoreExternalDeliveryComposer> {
  final TextEditingController _goodsController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _goodsFocusNode = FocusNode();
  final GlobalKey _goodsSectionKey = GlobalKey(
    debugLabel: 'store_external_step_goods',
  );
  final GlobalKey _destinationSectionKey = GlobalKey(
    debugLabel: 'store_external_step_area',
  );
  final GlobalKey _scheduleSectionKey = GlobalKey(
    debugLabel: 'store_external_step_schedule',
  );
  StoreExternalDeliveryConfiguration? _configuration;
  StoreExternalDeliveryArea? _selectedArea;
  StoreExternalDeliveryArea? _selectedMapLabelArea;
  int _destinationRevision = 0;
  SallaGeoPoint? _selectedDeliveryPoint;
  StoreExternalDeliveryQuote? _precisePointImmediateQuote;
  StoreExternalDeliveryRetryIntent? _pendingIntent;
  Timer? _serviceTransitionTimer;
  DateTime? _scheduledFor;
  String _scheduleType = sallaCourierServiceImmediate;
  bool _loading = true;
  bool _busy = false;
  bool _sendingCreate = false;
  bool _precisePointFareLoading = false;
  int _precisePointFareGeneration = 0;
  String _error = '';
  String _draftValidationMessage = '';
  bool _initialDeliveryPointApplied = false;
  bool _restoredInitialDraft = false;
  int _loadGeneration = 0;
  int _areaRefreshGeneration = 0;
  bool _refreshingAreas = false;

  bool get _scheduled => _scheduleType != sallaCourierServiceImmediate;

  String get _environment => Firebase.app().options.projectId.trim();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _serviceTransitionTimer?.cancel();
    _goodsFocusNode.dispose();
    _goodsController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    final callable = _storeExternalFunctions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
    );
    final response = await callable
        .call<Map<String, dynamic>>(payload)
        .timeout(const Duration(seconds: 40));
    return storeExternalObject(response.data);
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final ownerUid = sallaIdentity.uid;
    final ownerStoreId = storeId;
    final restoreDraft = !_restoredInitialDraft;
    bool isCurrent() =>
        mounted &&
        generation == _loadGeneration &&
        ownerUid == sallaIdentity.uid &&
        ownerStoreId == storeId;
    try {
      final results = await Future.wait<Object?>([
        _call('getStoreExternalDeliveryConfiguration', const {}),
        restoreDraft
            ? SallaAuthService.loadLocalRetryIntents(
                role: SallaUserRole.store,
                environment: _environment,
                ownerUid: sallaIdentity.uid,
                namespace: _storeExternalCreateRetryNamespace,
              )
            : Future.value(const <String, dynamic>{}),
      ]);
      if (!isCurrent()) return;
      final configuration = StoreExternalDeliveryConfiguration.fromMap(
        storeExternalObject(results[0]),
      );
      final intents = storeExternalObject(results[1]);
      StoreExternalDeliveryRetryIntent? pending;
      final rawIntent = intents[storeId];
      if (rawIntent is Map) {
        try {
          final candidate = StoreExternalDeliveryRetryIntent.fromLocal(
            storeExternalObject(rawIntent),
          );
          if (candidate.requestId.isNotEmpty && candidate.payload.isNotEmpty) {
            pending = candidate;
          } else {
            await _clearIntent();
          }
        } on FormatException {
          await _clearIntent();
        }
      }
      if (!isCurrent()) return;
      var appliedInitialPoint = false;
      setState(() {
        _configuration = configuration;
        if (_pendingIntent == null &&
            !_busy &&
            configuration.requiresDeliveryPin &&
            _selectedArea != null) {
          _selectedArea = null;
          _destinationRevision += 1;
          _precisePointImmediateQuote = null;
        }
        // A configuration refresh must never replace an in-flight receipt.
        if (restoreDraft) _pendingIntent = pending;
        if (restoreDraft && pending != null) {
          _restoreDraft(pending.payload, configuration);
        } else if (restoreDraft &&
            widget.initialDeliveryPoint != null &&
            !_initialDeliveryPointApplied) {
          _selectedArea = null;
          _destinationRevision += 1;
          _selectedDeliveryPoint = widget.initialDeliveryPoint;
          _selectedMapLabelArea = _nearestMapLabelArea(
            widget.initialDeliveryPoint!,
            areas: configuration.areas,
          );
          if (!_initialDeliveryPointApplied) {
            _initialDeliveryPointApplied = true;
            appliedInitialPoint = true;
          }
        }
        _restoredInitialDraft = true;
        if (_pendingIntent == null &&
            !_busy &&
            _selectedDeliveryPoint != null) {
          final matches = configuration.areas.where(
            (area) =>
                area.id == _selectedMapLabelArea?.id &&
                area.nameAr == _selectedMapLabelArea?.nameAr,
          );
          _selectedMapLabelArea = matches.isEmpty
              ? _nearestMapLabelArea(
                  _selectedDeliveryPoint!,
                  areas: configuration.areas,
                )
              : matches.first;
        }
      });
      if (appliedInitialPoint) widget.onInitialDeliveryPointApplied?.call();
      final precisePoint = _selectedDeliveryPoint;
      if (precisePoint != null) {
        unawaited(_refreshPrecisePointImmediateFare(precisePoint));
      }
      _scheduleServiceTransitionRefresh(configuration);
    } catch (error) {
      if (isCurrent())
        setState(() => _error = _storeExternalErrorMessage(error));
    } finally {
      if (isCurrent()) setState(() => _loading = false);
    }
  }

  void _scheduleServiceTransitionRefresh(
    StoreExternalDeliveryConfiguration configuration,
  ) {
    _serviceTransitionTimer?.cancel();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final transitions = <int>[
      configuration.serviceNextTransitionAtMs,
      if (configuration.subscriptionStatus == 'active')
        configuration.subscriptionEndsAt?.millisecondsSinceEpoch ?? 0,
      if (configuration.subscriptionStatus == 'scheduled')
        configuration.subscriptionStartsAt?.millisecondsSinceEpoch ?? 0,
    ].where((value) => value > nowMs).toList()..sort();
    final delayMs = transitions.isEmpty ? 0 : transitions.first - nowMs;
    if (delayMs <= 0) return;
    _serviceTransitionTimer = Timer(Duration(milliseconds: delayMs + 250), () {
      if (!mounted) return;
      setState(() => _loading = true);
      unawaited(_load());
    });
  }

  void _restoreDraft(
    Map<String, dynamic> payload,
    StoreExternalDeliveryConfiguration configuration,
  ) {
    _goodsController.text = formatStoreAmountInput(
      payload['goodsAmount']?.toString() ?? '',
    );
    _phoneController.text = normalizeStoreInputDigits(
      payload['recipientPhone']?.toString() ?? '',
    );
    _noteController.text = payload['note']?.toString() ?? '';
    final areaId = payload['areaId']?.toString() ?? '';
    _selectedArea = null;
    _selectedMapLabelArea = null;
    _destinationRevision += 1;
    _selectedDeliveryPoint = null;
    for (final area in configuration.areas) {
      if (area.id == areaId) {
        _selectedArea = area;
        break;
      }
    }
    if (_selectedArea == null) {
      final lat = double.tryParse(payload['deliveryLat']?.toString() ?? '');
      final lng = double.tryParse(payload['deliveryLng']?.toString() ?? '');
      if (lat != null && lng != null) {
        _selectedDeliveryPoint = SallaGeoPoint(lat, lng);
        final labels = configuration.areas.where(
          (area) => area.id == payload['deliveryLabelAreaId'],
        );
        _selectedMapLabelArea = labels.isEmpty ? null : labels.first;
      }
    }
    final restoredServiceType = payload['serviceType']?.toString().trim() ?? '';
    _scheduleType = restoredServiceType.isEmpty
        ? sallaCourierServiceImmediate
        : restoredServiceType;
    _scheduledFor = DateTime.tryParse(
      payload['scheduledFor']?.toString() ?? '',
    )?.toLocal();
  }

  Future<void> _saveIntent(StoreExternalDeliveryRetryIntent intent) {
    return SallaAuthService.saveLocalRetryIntent(
      role: SallaUserRole.store,
      environment: _environment,
      ownerUid: sallaIdentity.uid,
      namespace: _storeExternalCreateRetryNamespace,
      intentId: storeId,
      payload: intent.toLocal(),
    );
  }

  Future<void> _clearIntent() {
    return SallaAuthService.removeLocalRetryIntent(
      role: SallaUserRole.store,
      environment: _environment,
      ownerUid: sallaIdentity.uid,
      namespace: _storeExternalCreateRetryNamespace,
      intentId: storeId,
    );
  }

  Future<void> _chooseArea() async {
    final configuration = _configuration;
    if (configuration == null ||
        _busy ||
        _pendingIntent != null ||
        _refreshingAreas) {
      return;
    }
    if (configuration.requiresDeliveryPin) {
      await _chooseDestination();
      return;
    }
    final freshConfiguration = await _refreshAreaConfiguration();
    if (!mounted || freshConfiguration == null) return;
    final revision = _destinationRevision;
    final ownerUid = sallaIdentity.uid;
    final selected = await showStoreExternalDeliveryAreaPicker(
      context,
      areas: freshConfiguration.areas,
      selectedAreaId: _selectedArea?.id ?? '',
      scheduled: _scheduled,
    );
    if (selected != null &&
        mounted &&
        !_busy &&
        _pendingIntent == null &&
        revision == _destinationRevision &&
        ownerUid == sallaIdentity.uid) {
      _precisePointFareGeneration += 1;
      setState(() {
        _selectedArea = selected;
        _selectedMapLabelArea = null;
        _destinationRevision += 1;
        _selectedDeliveryPoint = null;
        _precisePointImmediateQuote = null;
        _precisePointFareLoading = false;
        _error = '';
        _draftValidationMessage = '';
      });
    }
  }

  Future<StoreExternalDeliveryConfiguration?>
  _refreshAreaConfiguration() async {
    final ownerUid = sallaIdentity.uid;
    final ownerStoreId = storeId;
    final generation = ++_areaRefreshGeneration;
    setState(() => _refreshingAreas = true);
    try {
      final result = await _call(
        'getStoreExternalDeliveryConfiguration',
        const {},
      );
      if (!mounted ||
          generation != _areaRefreshGeneration ||
          ownerUid != sallaIdentity.uid ||
          ownerStoreId != storeId) {
        return null;
      }
      final refreshed = StoreExternalDeliveryConfiguration.fromMap(result);
      StoreExternalDeliveryArea? refreshedArea(String id) {
        for (final area in refreshed.areas) {
          if (area.id == id) return area;
        }
        return null;
      }

      setState(() {
        _configuration = refreshed;
        if (_selectedArea != null) {
          _selectedArea = refreshedArea(_selectedArea!.id);
          if (_selectedArea == null) {
            _destinationRevision += 1;
            _precisePointImmediateQuote = null;
          }
        }
        if (_selectedMapLabelArea != null) {
          _selectedMapLabelArea = refreshedArea(_selectedMapLabelArea!.id);
        }
        _error = '';
      });
      _scheduleServiceTransitionRefresh(refreshed);
      return refreshed;
    } catch (error) {
      if (mounted && generation == _areaRefreshGeneration) {
        setState(() => _error = _storeExternalErrorMessage(error));
      }
      return null;
    } finally {
      if (mounted && generation == _areaRefreshGeneration) {
        setState(() => _refreshingAreas = false);
      }
    }
  }

  bool _samePrecisePoint(SallaGeoPoint? left, SallaGeoPoint right) {
    return left != null && left.lat == right.lat && left.lng == right.lng;
  }

  StoreExternalDeliveryArea? _nearestMapLabelArea(
    SallaGeoPoint point, {
    Iterable<StoreExternalDeliveryArea>? areas,
  }) {
    final candidates = (areas ?? _configuration?.areas ?? const [])
        .where((area) {
          final anchor = area.pricingAnchor;
          return area.id.trim().isNotEmpty &&
              area.nameAr.trim().isNotEmpty &&
              anchor != null &&
              anchor.lat.isFinite &&
              anchor.lng.isFinite &&
              anchor.lat.abs() <= 90 &&
              anchor.lng.abs() <= 180;
        })
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aAnchor = a.pricingAnchor!;
      final bAnchor = b.pricingAnchor!;
      final distance =
          sallaGeoDistanceKm(
            point.lat,
            point.lng,
            aAnchor.lat,
            aAnchor.lng,
          ).compareTo(
            sallaGeoDistanceKm(point.lat, point.lng, bAnchor.lat, bAnchor.lng),
          );
      return distance != 0 ? distance : a.id.compareTo(b.id);
    });
    return candidates.first;
  }

  Future<void> _chooseMapLabel() async {
    final point = _selectedDeliveryPoint;
    final configuration = _configuration;
    if (point == null ||
        configuration == null ||
        _busy ||
        _pendingIntent != null ||
        _refreshingAreas)
      return;
    final freshConfiguration = await _refreshAreaConfiguration();
    if (!mounted || freshConfiguration == null) return;
    final revision = _destinationRevision;
    final ownerUid = sallaIdentity.uid;
    final selected = await showStoreExternalDeliveryAreaPicker(
      context,
      areas: freshConfiguration.areas,
      selectedAreaId: _selectedMapLabelArea?.id ?? '',
      labelPoint: point,
    );
    if (!mounted ||
        selected == null ||
        _busy ||
        _pendingIntent != null ||
        revision != _destinationRevision ||
        ownerUid != sallaIdentity.uid ||
        !_samePrecisePoint(_selectedDeliveryPoint, point))
      return;
    final current = _configuration!.areas.where(
      (area) => area.id == selected.id && area.nameAr == selected.nameAr,
    );
    if (current.isEmpty) return;
    setState(() {
      _selectedMapLabelArea = current.first;
      _draftValidationMessage = '';
      _error = '';
    });
  }

  Future<void> _refreshPrecisePointImmediateFare(SallaGeoPoint point) async {
    final generation = ++_precisePointFareGeneration;
    if (!mounted) return;
    setState(() {
      _precisePointImmediateQuote = null;
      _precisePointFareLoading = true;
    });
    try {
      final response = await _call('quoteStoreExternalDelivery', {
        'deliveryLat': point.lat,
        'deliveryLng': point.lng,
        'goodsAmount': 250,
        'serviceType': sallaCourierServiceImmediate,
        'scheduledFor': '',
        'recipientPhone': '',
        'note': '',
      });
      final quote = StoreExternalDeliveryQuote.fromMap(
        storeExternalObject(response['quote']),
      );
      if (quote.fingerprint.isEmpty) {
        throw StateError('Immediate fare quote fingerprint missing.');
      }
      if (!mounted ||
          generation != _precisePointFareGeneration ||
          !_samePrecisePoint(_selectedDeliveryPoint, point)) {
        return;
      }
      setState(() {
        _precisePointImmediateQuote = quote;
        _precisePointFareLoading = false;
      });
    } catch (_) {
      if (!mounted ||
          generation != _precisePointFareGeneration ||
          !_samePrecisePoint(_selectedDeliveryPoint, point)) {
        return;
      }
      setState(() => _precisePointFareLoading = false);
    }
  }

  Future<void> _chooseDestination() async {
    if (_pendingIntent != null || _busy) return;
    final revision = _destinationRevision;
    final ownerUid = sallaIdentity.uid;
    bool stillEditable() =>
        mounted &&
        !_busy &&
        _pendingIntent == null &&
        revision == _destinationRevision &&
        ownerUid == sallaIdentity.uid;
    FocusManager.instance.primaryFocus?.unfocus();
    final choice = await showSallaLifecycleSafeModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFC),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'كيف تريد تحديد موقع التسليم؟',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'لن يُنشأ الطلب قبل عرض الكروة والموقع عليك للمراجعة.',
                  style: TextStyle(
                    color: mutedText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.search_rounded),
                  ),
                  title: const Text('اختيار اسم منطقة معتمدة'),
                  subtitle: const Text('يعتمد مركز المنطقة المعتمد للتسعير'),
                  onTap: () => Navigator.pop(sheetContext, 'area'),
                ),
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.map_outlined)),
                  title: const Text('تحديد نقطة دقيقة على الخريطة'),
                  subtitle: const Text('للموقع المرسل أو باب المستلم بالضبط'),
                  onTap: () => Navigator.pop(sheetContext, 'map'),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.my_location_rounded),
                  ),
                  title: const Text('استخدام موقعي الحالي'),
                  subtitle: const Text('يمكنك مراجعته وتحريكه قبل الاعتماد'),
                  onTap: () => Navigator.pop(sheetContext, 'current'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!stillEditable() || choice == null) return;
    if (choice == 'area') {
      await _chooseArea();
      return;
    }
    SallaGeoPoint? initial = _selectedDeliveryPoint;
    if (choice == 'current') {
      setState(() {
        _busy = true;
        _error = '';
      });
      try {
        initial = await _storeExternalCurrentLocation();
      } catch (error) {
        if (mounted) {
          setState(() {
            _error = error is StateError
                ? error.message.toString()
                : 'تعذر تحديد موقعك الحالي.';
          });
        }
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!stillEditable()) return;
    final selected = await Navigator.of(context).push<SallaGeoPoint>(
      MaterialPageRoute(
        builder: (_) =>
            _StoreExternalDeliveryMapPickerPage(initialPoint: initial),
      ),
    );
    if (selected == null || !stillEditable()) return;
    setState(() {
      _selectedArea = null;
      if (!_samePrecisePoint(_selectedDeliveryPoint, selected)) {
        _selectedMapLabelArea = _nearestMapLabelArea(selected);
        _destinationRevision += 1;
      }
      _selectedDeliveryPoint = selected;
      _error = '';
      _draftValidationMessage = '';
    });
    unawaited(_refreshPrecisePointImmediateFare(selected));
  }

  void _selectSchedule(String serviceType) {
    if (_pendingIntent != null || _busy) return;
    final configuration = _configuration;
    if (configuration == null) return;
    final now = DateTime.now();
    DateTime? scheduledFor;
    if (serviceType == sallaCourierServiceFlexibleSixHours) {
      scheduledFor = now.toUtc().add(const Duration(hours: 6));
    } else if (serviceType == sallaCourierServiceNextDayTwelveHours) {
      scheduledFor = sallaNextBaghdadCourierWindow(
        now: now,
        opensAtMinute: configuration.serviceOpensAtMinute,
      ).deliveryEndsAt;
    } else if (serviceType != sallaCourierServiceImmediate) {
      return;
    }
    setState(() {
      _scheduleType = serviceType;
      _scheduledFor = scheduledFor;
      _error = '';
      _draftValidationMessage = '';
    });
  }

  Future<void> _revealRequiredField(
    GlobalKey sectionKey, {
    FocusNode? focusNode,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final sectionContext = sectionKey.currentContext;
    if (sectionContext != null) {
      await Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    }
    if (mounted && focusNode != null) focusNode.requestFocus();
  }

  void _showDraftMessage(String message) {
    if (!mounted) return;
    setState(() => _draftValidationMessage = message);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearDraftValidationMessage() {
    if (!mounted || _draftValidationMessage.isEmpty) return;
    setState(() => _draftValidationMessage = '');
  }

  Future<Map<String, dynamic>?> _validatedDraft() async {
    final configuration = _configuration;
    final area = _selectedArea;
    final deliveryPoint = _selectedDeliveryPoint;
    if (configuration?.requiresDeliveryPin == true && deliveryPoint == null) {
      _showDraftMessage(
        'حدد موقع التسليم الدقيق على الخريطة لحساب أجرة الاشتراك.',
      );
      await _revealRequiredField(_destinationSectionKey);
      return null;
    }
    final goodsText = _goodsController.text.trim();
    final goodsAmount = goodsText.isEmpty
        ? 0
        : parseStoreAmountInput(goodsText);
    if (goodsAmount == null ||
        goodsAmount < 0 ||
        goodsAmount > 100000000 ||
        goodsAmount % 250 != 0) {
      const message =
          'صحح حقل «مبلغ البضاعة»: أدخل صفراً أو مبلغاً من مضاعفات 250 د.ع لا يتجاوز 100,000,000.';
      _showDraftMessage(message);
      await _revealRequiredField(_goodsSectionKey, focusNode: _goodsFocusNode);
      return null;
    }
    if ((area == null) == (deliveryPoint == null)) {
      const message =
          'املأ حقل «موقع التسليم» باختيار منطقة أو تحديد دبوس على الخريطة.';
      _showDraftMessage(message);
      await _revealRequiredField(_destinationSectionKey);
      return null;
    }
    if (deliveryPoint != null &&
        (_selectedMapLabelArea == null ||
            !(configuration?.areas.any(
                  (area) =>
                      area.id == _selectedMapLabelArea!.id &&
                      area.nameAr == _selectedMapLabelArea!.nameAr,
                ) ??
                false))) {
      _showDraftMessage(
        'أكد اسم منطقة التسليم للدبوس المحدد قبل مراجعة الطلب.',
      );
      await _revealRequiredField(_destinationSectionKey);
      return null;
    }
    if (_scheduled) {
      final scheduledFor = _scheduledFor;
      final now = DateTime.now();
      if (scheduledFor == null || !scheduledFor.isAfter(now)) {
        const message = 'أعد اختيار نافذة التوصيل المجدول.';
        _showDraftMessage(message);
        await _revealRequiredField(_scheduleSectionKey);
        return null;
      }
    }
    if (configuration == null) {
      _showDraftMessage(
        'تعذر تحميل إعدادات التوصيل. حدّث الصفحة وحاول مجدداً.',
      );
      return null;
    }
    if (!configuration.enabled) {
      _showDraftMessage(_availabilityMessage(configuration));
      return null;
    }
    _clearDraftValidationMessage();
    return <String, dynamic>{
      if (area != null) 'areaId': area.id,
      if (deliveryPoint != null) 'deliveryLat': deliveryPoint.lat,
      if (deliveryPoint != null) 'deliveryLng': deliveryPoint.lng,
      if (deliveryPoint != null)
        'deliveryLabelAreaId': _selectedMapLabelArea!.id,
      'goodsAmount': goodsAmount,
      'serviceType': _scheduleType,
      'scheduledFor': _scheduled
          ? _scheduledFor!.toUtc().toIso8601String()
          : '',
      'recipientPhone': normalizeStoreInputDigits(_phoneController.text).trim(),
      'note': _noteController.text.trim(),
    };
  }

  Future<bool> _confirmQuote(StoreExternalDeliveryQuote quote) async {
    return await showSallaLifecycleSafeDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('مراجعة طلب التوصيل'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _reviewLine('المنطقة', quote.areaName),
                  if (quote.distanceKm > 0)
                    _reviewLine(
                      'الإزاحة من المتجر',
                      '${quote.distanceKm.toStringAsFixed(1)} كم',
                    ),
                  _reviewLine(
                    'الخدمة',
                    storeExternalServiceTypeLabel(quote.serviceType),
                  ),
                  if (quote.scheduledDeliveryAt != null)
                    _reviewLine(
                      'ساعة التوصيل',
                      storeExternalScheduledClockLabel(
                        context,
                        quote.scheduledDeliveryAt!,
                      ),
                    ),
                  const Divider(height: 24),
                  _reviewLine('مبلغ البضاعة', formatIqd(quote.goodsAmount)),
                  _reviewLine('الكروة', formatIqd(quote.deliveryFee)),
                  _reviewLine('رسم الخدمة', formatIqd(quote.serviceFee)),
                  _reviewLine(
                    'الإجمالي المطلوب من المستلم',
                    formatIqd(quote.customerTotalToCollect),
                    important: true,
                  ),
                  if (quote.deliveryLat != null &&
                      quote.deliveryLng != null) ...[
                    const SizedBox(height: 10),
                    _StoreExternalDestinationPreview(
                      latitude: quote.deliveryLat!,
                      longitude: quote.deliveryLng!,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    quote.goodsAmount == 0
                        ? 'لا يوجد مبلغ بضاعة يُدفع للمتجر؛ يُحصّل من المستلم الكروة ورسم الخدمة إن وجد فقط.'
                        : 'يدفع السائق مبلغ البضاعة للمتجر مباشرة، ويحتفظ بصافي كروته. لا يوجد راتب آجل.',
                    style: const TextStyle(
                      color: mutedText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('تعديل'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('إنشاء الطلب'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _reviewLine(String label, String value, {bool important = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: important ? appColor : darkText,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _quoteAndCreate() async {
    if (_busy || _pendingIntent != null) return;
    final draft = await _validatedDraft();
    if (draft == null) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    var quoteConfirmed = false;
    var createStarted = false;
    try {
      final response = await _call('quoteStoreExternalDelivery', draft);
      final quote = StoreExternalDeliveryQuote.fromMap(
        storeExternalObject(response['quote']),
      );
      if (quote.fingerprint.isEmpty) {
        throw StateError('Quote fingerprint missing.');
      }
      if (!mounted || !await _confirmQuote(quote)) return;
      quoteConfirmed = true;
      final requestId = _newStoreExternalRequestId('create');
      final payload = <String, dynamic>{
        ...draft,
        'expectedQuoteFingerprint': quote.fingerprint,
        'requestId': requestId,
      };
      final intent = StoreExternalDeliveryRetryIntent(
        requestId: requestId,
        payload: payload,
      );
      await _saveIntent(intent);
      if (!mounted) return;
      setState(() => _pendingIntent = intent);
      createStarted = true;
      await _sendCreateIntent(intent);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = createStarted || _pendingIntent != null
              ? _storeExternalErrorMessage(error)
              : quoteConfirmed
              ? 'لم يُنشأ أي طلب. تعذر حفظ محاولة الطلب على الجهاز؛ تحقق من مساحة التخزين ثم أعد المراجعة.'
              : _storeExternalReviewErrorMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCreateIntent(
    StoreExternalDeliveryRetryIntent intent,
  ) async {
    if (mounted) setState(() => _sendingCreate = true);
    try {
      final response = await _call(
        'createStoreExternalDelivery',
        intent.payload,
      );
      final orderId = response['orderId']?.toString() ?? intent.requestId;
      final publicOrder = StoreOrder.fromFirebase(
        orderId,
        storeExternalObject(response['order']),
      );
      await _clearIntent();
      if (!mounted) return;
      setState(() => _pendingIntent = null);
      StoreOrder createdOrder = publicOrder;
      try {
        createdOrder = await _readCreatedOrder(orderId);
      } catch (_) {
        // The callable response already confirmed creation. Realtime will
        // replace this minimal public snapshot with the canonical store view.
      }
      if (mounted) Navigator.pop(context, createdOrder);
    } catch (error) {
      if (!_storeExternalOutcomeMayBeUnknown(error)) {
        await _clearIntent();
        if (mounted) setState(() => _pendingIntent = null);
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _sendingCreate = false);
    }
  }

  Future<StoreOrder> _readCreatedOrder(String orderId) async {
    final data = await readStorePublicOrder(orderId);
    if (data == null ||
        data['orderSource']?.toString() != 'store_external' ||
        data['storeId']?.toString() != storeId) {
      throw StateError('Created external order snapshot missing.');
    }
    return StoreOrder.fromFirebase(orderId, data);
  }

  Future<void> _diagnosePendingIntent() async {
    final intent = _pendingIntent;
    if (intent == null || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final savedOrder = await readStorePublicOrder(intent.requestId);
      if (savedOrder != null) {
        final order = await _readCreatedOrder(intent.requestId);
        await _clearIntent();
        if (!mounted) return;
        setState(() => _pendingIntent = null);
        Navigator.pop(context, order);
        return;
      }
      final diagnosed = intent.markDiagnosedAbsent();
      await _saveIntent(diagnosed);
      if (!mounted) return;
      setState(() {
        _pendingIntent = diagnosed;
        _error =
            'لم يظهر الطلب في القراءة الموثوقة. يمكنك الآن إعادة المحاولة بالمعرّف والحمولة نفسيهما فقط.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _storeExternalErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryDiagnosedIntent() async {
    final intent = _pendingIntent;
    if (intent == null || !intent.diagnosedAbsent || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await _sendCreateIntent(intent);
    } catch (error) {
      if (mounted) setState(() => _error = _storeExternalErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _minuteOfDayLabel(int minuteOfDay) {
    final safe = minuteOfDay.clamp(0, 1439).toInt();
    final hour = safe ~/ 60;
    final minute = safe % 60;
    final suffix = hour < 12 ? 'ص' : 'م';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return minute == 0
        ? '$displayHour $suffix'
        : '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFF929C9F), width: 1.2),
    );
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: mutedText, size: 22),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      disabledBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFFD5DDDC)),
      ),
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: appColor, width: 2),
      ),
      errorMaxLines: 3,
      counterText: '',
    );
  }

  Widget _simpleCard({
    Key? key,
    required Widget child,
    Color color = Colors.white,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _serviceSelector(bool editable) {
    return Column(
      key: _scheduleSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          key: const ValueKey('store_external_service_selector'),
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('فوري'),
              icon: Icon(Icons.bolt_rounded),
            ),
            ButtonSegment(
              value: true,
              label: Text('مجدول'),
              icon: Icon(Icons.schedule_rounded),
            ),
          ],
          selected: {_scheduled},
          onSelectionChanged: editable
              ? (selection) => _selectSchedule(
                  selection.single
                      ? sallaCourierServiceFlexibleSixHours
                      : sallaCourierServiceImmediate,
                )
              : null,
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: appColor,
            selectedForegroundColor: Colors.white,
            selectedBackgroundColor: appColor,
            backgroundColor: Colors.white,
          ),
        ),
        if (_scheduled) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('store_external_schedule_$_scheduleType'),
            initialValue: _scheduleType,
            isExpanded: true,
            decoration: _fieldDecoration(
              'موعد التوصيل',
              Icons.schedule_outlined,
            ),
            items: const [
              DropdownMenuItem(
                value: sallaCourierServiceFlexibleSixHours,
                child: Text('خلال 6 ساعات'),
              ),
              DropdownMenuItem(
                value: sallaCourierServiceNextDayTwelveHours,
                child: Text('اليوم التالي • خلال 12 ساعة'),
              ),
            ],
            onChanged: editable
                ? (value) {
                    if (value != null) _selectSchedule(value);
                  }
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            _scheduleType == sallaCourierServiceFlexibleSixHours
                ? 'يبدأ البحث الآن، والتوصيل خلال 6 ساعات.'
                : 'يبدأ البحث غداً عند ${_minuteOfDayLabel(_configuration?.serviceOpensAtMinute ?? 8 * 60)}، والتوصيل خلال 12 ساعة.',
            style: const TextStyle(color: mutedText, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _orderEstimate() {
    // القائمة تعرض أجرة الخادم. رسم الخدمة والإجمالي الملزم في المراجعة فقط.
    final int? fare =
        _selectedArea != null && _configuration?.requiresDeliveryPin != true
        ? (_scheduled
              ? _selectedArea!.scheduledFee
              : _selectedArea!.immediateFee)
        : _selectedDeliveryPoint != null && !_scheduled
        ? _precisePointImmediateQuote?.deliveryFee
        : null;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _goodsController,
      builder: (context, value, _) {
        final goods = parseStoreAmountInput(value.text) ?? 0;
        return _simpleCard(
          key: const ValueKey('store_external_order_summary'),
          color: const Color(0xFFEAF2F1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ملخص الطلب',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Divider(height: 12),
              _reviewLine('سعر البضاعة', formatIqd(goods)),
              _reviewLine(
                'كلفة التوصيل',
                fare == null ? 'تظهر في المراجعة' : formatIqd(fare),
              ),
              const Divider(height: 12),
              _reviewLine(
                'المجموع المبدئي',
                fare == null ? '—' : formatIqd(goods + fare),
              ),
              const SizedBox(height: 5),
              const Text(
                'قبل رسم الخدمة إن وجد. الكروة والإجمالي النهائيان في المراجعة.',
                style: TextStyle(color: mutedText, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final configuration = _configuration;
    final pending = _pendingIntent;
    final selectedArea = _selectedArea;
    final selectedDeliveryPoint = _selectedDeliveryPoint;
    final editable = pending == null && !_busy && !_loading;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FractionallySizedBox(
        heightFactor: 0.96,
        child: ColoredBox(
          color: const Color(0xFFF5F7F7),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    key: const ValueKey('store_external_composer_scroll'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Container(
                        key: const ValueKey<String>(
                          'store_external_composer_header',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF235F5D),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'رجوع',
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'طلب جديد',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'اطلب مندوبك',
                                    style: TextStyle(
                                      color: Color(0xFFD4E7E5),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _serviceSelector(editable),
                      if (_loading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      if (configuration != null && !configuration.enabled)
                        _availabilityCard(configuration),
                      if (configuration != null &&
                          configuration.subscriptionStatus != 'none')
                        _subscriptionStatusCard(configuration),
                      if (_sendingCreate)
                        _sendingCard()
                      else if (pending != null)
                        _pendingCard(pending),
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(_error, style: const TextStyle(color: Colors.red)),
                        if (configuration == null && !_loading)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                                _error = '';
                              });
                              unawaited(_load());
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة تحميل المناطق'),
                          ),
                      ],
                      const SizedBox(height: 10),
                      _simpleCard(
                        key: const ValueKey('store_external_customer_fields'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'أدخل معلومات الزبون ليصل المندوب بسهولة',
                              style: TextStyle(color: mutedText, fontSize: 15),
                            ),
                            const Divider(height: 16),
                            KeyedSubtree(
                              key: _destinationSectionKey,
                              child: Semantics(
                                button: true,
                                child: InkWell(
                                  key: const ValueKey(
                                    'store_external_destination_field',
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: editable
                                      ? selectedDeliveryPoint != null
                                            ? _chooseMapLabel
                                            : _chooseArea
                                      : null,
                                  child: InputDecorator(
                                    decoration:
                                        _fieldDecoration(
                                          'منطقة التسليم (إلزامي)',
                                          Icons.location_city_outlined,
                                        ).copyWith(
                                          suffixIcon: _refreshingAreas
                                              ? const Padding(
                                                  padding: EdgeInsets.all(14),
                                                  child: SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons
                                                      .keyboard_arrow_down_rounded,
                                                ),
                                          errorText:
                                              _draftValidationMessage.contains(
                                                'موقع التسليم',
                                              )
                                              ? 'اختر منطقة التسليم أو حدد موقعاً على الخريطة'
                                              : null,
                                        ),
                                    child: Text(
                                      selectedArea?.nameAr ??
                                          (selectedDeliveryPoint != null
                                              ? _selectedMapLabelArea?.nameAr ??
                                                    'اختر اسم المنطقة'
                                              : 'اختر المنطقة'),
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                key: const ValueKey(
                                  'store_external_map_alternative',
                                ),
                                onPressed: editable ? _chooseDestination : null,
                                icon: const Icon(Icons.map_outlined, size: 19),
                                label: Text(
                                  selectedDeliveryPoint == null
                                      ? configuration?.requiresDeliveryPin ==
                                                true
                                            ? 'حدد الموقع على الخريطة (إلزامي للاشتراك)'
                                            : 'أو حدد الموقع على الخريطة'
                                      : 'تعديل الموقع على الخريطة',
                                ),
                              ),
                            ),
                            if (selectedDeliveryPoint != null) ...[
                              Text(
                                key: const ValueKey(
                                  'store_external_map_area_label',
                                ),
                                _selectedMapLabelArea == null
                                    ? 'لم نجد نقطة مرجعية قريبة لاقتراح اسم؛ اختر المنطقة يدوياً. التسليم يبقى إلى الدبوس نفسه.'
                                    : 'اختير تلقائياً أقرب اسم حسب النقاط المرجعية؛ يمكنك تغييره. التسليم والكروة حسب الدبوس الدقيق.',
                                style: const TextStyle(
                                  color: appColor,
                                  fontSize: 13,
                                ),
                              ),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton.icon(
                                  key: const ValueKey(
                                    'store_external_change_pin_area_label',
                                  ),
                                  onPressed: editable ? _chooseMapLabel : null,
                                  icon: const Icon(
                                    Icons.edit_location_alt_outlined,
                                  ),
                                  label: const Text('تغيير اسم المنطقة'),
                                ),
                              ),
                              Text(
                                '${selectedDeliveryPoint.lat.toStringAsFixed(5)}, ${selectedDeliveryPoint.lng.toStringAsFixed(5)}',
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: mutedText,
                                  fontSize: 12,
                                ),
                              ),
                              if (!_scheduled)
                                Text(
                                  key: const ValueKey(
                                    'store_external_precise_point_immediate_fare',
                                  ),
                                  _precisePointFareLoading
                                      ? 'جارٍ حساب الكروة الفورية...'
                                      : _precisePointImmediateQuote != null
                                      ? 'الكروة الفورية: ${formatIqd(_precisePointImmediateQuote!.deliveryFee)}'
                                      : 'ستظهر الكروة الفورية في المراجعة النهائية.',
                                  style: const TextStyle(
                                    color: appColor,
                                    fontSize: 12,
                                  ),
                                ),
                              const SizedBox(height: 14),
                            ],
                            TextField(
                              key: const ValueKey('store_external_phone_field'),
                              controller: _phoneController,
                              textDirection: TextDirection.ltr,
                              inputFormatters: const [
                                StorePhoneInputFormatter(),
                              ],
                              enabled: editable,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              maxLength: 40,
                              decoration: _fieldDecoration(
                                'هاتف المستلم (اختياري)',
                                Icons.phone_outlined,
                              ),
                            ),
                            const SizedBox(height: 12),
                            KeyedSubtree(
                              key: _goodsSectionKey,
                              child: TextField(
                                key: const ValueKey(
                                  'store_external_goods_field',
                                ),
                                controller: _goodsController,
                                textDirection: TextDirection.ltr,
                                focusNode: _goodsFocusNode,
                                enabled: editable,
                                onChanged: (_) =>
                                    _clearDraftValidationMessage(),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  const StoreAmountInputFormatter(),
                                ],
                                decoration:
                                    _fieldDecoration(
                                      'سعر الطلب (اختياري)',
                                      Icons.payments_outlined,
                                    ).copyWith(
                                      helperText:
                                          'اتركه فارغاً إذا لا يوجد مبلغ للبضاعة',
                                      errorText:
                                          _draftValidationMessage.contains(
                                            'مبلغ البضاعة',
                                          )
                                          ? _draftValidationMessage
                                          : null,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const ValueKey('store_external_note_field'),
                              controller: _noteController,
                              enabled: editable,
                              maxLength: 1000,
                              minLines: 1,
                              maxLines: 3,
                              decoration: _fieldDecoration(
                                'ملاحظات الوصول (اختياري)',
                                Icons.notes_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _orderEstimate(),
                      const SizedBox(height: 10),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      key: const ValueKey<String>(
                        'store_external_review_panel',
                      ),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_draftValidationMessage.isNotEmpty) ...[
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              key: const ValueKey<String>(
                                'store_external_review_validation_message',
                              ),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _draftValidationMessage,
                                style: const TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        FilledButton.icon(
                          key: const ValueKey<String>('store_external_submit'),
                          onPressed:
                              !_loading &&
                                  !_busy &&
                                  pending == null &&
                                  configuration != null
                              ? _quoteAndCreate
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: orangeColor,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.receipt_long_rounded),
                          label: Text(
                            _sendingCreate
                                ? 'جارٍ إرسال الطلب...'
                                : 'راجع الكروة والطلب',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _sendingCreate
                              ? 'انتظر التأكيد، لا حاجة لإرسال الطلب مرة أخرى'
                              : 'لن يُنشأ الطلب قبل أن تراجع الكروة والإجمالي',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: mutedText,
                            fontSize: 12,
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
    );
  }

  Widget _subscriptionStatusCard(
    StoreExternalDeliveryConfiguration configuration,
  ) {
    String dateLabel(DateTime? value) {
      if (value == null) return '—';
      final baghdad = value.toUtc().add(const Duration(hours: 3));
      return '${baghdad.year}/${baghdad.month.toString().padLeft(2, '0')}/${baghdad.day.toString().padLeft(2, '0')}';
    }

    final status = switch (configuration.subscriptionStatus) {
      'active' => 'فعّال',
      'scheduled' => 'لم يبدأ بعد',
      _ => 'منتهٍ',
    };
    return _simpleCard(
      key: const ValueKey('store_delivery_subscription_status'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'اشتراك التوصيل: $status',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text('البداية: ${dateLabel(configuration.subscriptionStartsAt)}'),
          Text('النهاية: ${dateLabel(configuration.subscriptionEndsAt)}'),
        ],
      ),
    );
  }

  Widget _availabilityCard(StoreExternalDeliveryConfiguration configuration) {
    final message = _availabilityMessage(configuration);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  String _availabilityMessage(
    StoreExternalDeliveryConfiguration configuration,
  ) {
    return configuration.approvalRequired || !configuration.adminApproved
        ? 'طلب مندوبك بانتظار اعتماد الإدارة لهذا المتجر.'
        : !configuration.globalEnabled
        ? 'الإطلاق العام مغلق حالياً. لا يمكن إنشاء طلب فعلي حتى تفتحه الإدارة بعد البوابات والنشر الخامل.'
        : !configuration.storeEnabled
        ? 'الإدارة عطلت التوصيل الخارجي لهذا المتجر.'
        : configuration.serviceAvailabilityMessage.isNotEmpty
        ? configuration.serviceAvailabilityMessage
        : 'جدول المتجر غير جاهز أو تغيرت بياناته.';
  }

  Widget _sendingCard() {
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('store_external_create_in_flight'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: appColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'جارٍ إرسال الطلب، ننتظر تأكيد الإنشاء.',
          style: TextStyle(fontWeight: FontWeight.w700, color: appColor),
        ),
      ),
    );
  }

  Widget _pendingCard(StoreExternalDeliveryRetryIntent intent) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'هناك نتيجة إنشاء غير مؤكدة',
            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red),
          ),
          const SizedBox(height: 5),
          const Text(
            'المدخلات مقفلة حتى تشخيص المحاولة المحفوظة. لن ننشئ معرّفاً أو حمولة جديدة.',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _diagnosePendingIntent,
            icon: const Icon(Icons.manage_search_rounded),
            label: const Text('تشخيص حالة المحاولة'),
          ),
          if (intent.diagnosedAbsent) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _retryDiagnosedIntent,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة نفسها'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<bool> cancelStoreExternalDeliveryFromStore(
  BuildContext context,
  StoreOrder order,
) async {
  if (!order.canCancelStoreExternalDelivery) return false;
  final environment = Firebase.app().options.projectId.trim();
  Future<void> clearIntent() => SallaAuthService.removeLocalRetryIntent(
    role: SallaUserRole.store,
    environment: environment,
    ownerUid: sallaIdentity.uid,
    namespace: _storeExternalCancelRetryNamespace,
    intentId: order.databaseKey,
  );
  final stored = await SallaAuthService.loadLocalRetryIntents(
    role: SallaUserRole.store,
    environment: environment,
    ownerUid: sallaIdentity.uid,
    namespace: _storeExternalCancelRetryNamespace,
  );
  StoreExternalDeliveryRetryIntent? pending;
  final rawPending = stored[order.databaseKey];
  if (rawPending != null) {
    try {
      pending = StoreExternalDeliveryRetryIntent.fromLocal(rawPending);
    } on FormatException {
      await clearIntent();
    }
  }

  if (pending != null) {
    try {
      final current =
          await readStorePublicOrder(order.databaseKey) ?? <String, dynamic>{};
      if (current['status']?.toString() == 'cancelled') {
        await clearIntent();
        return true;
      }
      if (!context.mounted) return false;
      final retry = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('محاولة إلغاء محفوظة'),
          content: const Text(
            'لم يظهر الإلغاء في القراءة الموثوقة. هل تريد إعادة المحاولة بالمعرّف والحمولة نفسيهما؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ليس الآن'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إعادة المحاولة نفسها'),
            ),
          ],
        ),
      );
      if (retry != true) return false;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_storeExternalErrorMessage(error))),
        );
      }
      return false;
    }
  } else {
    if (!context.mounted) return false;
    final reason = await showStoreExternalCancellationReasonDialog(
      context,
      orderNumber: order.number,
    );
    if (reason == null || reason.isEmpty) return false;
    final requestId = _newStoreExternalRequestId('cancel');
    final payload = <String, dynamic>{
      'orderId': order.databaseKey,
      'requestId': requestId,
      'reason': reason,
    };
    pending = StoreExternalDeliveryRetryIntent(
      requestId: requestId,
      payload: payload,
    );
    await SallaAuthService.saveLocalRetryIntent(
      role: SallaUserRole.store,
      environment: environment,
      ownerUid: sallaIdentity.uid,
      namespace: _storeExternalCancelRetryNamespace,
      intentId: order.databaseKey,
      payload: pending.toLocal(),
    );
  }

  try {
    final callable = _storeExternalFunctions.httpsCallable(
      'cancelStoreExternalDelivery',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
    );
    await callable
        .call<Map<String, dynamic>>(pending.payload)
        .timeout(const Duration(seconds: 40));
    await clearIntent();
    return true;
  } catch (error) {
    if (!_storeExternalOutcomeMayBeUnknown(error)) await clearIntent();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_storeExternalErrorMessage(error))),
      );
    }
    return false;
  }
}
