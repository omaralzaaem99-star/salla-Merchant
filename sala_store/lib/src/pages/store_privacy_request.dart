part of sala_store;

class StorePrivacyRequestPage extends StatefulWidget {
  const StorePrivacyRequestPage({
    super.key,
    required this.storeId,
    required this.call,
  });
  final String storeId;
  final StoreCourierReportLoader call;
  @override
  State<StorePrivacyRequestPage> createState() =>
      _StorePrivacyRequestPageState();
}

class _StorePrivacyRequestPageState extends State<StorePrivacyRequestPage> {
  bool _busy = false, _ready = false, _confirmed = false;
  String _error = '';
  Map<String, dynamic>? _request, _pending;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Map<String, dynamic>? _parse(Map<String, dynamic> result) {
    if (result['ok'] != true) throw const FormatException('لم تتأكد العملية.');
    final raw = result['request'];
    if (raw == null) return null;
    if (raw is! Map ||
        raw['storeId'] != widget.storeId ||
        raw['id'] is! String ||
        raw['status'] is! String) {
      throw const FormatException('استجابة الطلب غير متطابقة.');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = _parse(
        await widget.call({
          'action': 'privacy_status',
          'storeId': widget.storeId,
        }),
      );
      if (!mounted) return;
      setState(() {
        _request = result;
        _ready = true;
        if (result != null) _pending = null;
      });
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error = 'تعذر تحميل حالة الطلب. تحقق من الاتصال وأعد المحاولة.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy ||
        !_ready ||
        (!_confirmed && _pending == null) ||
        _request != null)
      return;
    final random = math.Random.secure();
    _pending ??= Map<String, dynamic>.unmodifiable({
      'action': 'request_privacy_deletion',
      'storeId': widget.storeId,
      'confirmation': 'DELETE_STORE_ACCOUNT',
      'requestId':
          'privacy_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
    });
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final saved = _parse(await widget.call(_pending!));
      if (saved == null) throw const FormatException('لم يصل إيصال الطلب.');
      if (!mounted) return;
      setState(() {
        _request = saved;
        _pending = null;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'لم يتأكد إرسال الطلب. أعد المحاولة؛ لن يتكرر طلبك إذا كان قد وصل.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('طلب حذف الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.privacy_tip_outlined, color: appColor, size: 46),
          const SizedBox(height: 16),
          const Text(
            'حسابك وبياناتك',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'أرسل طلبك من هنا دون مكالمة. تراجعه الإدارة ثم تنفذ حذف بيانات حساب المتجر وصوره وبيانات الدخول الخاصة به. تبقى سجلات الطلبات والتسويات المطلوبة لحفظ الحقوق، وتبقى أدوارك الأخرى إن وجدت.',
          ),
          const SizedBox(height: 12),
          const Text(
            'تبدأ المراجعة خلال 30 يوماً. قد يتأخر التنفيذ إلى حين إكمال الطلبات الجارية وتسوية الحقوق القائمة. إرسال الطلب وحده لا يوقف العمل فوراً؛ التنفيذ بعد تأكيد الإدارة.',
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),
          if (_request != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _request!['status'] == 'completed'
                          ? 'اكتمل الحذف'
                          : _request!['status'] == 'cleanup_pending'
                          ? 'جارٍ استكمال الحذف'
                          : 'طلبك مسجل لدى الإدارة',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SelectableText('رقم المتابعة: ${_request!['id']}'),
                    const SizedBox(height: 8),
                    Text(_request!['message']?.toString() ?? ''),
                  ],
                ),
              ),
            ),
          ] else if (_ready) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: _busy || _pending != null
                  ? null
                  : (v) => setState(() => _confirmed = v == true),
              title: const Text(
                'أطلب حذف حساب هذا المتجر وأفهم البيانات التي يجب الاحتفاظ بها.',
              ),
            ),
            FilledButton.icon(
              onPressed: _busy || (!_confirmed && _pending == null)
                  ? null
                  : _submit,
              icon: const Icon(Icons.send_outlined),
              label: Text(
                _pending == null ? 'إرسال طلب الحذف' : 'إعادة محاولة الإرسال',
              ),
            ),
          ],
          TextButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث حالة الطلب'),
          ),
        ],
      ),
    ),
  );
}
