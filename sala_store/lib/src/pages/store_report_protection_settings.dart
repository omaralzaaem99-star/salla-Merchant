part of sala_store;

/// Secrets and an uncertain save stay in memory only, never in the retry disk queue.
class StoreReportProtectionSettings extends StatefulWidget {
  const StoreReportProtectionSettings({
    super.key,
    required this.expectedStoreId,
    required this.call,
    required this.onClose,
  });
  final String expectedStoreId;
  final StoreCourierReportLoader call;
  final VoidCallback onClose;

  @override
  State<StoreReportProtectionSettings> createState() =>
      _StoreReportProtectionSettingsState();
}

class _StoreReportProtectionSettingsState
    extends State<StoreReportProtectionSettings>
    with WidgetsBindingObserver {
  final _current = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _ready = false;
  bool _busy = false;
  bool _wasEnabled = false;
  bool _enabled = false;
  bool _foreground = true;
  bool _saved = false;
  int _revision = 0;
  int _generation = 0;
  String _error = '';
  Map<String, dynamic>? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  void _clearInputs() {
    _current.clear();
    _pin.clear();
    _confirm.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _pending = null;
    _current.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) {
        _generation++;
        _clearInputs();
        if (_pending == null) _busy = false;
      }
    });
    if (_foreground) {
      if (_saved) {
        widget.onClose();
      } else if (_pending == null) {
        unawaited(_load());
      }
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _ready = false;
      _error = '';
    });
    try {
      final result = await widget.call({
        'storeId': widget.expectedStoreId,
        'action': 'report_access_status',
      });
      if (!mounted || generation != _generation) return;
      if (result['enabled'] is! bool || result['revision'] is! int) {
        throw const FormatException('استجابة الحماية غير صالحة.');
      }
      setState(() {
        _wasEnabled = _enabled = result['enabled'] as bool;
        _revision = result['revision'] as int;
        _ready = true;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'تعذر تحميل الحماية. تحقق من الاتصال وأعد المحاولة.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_ready || !_foreground) return;
    if (_pending == null) {
      final current = _current.text.trim();
      final pin = _pin.text.trim();
      if (_wasEnabled && !RegExp(r'^\d{6}$').hasMatch(current)) {
        setState(() => _error = 'أدخل الرمز الحالي من 6 أرقام.');
        return;
      }
      if (_enabled && !RegExp(r'^\d{6}$').hasMatch(pin)) {
        setState(() => _error = 'حدد رمزاً جديداً من 6 أرقام.');
        return;
      }
      if (_enabled && pin != _confirm.text.trim()) {
        setState(() => _error = 'تأكيد الرمز الجديد غير مطابق.');
        return;
      }
      final random = math.Random.secure();
      final requestId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _pending = Map<String, dynamic>.unmodifiable({
        'storeId': widget.expectedStoreId,
        'action': 'set_report_access',
        'requestId': 'store_report_$requestId',
        'expectedRevision': _revision,
        'enabled': _enabled,
        if (_wasEnabled) 'currentPin': current,
        if (_enabled) 'reportPin': pin,
      });
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = await widget.call(_pending!);
      if (!mounted) return;
      if (result['ok'] != true ||
          result['enabled'] != _pending!['enabled'] ||
          result['revision'] != (_pending!['expectedRevision'] as int) + 1) {
        throw const FormatException('تعذر تأكيد الحفظ.');
      }
      _pending = null;
      _clearInputs();
      _saved = true;
      if (_foreground) widget.onClose();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      if (const {
        'invalid-argument',
        'permission-denied',
        'aborted',
        'not-found',
        'already-exists',
        'failed-precondition',
        'resource-exhausted',
        'unauthenticated',
      }.contains(error.code)) {
        _pending = null;
        if (error.code == 'aborted') _ready = false;
        if (error.code == 'permission-denied') _current.clear();
        setState(() => _error = error.message ?? 'تعذر حفظ إعدادات الحماية.');
      } else {
        setState(() => _error = 'تعذر تأكيد الحفظ. اضغط إعادة محاولة الحفظ.');
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = 'تعذر تأكيد الحفظ. اضغط إعادة محاولة الحفظ.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController controller, String label, String id) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          key: ValueKey(id),
          controller: controller,
          enabled: !_busy && _pending == null,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _pending == null,
    child: !_foreground
        ? const Center(
            child: Text('إعدادات الحماية مخفية أثناء مغادرة التطبيق.'),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE0EAE7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: appColor, size: 36),
                  const SizedBox(height: 12),
                  const Text(
                    'حماية سجل طلب مندوبك',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: appColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'حدد من يستطيع الاطلاع على سجل طلبات متجرك ومبالغها. هذا الرمز مستقل عن رمز دخول التطبيق.',
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                  if (_ready) ...[
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('قفل السجل برمز'),
                        subtitle: Text(
                          _enabled
                              ? 'يتطلب رمزاً عند فتح السجل'
                              : 'السجل مفتوح دون رمز',
                        ),
                        value: _enabled,
                        onChanged: _busy || _pending != null
                            ? null
                            : (value) => setState(() => _enabled = value),
                      ),
                    ),
                    if (_wasEnabled) ...[
                      const Text(
                        'تغيير الرمز أو إلغاء القفل يتطلب الرمز الحالي.',
                      ),
                      _field(_current, 'الرمز الحالي', 'report_current_pin'),
                    ],
                    if (_enabled) ...[
                      _field(_pin, 'الرمز الجديد', 'report_new_pin'),
                      _field(
                        _confirm,
                        'تأكيد الرمز الجديد',
                        'report_confirm_pin',
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'نسيت الرمز؟ تواصل مع الإدارة لإعادة تعيينه.',
                      style: TextStyle(color: mutedText),
                    ),
                  ],
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : (_ready ? _save : _load),
                        child: Text(
                          !_ready
                              ? 'إعادة التحميل'
                              : _pending != null
                              ? 'إعادة محاولة الحفظ'
                              : 'حفظ الحماية',
                        ),
                      ),
                      TextButton(
                        onPressed: _busy || _pending != null
                            ? null
                            : widget.onClose,
                        child: const Text('العودة إلى السجل'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
  );
}
