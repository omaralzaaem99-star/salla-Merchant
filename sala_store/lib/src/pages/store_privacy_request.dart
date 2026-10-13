part of sala_store;

Future<void> openStorePrivacyDeletion(
  BuildContext context, {
  String storeId = '',
  String applicationId = '',
}) async {
  final uid = SallaAuthService.firebaseAuth.currentUser?.uid;
  if (uid == null) return;
  final environment = Firebase.app().options.projectId;
  final key = applicationId.isNotEmpty ? 'application_$applicationId' : storeId;
  const namespace = 'store_privacy_schedule_v2';
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  var closed = false;
  Future<void> finish(Map<String, dynamic> receipt) async {
    if (closed) return;
    final current = SallaAuthService.firebaseAuth.currentUser?.uid;
    if (current != null && current != uid) throw StateError('تغير الحساب.');
    try {
      await clearMerchantAccountIntent();
      await SallaAuthService.removeLocalRetryIntent(
        role: SallaUserRole.store,
        environment: environment,
        ownerUid: uid,
        namespace: namespace,
        intentId: key,
      );
    } catch (_) {
      // Keep any unresolved local receipt for recovery; server closure is final.
    } finally {
      // A local storage failure must not leave a closed account signed in.
      try {
        await SallaAuthService.clearDeletedAccountLocalData(
          SallaUserRole.store,
        );
      } finally {
        await SallaAuthService.signOut();
      }
    }
    closed = true;
    if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
    if (messenger.mounted)
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            receipt['status'] == 'completed'
                ? 'تم حذف حساب المتجر نهائياً وتسجيل خروجك.'
                : receipt['deletionMode'] == 'immediate'
                ? 'أُغلق حسابك. جارٍ استكمال الحذف النهائي تلقائياً.'
                : 'أُغلق حساب المتجر. الحذف النهائي تلقائي بعد 30 يوماً إن لم تسترجعه الإدارة.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
  }

  await navigator.push<void>(
    MaterialPageRoute(
      builder: (_) => StorePrivacyRequestPage(
        storeId: storeId,
        applicationId: applicationId,
        call: (payload) async {
          if (SallaAuthService.firebaseAuth.currentUser?.uid != uid)
            throw StateError('تغير الحساب.');
          final result = await callMerchantAccount(payload);
          final responseUid = SallaAuthService.firebaseAuth.currentUser?.uid;
          if (responseUid != null && responseUid != uid)
            throw StateError('تغير الحساب.');
          // Finish even if the initiating page was disposed while the call ran.
          if (result['signOut'] == true && result['request'] is Map) {
            final receipt = Map<String, dynamic>.from(result['request'] as Map);
            if ((storeId.isNotEmpty && receipt['storeId'] != storeId) ||
                (applicationId.isNotEmpty &&
                    receipt['applicationId'] != applicationId))
              throw StateError('استجابة غير متطابقة');
            await finish(receipt);
          }
          return result;
        },
        loadPending: () async => (await SallaAuthService.loadLocalRetryIntents(
          role: SallaUserRole.store,
          environment: environment,
          ownerUid: uid,
          namespace: namespace,
        ))[key],
        savePending: (payload) => SallaAuthService.saveLocalRetryIntent(
          role: SallaUserRole.store,
          environment: environment,
          ownerUid: uid,
          namespace: namespace,
          intentId: key,
          payload: payload,
        ),
        clearPending: () => SallaAuthService.removeLocalRetryIntent(
          role: SallaUserRole.store,
          environment: environment,
          ownerUid: uid,
          namespace: namespace,
          intentId: key,
        ),
        onScheduled: finish,
      ),
    ),
  );
}

