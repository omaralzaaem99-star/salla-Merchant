part of sala_store;

typedef StoreCourierReportLoader =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

DateTime storeReportBaghdadDate(DateTime instant) {
  final shifted = instant.toUtc().add(const Duration(hours: 3));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

String storeReportDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

String storeReportTime(DateTime instant) {
  final shifted = instant.toUtc().add(const Duration(hours: 3));
  return '${shifted.hour.toString().padLeft(2, '0')}:'
      '${shifted.minute.toString().padLeft(2, '0')}';
}

String storeReportStatus(StoreOrder order) => order.isCancelled
    ? 'ملغى'
    : order.isDelivered
    ? 'مكتمل'
    : 'جارٍ';

String storeReportArea(StoreOrder order) {
  for (final label in [
    order.deliveryAreaName,
    order.deliveryZoneName,
    order.address,
  ]) {
    if (label.trim().isNotEmpty && label.trim() != '-') return label.trim();
  }
  return 'المنطقة غير مسجلة';
}

String storeReportSupportText(StoreOrder order) => [
  'طلب مندوبك — رقم الطلب: ${order.number}',
  'معرّف الطلب: ${order.databaseKey}',
  'التاريخ: ${storeReportDayKey(storeReportBaghdadDate(order.createdAt))} '
      '${storeReportTime(order.createdAt)} بتوقيت بغداد',
  'الحالة: ${storeReportStatus(order)}',
  'المنطقة: ${storeReportArea(order)}',
  '${order.responsibleDriverLabel}: '
      '${order.responsibleDriverName.isEmpty ? 'غير مسجل' : order.responsibleDriverName}',
  if (order.responsibleDriverId.isNotEmpty)
    'معرّف السائق: ${order.responsibleDriverId}',
  'مبلغ الطلب: ${formatIqd(order.storeGrossAmount)}',
].join('\n');

class StoreCourierReportTotals {
  StoreCourierReportTotals(Iterable<StoreOrder> orders) {
    for (final order in orders) {
      count++;
      if (order.isCancelled) {
        cancelled++;
      } else if (order.isDelivered) {
        completed++;
        goods += order.storeGrossAmount;
      } else {
        active++;
      }
    }
  }
  int count = 0;
  int completed = 0;
  int cancelled = 0;
  int active = 0;
  int goods = 0;
}

Future<Map<String, dynamic>> loadStoreCourierReportPage(
  Map<String, dynamic> request,
) async {
  final expectedId = storeId;
  final expectedUid = sallaIdentity.uid;
  if (request['storeId'] != expectedId) {
    throw StateError('تغير حساب المتجر. افتح السجل مجدداً.');
  }
  final response = await FirebaseFunctions.instanceFor(region: 'europe-west1')
      .httpsCallable(
        'getStoreOrderHistoryPage',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      )
      .call<dynamic>(request)
      .timeout(const Duration(seconds: 30));
  if (storeId != expectedId || sallaIdentity.uid != expectedUid) {
    throw StateError('تغير حساب المتجر أثناء قراءة السجل.');
  }
  if (response.data is! Map) {
    throw const FormatException('استجابة السجل غير صالحة.');
  }
  return (response.data as Map).map(
    (key, value) => MapEntry(key.toString(), value),
  );
}

/// A view inside the existing orders page, using its authenticated history API.
class StoreCourierReport extends StatefulWidget {
  const StoreCourierReport({
    super.key,
    required this.expectedStoreId,
    required this.loadPage,
    required this.onOpenOrder,
    this.now,
  });
  final String expectedStoreId;
  final StoreCourierReportLoader loadPage;
  final ValueChanged<StoreOrder> onOpenOrder;
  final DateTime? now;

  @override
  State<StoreCourierReport> createState() => _StoreCourierReportState();
}

class _StoreCourierReportState extends State<StoreCourierReport>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _pin = TextEditingController();
  String _session = '';
  String _accessError = '';
  bool _checkingAccess = true;
  bool _locked = true;
  bool _unlocking = false;
  bool _enabled = false;
  bool _editingProtection = false;
  int? _accessRevision;
  Timer? _accessTimer;
  Timer? _expiryTimer;
  final _orders = <String, StoreOrder>{};
  final _seenCursors = <String>{};
  late DateTime _from;
  late DateTime _to;
  Map<String, dynamic>? _cursor;
  String _number = '';
  String _status = 'الكل';
  String _error = '';
  bool _loading = false;
  bool _complete = false;
  int _generation = 0;
  DateTime? _loadedAt;

  DateTime get _today => storeReportBaghdadDate(widget.now ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _from = _to = _today;
    unawaited(_checkAccess());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accessTimer?.cancel();
    _expiryTimer?.cancel();
    _revokeSession();
    _generation++;
    _search.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _revokeSession() {
    final token = _session;
    _session = '';
    if (token.isNotEmpty) {
      unawaited(
        widget
            .loadPage({
              'storeId': widget.expectedStoreId,
              'action': 'report_lock',
              'reportSession': token,
            })
            .catchError((_) => <String, dynamic>{}),
      );
    }
  }

  void _clearAccess() {
    _accessTimer?.cancel();
    _expiryTimer?.cancel();
    _generation++;
    _revokeSession();
    _orders.clear();
    _seenCursors.clear();
    _cursor = null;
    _complete = false;
    _loading = false;
    _loadedAt = null;
    _locked = true;
    _unlocking = false;
    _pin.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      setState(_clearAccess);
    } else if (!_editingProtection) {
      unawaited(_checkAccess());
    }
  }

  @override
  void didUpdateWidget(covariant StoreCourierReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedStoreId != widget.expectedStoreId) {
      _clearAccess();
      _editingProtection = false;
      _accessRevision = null;
      unawaited(_checkAccess());
    }
  }

  Future<void> _checkAccess({bool refresh = false}) async {
    final generation = _generation;
    if (!refresh)
      setState(() {
        _checkingAccess = true;
        _accessError = '';
      });
    try {
      final result = await widget.loadPage({
        'storeId': widget.expectedStoreId,
        'action': 'report_access_status',
      });
      if (!mounted || generation != _generation) return;
      if (result['enabled'] is! bool || result['revision'] is! int) {
        throw const FormatException('تعذر التحقق من قفل السجل.');
      }
      final enabled = result['enabled'] == true;
      final revision = result['revision'] as int;
      if (refresh && _accessRevision == revision && _enabled == enabled) return;
      setState(() {
        _clearAccess();
        _accessRevision = revision;
        _enabled = enabled;
        _locked = enabled;
        _checkingAccess = false;
      });
      _watchAccess();
      if (!enabled) await _load(reset: true);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _clearAccess();
        _checkingAccess = false;
        _accessError =
            'تعذر التحقق من حماية السجل. تحقق من الاتصال وأعد المحاولة.';
      });
    }
  }

  void _watchAccess() {
    _accessTimer?.cancel();
    _accessTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_loading && !_unlocking) unawaited(_checkAccess(refresh: true));
    });
  }

  void _editProtection() {
    setState(() {
      _clearAccess();
      _editingProtection = true;
    });
  }

  void _closeProtection() {
    setState(() {
      _clearAccess();
      _editingProtection = false;
    });
    unawaited(_checkAccess());
  }

  Widget _protectionButton() => TextButton.icon(
    onPressed: _unlocking ? null : _editProtection,
    icon: const Icon(Icons.admin_panel_settings_outlined),
    label: const Text('حماية السجل'),
  );

  Future<void> _unlock() async {
    if (_unlocking) return;
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _accessError = 'أدخل الرمز المكون من 6 أرقام.');
      return;
    }
    final generation = ++_generation;
    setState(() {
      _unlocking = true;
      _accessError = '';
    });
    try {
      final result = await widget.loadPage({
        'storeId': widget.expectedStoreId,
        'action': 'report_unlock',
        'reportPin': pin,
      });
      if (!mounted || generation != _generation) {
        final token = result['reportSession'];
        if (token is String && token.isNotEmpty) {
          unawaited(
            widget
                .loadPage({
                  'storeId': widget.expectedStoreId,
                  'action': 'report_lock',
                  'reportSession': token,
                })
                .catchError((_) => <String, dynamic>{}),
          );
        }
        return;
      }
      final enabled = result['enabled'] == true;
      final token = result['reportSession'];
      final expiry = result['expiresAt'];
      if (result['enabled'] is! bool ||
          token is! String ||
          enabled &&
              (token.isEmpty ||
                  expiry is! int ||
                  expiry <= DateTime.now().millisecondsSinceEpoch)) {
        throw const FormatException('استجابة فتح السجل غير صالحة.');
      }
      setState(() {
        _session = token;
        _enabled = enabled;
        _accessRevision = result['revision'] as int;
        _locked = false;
        _pin.clear();
      });
      if (enabled) {
        _expiryTimer = Timer(
          Duration(
            milliseconds:
                (expiry as int) - DateTime.now().millisecondsSinceEpoch,
          ),
          () {
            if (mounted) setState(_clearAccess);
          },
        );
      }
      _watchAccess();
      await _load(reset: true);
    } on FirebaseFunctionsException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _accessError = error.message ?? 'تعذر فتح السجل.');
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _accessError = 'تعذر فتح السجل. تحقق من الاتصال وأعد المحاولة.',
        );
      }
    } finally {
      if (mounted && (generation == _generation || !_locked)) {
        setState(() {
          _unlocking = false;
          _pin.clear();
        });
      }
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_locked || _checkingAccess) return;
    final generation = ++_generation;
    final from = storeReportDayKey(_from);
    final to = storeReportDayKey(_to);
    final number = _number;
    setState(() {
      _loading = true;
      _complete = false;
      _error = '';
      if (reset) {
        _orders.clear();
        _seenCursors.clear();
        _cursor = null;
        _loadedAt = null;
      }
    });
    try {
      while (mounted && generation == _generation) {
        final page = await widget.loadPage({
          'storeId': widget.expectedStoreId,
          'pageSize': 100,
          if (_session.isNotEmpty) 'reportSession': _session,
          if (number.isNotEmpty) 'orderNumber': number,
          if (number.isEmpty) ...{'fromDay': from, 'toDay': to},
          if (_cursor != null) 'cursor': _cursor,
        });
        if (!mounted || generation != _generation) return;
        final rows = page['orders'];
        if (rows is! List || page['hasMore'] is! bool) {
          throw const FormatException('بيانات السجل غير مكتملة.');
        }
        final parsed = <String, StoreOrder>{};
        for (final row in rows) {
          if (row is! Map) throw const FormatException('طلب غير صالح.');
          final data = row.map((key, value) => MapEntry(key.toString(), value));
          final key = data['key']?.toString().trim() ?? '';
          final instant = DateTime.tryParse(
            data['createdAt']?.toString() ?? '',
          );
          if (key.isEmpty ||
              instant == null ||
              data['storeId'] != widget.expectedStoreId ||
              data['orderSource'] != 'store_external') {
            throw const FormatException('بيانات الطلب لا تطابق سجل المتجر.');
          }
          final day = storeReportDayKey(storeReportBaghdadDate(instant));
          if (number.isEmpty &&
                  (day.compareTo(from) < 0 || day.compareTo(to) > 0) ||
              number.isNotEmpty && data['orderNumber'] != number) {
            throw const FormatException('الطلب خارج البحث المحدد.');
          }
          parsed[key] = StoreOrder.fromFirebase(key, data);
        }
        final more = page['hasMore'] == true;
        final rawCursor = page['nextCursor'];
        Map<String, dynamic>? next;
        if (more) {
          if (rawCursor is! Map || number.isNotEmpty) {
            throw const FormatException('تعذر إكمال صفحات السجل.');
          }
          next = rawCursor.map((key, value) => MapEntry(key.toString(), value));
          final cursorKey = '${next['createdAt']}|${next['key']}';
          if (next['createdAt'] == null ||
              next['key'] == null ||
              !_seenCursors.add(cursorKey)) {
            throw const FormatException('لم يتقدم تحميل السجل.');
          }
        }
        setState(() {
          _orders.addAll(parsed);
          _cursor = next;
          _complete = !more;
          if (!more) _loadedAt = DateTime.now();
        });
        if (!more) break;
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        if (error is FirebaseFunctionsException &&
            error.code == 'permission-denied') {
          setState(() {
            _clearAccess();
            _accessError = 'السجل مقفل. أدخل الرمز لعرضه.';
          });
          return;
        }
        setState(
          () => _error =
              'لم يكتمل تحميل السجل. الأعداد والمبالغ النهائية غير جاهزة. أعد المحاولة.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectDays(DateTime from, DateTime to) {
    setState(() {
      _from = from;
      _to = to;
      _number = '';
      _search.clear();
    });
    unawaited(_load(reset: true));
  }

  Future<void> _pickDays() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: _today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'اختر يوماً واحداً أو فترة حتى 31 يوماً',
      saveText: 'عرض السجل',
    );
    if (!mounted || picked == null) return;
    // UTC date-only arithmetic does not depend on the phone's DST setting.
    final length =
        DateTime.utc(picked.end.year, picked.end.month, picked.end.day)
            .difference(
              DateTime.utc(
                picked.start.year,
                picked.start.month,
                picked.start.day,
              ),
            )
            .inDays;
    if (length > 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر فترة لا تتجاوز 31 يوماً.')),
      );
      return;
    }
    _selectDays(picked.start, picked.end);
  }

  void _findOrder() {
    final number = _search.text.trim().toUpperCase();
    if (!RegExp(r'^EXT-[A-Z0-9]{8}$').hasMatch(number)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل رقم الطلب كاملاً، مثل EXT-A1B2C3D4.'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    _number = number;
    _status = 'الكل';
    unawaited(_load(reset: true));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم النسخ، يمكنك إرساله إلى الإدارة.')),
    );
  }

  Widget _panel(Widget child, {Color color = Colors.white}) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE0EAE7)),
    ),
    child: child,
  );

  Widget _metric(String label, String value) => SizedBox(
    width: 136,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: mutedText, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: darkText,
          ),
        ),
      ],
    ),
  );

  Widget _controls() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'سجل طلب مندوبك',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: appColor,
          ),
        ),
        const SizedBox(height: 5),
        _protectionButton(),
        if (_enabled)
          TextButton.icon(
            onPressed: () => setState(_clearAccess),
            icon: const Icon(Icons.lock_outline),
            label: const Text('قفل السجل الآن'),
          ),
        const Text(
          'كل طلب محفوظ برقمه ومنطقته وسائقه. اختر اليوم أو ابحث عن طلب سابق.',
          style: TextStyle(color: mutedText),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ActionChip(
              label: const Text('اليوم'),
              onPressed: () => _selectDays(_today, _today),
            ),
            ActionChip(
              label: const Text('أمس'),
              onPressed: () {
                final yesterday = DateTime(
                  _today.year,
                  _today.month,
                  _today.day - 1,
                );
                _selectDays(yesterday, yesterday);
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.date_range_outlined, size: 18),
              label: const Text('يوم أو فترة'),
              onPressed: _pickDays,
            ),
            ActionChip(
              avatar: const Icon(Icons.refresh, size: 18),
              label: const Text('تحديث'),
              onPressed: _loading ? null : () => _load(reset: true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('courier_report_search'),
          controller: _search,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _findOrder(),
          decoration: InputDecoration(
            labelText: 'رقم الطلب في جميع الأيام',
            hintText: 'EXT-A1B2C3D4',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            suffixIcon: IconButton(
              tooltip: 'بحث عن الطلب',
              onPressed: _findOrder,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _number.isNotEmpty
              ? 'نتيجة البحث عن $_number'
              : '${storeReportDayKey(_from)}  ←  ${storeReportDayKey(_to)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const Text(
          'حسب تاريخ إنشاء الطلب • بتوقيت بغداد',
          style: TextStyle(fontSize: 12, color: mutedText),
        ),
      ],
    ),
  );

  Widget _summary(StoreCourierReportTotals totals) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _complete ? 'ملخص الفترة' : 'جارٍ حساب ملخص الفترة',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        if (!_complete) ...[
          if (_loading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            'تم تحميل ${_orders.length} طلب. يظهر المجموع بعد اكتمال الفترة.',
          ),
        ] else ...[
          Wrap(
            spacing: 10,
            runSpacing: 14,
            children: [
              _metric('عدد الطلبات', '${totals.count}'),
              _metric('مكتملة', '${totals.completed}'),
              _metric('جارية', '${totals.active}'),
              _metric('ملغاة', '${totals.cancelled}'),
            ],
          ),
          const Divider(height: 28),
          const Text(
            'مبالغ الطلبات المكتملة فقط',
            style: TextStyle(fontWeight: FontWeight.w800, color: appColor),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 14,
            children: [_metric('قيمة الطلبات', formatIqd(totals.goods))],
          ),
          const SizedBox(height: 12),
          const Text(
            'المبالغ كما سُجلت في الطلب؛ لا تشمل الملغى والجاري ولا تعني تسوية مالية.',
            style: TextStyle(fontSize: 12, color: mutedText),
          ),
          if (_loadedAt != null)
            Text(
              'آخر تحديث ${storeReportTime(_loadedAt!)} — حدّث لمتابعة التغييرات.',
              style: const TextStyle(fontSize: 12, color: mutedText),
            ),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_error, style: TextStyle(color: Colors.red.shade700)),
          TextButton.icon(
            onPressed: _loading ? null : () => _load(reset: false),
            icon: const Icon(Icons.refresh),
            label: const Text('إكمال التحميل'),
          ),
        ],
      ],
    ),
    color: const Color(0xFFF0F8F5),
  );

  Widget _dayHeading(String day, List<StoreOrder> orders) {
    final totals = StoreCourierReportTotals(orders);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(
            _complete
                ? '${totals.count} طلب • ${totals.completed} مكتمل • ${totals.active} جارٍ • ${totals.cancelled} ملغى'
                : '${totals.count} طلب محمّل — لم يكتمل اليوم بعد',
          ),
          if (_complete)
            Text(
              'قيمة الطلبات المكتملة: ${formatIqd(totals.goods)}',
              style: const TextStyle(
                color: appColor,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _orderCard(StoreOrder order) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StoreOrderNumberLabel(
          number: order.number,
          onCopy: () => _copy(order.number),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 5,
          children: [
            Text(
              storeReportStatus(order),
              style: TextStyle(
                color: order.isCancelled ? Colors.red.shade700 : appColor,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              '${storeReportTime(order.createdAt)} • ${storeExternalServiceTypeLabel(order.storeExternalServiceType)}',
            ),
          ],
        ),
        const Divider(height: 24),
        Text(
          'المنطقة: ${storeReportArea(order)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '${order.responsibleDriverLabel}: ${order.responsibleDriverName.isEmpty ? (order.isDelivered ? 'غير مسجل في الطلب القديم' : 'لم يُعيّن بعد') : order.responsibleDriverName}',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [_metric('مبلغ الطلب', formatIqd(order.storeGrossAmount))],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            TextButton.icon(
              onPressed: () => _copy(storeReportSupportText(order)),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('نسخ للإدارة'),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_editingProtection) {
      return StoreReportProtectionSettings(
        key: ValueKey(widget.expectedStoreId),
        expectedStoreId: widget.expectedStoreId,
        call: widget.loadPage,
        onClose: _closeProtection,
      );
    }
    if (_checkingAccess || _locked) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _panel(
              Column(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 44,
                    color: appColor,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'سجل طلب مندوبك',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  if (_checkingAccess)
                    const LinearProgressIndicator()
                  else ...[
                    const Text('السجل محمي. أدخل الرمز لعرض الطلبات ومبالغها.'),
                    _protectionButton(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pin,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enabled: !_unlocking,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'رمز السجل',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _unlock(),
                    ),
                    if (_accessError.isNotEmpty)
                      Text(
                        _accessError,
                        style: const TextStyle(color: Colors.red),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _unlocking ? null : _unlock,
                      child: Text(_unlocking ? 'جارٍ التحقق…' : 'فتح السجل'),
                    ),
                    TextButton(
                      onPressed: _unlocking ? null : () => _checkAccess(),
                      child: const Text('تحديث حالة القفل'),
                    ),
                    const Text(
                      'نسيت الرمز؟ تواصل مع الإدارة لتغييره.',
                      style: TextStyle(color: mutedText),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    final orders = _orders.values.toList()
      ..sort((a, b) {
        final compared = b.createdAt.compareTo(a.createdAt);
        return compared != 0
            ? compared
            : b.databaseKey.compareTo(a.databaseKey);
      });
    final groups = <String, List<StoreOrder>>{};
    for (final order in orders) {
      (groups[storeReportDayKey(storeReportBaghdadDate(order.createdAt))] ??=
              [])
          .add(order);
    }
    final rows = <Object>[];
    for (final entry in groups.entries) {
      final visible = entry.value.where(
        (order) => _status == 'الكل' || storeReportStatus(order) == _status,
      );
      if (visible.isEmpty) continue;
      rows.add(entry.key);
      rows.addAll(visible);
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView.builder(
        key: const ValueKey('courier_report_list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: 3 + (rows.isEmpty ? 1 : rows.length),
        itemBuilder: (context, index) {
          if (index == 0) return _controls();
          if (index == 1) return _summary(StoreCourierReportTotals(orders));
          if (index == 2)
            return Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final status in ['الكل', 'مكتمل', 'جارٍ', 'ملغى'])
                  ChoiceChip(
                    label: Text(status),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            );
          if (rows.isEmpty)
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _complete
                    ? (_number.isNotEmpty
                          ? 'لا يوجد طلب بهذا الرقم في متجرك.'
                          : 'لا توجد طلبات في الفترة والحالة المحددتين.')
                    : 'جارٍ البحث في سجل الطلبات...',
                textAlign: TextAlign.center,
              ),
            );
          final row = rows[index - 3];
          return row is String
              ? _dayHeading(row, groups[row]!)
              : _orderCard(row as StoreOrder);
        },
      ),
    );
  }
}