class StorePrivacyRequestPage extends StatefulWidget {
  const StorePrivacyRequestPage({
    super.key,
    this.storeId = '',
    this.applicationId = '',
    required this.call,
    this.loadPending,
    this.savePending,
    this.clearPending,
    this.onScheduled,
  });
  final String storeId;
  final String applicationId;
  final StoreCourierReportLoader call;
  final Future<Map<String, dynamic>?> Function()? loadPending;
  final Future<void> Function(Map<String, dynamic>)? savePending;
  final Future<void> Function()? clearPending;
  final Future<void> Function(Map<String, dynamic>)? onScheduled;
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
        (widget.storeId.isNotEmpty && raw['storeId'] != widget.storeId) ||
        (widget.applicationId.isNotEmpty &&
            raw['applicationId'] != widget.applicationId) ||
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
      _pending ??= await widget.loadPending?.call();
      if (_pending != null &&
          (_pending!['action'] != 'schedule_privacy_deletion' ||
              _pending!['storeId'] !=
                  (widget.storeId.isEmpty ? null : widget.storeId) ||
              _pending!['applicationId'] !=
                  (widget.applicationId.isEmpty
                      ? null
                      : widget.applicationId) ||
              ![0, 30].contains(_pending!['graceDays']) ||
              _pending!['confirmation'] !=
                  (_pending!['graceDays'] == 0
                      ? 'DELETE_STORE_ACCOUNT_NOW'
                      : 'DELETE_STORE_ACCOUNT')))
        throw StateError('محاولة محفوظة غير متطابقة');
      final response = await widget.call({
        'action': 'scheduled_privacy_status',
        if (widget.storeId.isNotEmpty) 'storeId': widget.storeId,
        if (widget.applicationId.isNotEmpty)
          'applicationId': widget.applicationId,
      });
      final result = _parse(response);
      if (!mounted) return;
      setState(() {
        _request =
            result?['status'] == 'restored' ||
                response['canConfirmImmediateDeletion'] == true
            ? null
            : result;
        _ready = true;
      });
      if (response['signOut'] == true && result != null) await _closed(result);
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
    if (_pending == null) {
      final accepted = await showSallaLifecycleSafeDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('تأكيد حذف الحساب نهائياً'),
          content: const Text(
            'سيُحذف رقم هاتف المتجر وعنوانه وصوره وبيانات دخوله دون مهلة استرجاع، وتُسجّل خروجك. يبقى للإدارة سجل باسم المتجر وتاريخ الحذف، والسجلات المالية اللازمة لحفظ الحقوق. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('تراجع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('نعم، احذف حسابي نهائياً'),
            ),
          ],
        ),
      );
      if (!mounted || accepted != true || _busy) return;
    }
    final random = math.Random.secure();
    _pending ??= Map<String, dynamic>.unmodifiable({
      'action': 'schedule_privacy_deletion',
      if (widget.storeId.isNotEmpty) 'storeId': widget.storeId,
      if (widget.applicationId.isNotEmpty)
        'applicationId': widget.applicationId,
      'confirmation': 'DELETE_STORE_ACCOUNT_NOW',
      'graceDays': 0,
      'requestId':
          'privacy_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
    });
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.savePending?.call(_pending!);
      if (!mounted) return;
      final response = await widget.call(_pending!);
      final saved = _parse(response);
      if (saved == null) throw const FormatException('لم يصل إيصال الطلب.');
      if (!mounted) return;
      setState(() {
        _request = saved['status'] == 'restored' ? null : saved;
        _pending = null;
      });
      if (response['signOut'] == true) {
        await _closed(saved);
      } else {
        await widget.clearPending?.call();
      }
    } catch (error) {
      if (mounted)
        setState(
          () => _error =
              error is FirebaseFunctionsException &&
                  error.code == 'failed-precondition'
              ? (error.message ?? 'تعذر حذف الحساب الآن.')
              : 'لم يتأكد إرسال الطلب. أعد المحاولة؛ لن يتكرر طلبك إذا كان قد وصل.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closed(Map<String, dynamic> receipt) async {
    try {
      await widget.clearPending?.call();
    } finally {
      await widget.onScheduled?.call(receipt);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('حذف الحساب')),
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
            'بعد تأكيدك يبدأ حذف حساب المتجر وبياناته مباشرة وتُسجّل خروجك تلقائياً، دون مهلة استرجاع.',
          ),
          const SizedBox(height: 12),
          const Text(
            'يُحذف رقم الهاتف والعنوان والصور وبيانات الدخول الخاصة بالمتجر. يبقى للإدارة سجل باسم المتجر وتاريخ الحذف، والسجلات المالية اللازمة لحفظ الحقوق وأدوارك الأخرى إن وجدت. أكمل أو ألغِ الطلبات الجارية قبل الحذف.',
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
          if (_pending?['graceDays'] == 30)
            const Text(
              'هذه محاولة سابقة مؤكدة بمهلة 30 يوماً؛ ستُستكمل كما وافقت عليها سابقاً ولن تتحول إلى حذف فوري.',
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
                          : _request!['deletionMode'] == 'immediate' ||
                                _request!['status'] == 'cleanup_pending'
                          ? 'جارٍ استكمال الحذف'
                          : _request!['status'] == 'scheduled'
                          ? 'أُغلق حسابك · الحذف النهائي بعد 30 يوماً'
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
                'أفهم أن الحذف نهائي دون استرجاع، وأن سجل اسم المتجر وتاريخ الحذف والسجلات المالية ستبقى لدى الإدارة.',
              ),
            ),
            FilledButton.icon(
              onPressed: _busy || (!_confirmed && _pending == null)
                  ? null
                  : _submit,
              icon: const Icon(Icons.send_outlined),
              label: Text(
                _pending == null
                    ? 'حذف الحساب وتسجيل الخروج'
                    : 'إعادة محاولة الإرسال',
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
