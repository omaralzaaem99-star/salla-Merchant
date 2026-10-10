part of '../../main.dart';

typedef StoreApplicationCall =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data);

final merchantAccountChanges = ValueNotifier<int>(0);
bool _merchantLoginRequested = false;
const _merchantAccountNamespace = 'store_guest_application_v1';
Future<Map<String, dynamic>?> loadMerchantAccountIntent() async =>
    (await SallaAuthService.loadLocalRetryIntents(
      role: SallaUserRole.store,
      environment: Firebase.app().options.projectId,
      ownerUid: 'guest',
      namespace: _merchantAccountNamespace,
    ))['application'];
Future<void> saveMerchantAccountIntent(Map<String, dynamic> value) async {
  await SallaAuthService.saveLocalRetryIntent(
    role: SallaUserRole.store,
    environment: Firebase.app().options.projectId,
    ownerUid: 'guest',
    namespace: _merchantAccountNamespace,
    intentId: 'application',
    payload: value,
  );
  merchantAccountChanges.value++;
}

Future<void> clearMerchantAccountIntent() async {
  await SallaAuthService.removeLocalRetryIntent(
    role: SallaUserRole.store,
    environment: Firebase.app().options.projectId,
    ownerUid: 'guest',
    namespace: _merchantAccountNamespace,
    intentId: 'application',
  );
  merchantAccountChanges.value++;
}

Future<Map<String, dynamic>> callMerchantAccount(
  Map<String, dynamic> data,
) async => Map<String, dynamic>.from(
  (await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
            'manageStoreRecord',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<Map<String, dynamic>>(data))
      .data,
);

Future<void> openMerchantSupport(BuildContext context) async {
  try {
    if (await launchUrl(
      Uri.https('wa.me', '/9647775655367'),
      mode: LaunchMode.externalApplication,
    ))
      return;
  } catch (_) {}
  if (context.mounted)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح واتساب. رقم الدعم: 07775655367')),
    );
}

class StoreAccessEntry extends StatefulWidget {
  const StoreAccessEntry({super.key, required this.authBuilder});
  final Widget Function(VoidCallback explore) authBuilder;
  @override
  State<StoreAccessEntry> createState() => _StoreAccessEntryState();
}

class _StoreAccessEntryState extends State<StoreAccessEntry> {
  bool _login = false;
  bool _restoring = true, _explorePending = false;
  Map<String, dynamic>? _pending;
  int _restoreGeneration = 0;
  @override
  void initState() {
    super.initState();
    merchantAccountChanges.addListener(_restore);
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final generation = ++_restoreGeneration;
    try {
      final saved = Firebase.apps.isEmpty
          ? null
          : await loadMerchantAccountIntent();
      if (!mounted || generation != _restoreGeneration) return;
      setState(() {
        _pending = saved?['action'] == 'create_pending_store_account'
            ? saved
            : null;
        if (_merchantLoginRequested) {
          _login = true;
          _merchantLoginRequested = false;
        }
        _restoring = false;
      });
    } catch (_) {
      if (mounted && generation == _restoreGeneration)
        setState(() => _restoring = false);
    }
  }

  @override
  void dispose() {
    merchantAccountChanges.removeListener(_restore);
    super.dispose();
  }

  late final _authChanges = Firebase.apps.isEmpty
      ? const Stream<dynamic>.empty()
      : SallaAuthService.firebaseAuth.authStateChanges();
  @override
  Widget build(BuildContext context) => StreamBuilder<dynamic>(
    stream: _authChanges,
    initialData: Firebase.apps.isEmpty
        ? null
        : SallaAuthService.firebaseAuth.currentUser,
    builder: (context, snapshot) => _restoring
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _pending != null && !_login
        ? _explorePending
              ? StoreExplorePage(
                  onLogin: () => setState(() => _explorePending = false),
                  onApply: () => setState(() => _explorePending = false),
                )
              : _pending!['received'] == true
              ? StorePendingAccountPage(
                  key: ValueKey(_pending!['applicationId']),
                  receipt: _pending!,
                  onExplore: () => setState(() => _explorePending = true),
                  onLogin: () => setState(() => _login = true),
                  onActivated: () {
                    unawaited(_restore());
                  },
                )
              : const StoreApplicationPage()
        : snapshot.data != null || _login
        ? widget.authBuilder(() => setState(() => _login = false))
        : StoreExplorePage(onLogin: () => setState(() => _login = true)),
  );
}

class StoreExplorePage extends StatelessWidget {
  const StoreExplorePage({super.key, required this.onLogin, this.onApply});
  final VoidCallback onLogin;
  final VoidCallback? onApply;
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: StoreHomePage.guest(onLogin: onLogin, onApply: onApply),
  );
}

Future<void> showStoreGuestAccess(
  BuildContext context, {
  required VoidCallback onLogin,
  required VoidCallback onApply,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_outline_rounded, color: appColor, size: 36),
            const SizedBox(height: 12),
            const Text(
              'استخدم الميزة بحساب متجرك',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'استكشف التطبيق بحرية. لاستخدام الخدمات، سجّل الدخول أو أنشئ حساب متجرك وانتظر تفعيل الإدارة.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext, 'login'),
              child: const Text('تسجيل الدخول'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(sheetContext, 'apply'),
              child: const Text('إنشاء حساب'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('متابعة الاستكشاف'),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'login') onLogin();
  if (action == 'apply') onApply();
}

String merchantApplicationPhone(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  var phone = value
      .split('')
      .map(
        (c) => arabic.contains(c)
            ? '${arabic.indexOf(c)}'
            : persian.contains(c)
            ? '${persian.indexOf(c)}'
            : c,
      )
      .join()
      .replaceAll(RegExp(r'[\s()+-]'), '');
  if (phone.startsWith('00964'))
    phone = '0${phone.substring(5)}';
  else if (phone.startsWith('964'))
    phone = '0${phone.substring(3)}';
  return phone;
}

Future<void>? _merchantActivation;
Future<void> activateMerchantAccount(
  Map<String, dynamic> receipt,
  Map<String, dynamic> status,
) {
  return _merchantActivation ??= (() async {
    final user = SallaAuthService.firebaseAuth.currentUser;
    if (user == null || user.uid != receipt['applicantUid'])
      throw StateError('session-changed');
    if (status['status'] == 'approved') {
      await SallaAuthService.signInWithLinkCode(
        role: SallaUserRole.store,
        requestedName: '${status['storeName'] ?? ''}',
        phone: '${status['phone'] ?? ''}',
        linkCode: '${status['linkCode'] ?? ''}',
      );
    } else {
      final identity = await SallaAuthService.resolveIdentity(
        user: user,
        expectedRole: SallaUserRole.store,
        allowFirstAdminBootstrap: false,
      );
      if (identity == null || !identity.active)
        throw StateError('identity-unconfirmed');
      await SallaAuthService.saveLocalIdentity(identity);
    }
    // Never erase the pending receipt until the existing login path confirms it.
    await clearMerchantAccountIntent();
  })().whenComplete(() => _merchantActivation = null);
}

class StorePendingAccountPage extends StatefulWidget {
  const StorePendingAccountPage({
    super.key,
    required this.receipt,
    this.call,
    this.activate,
    this.onExplore,
    this.onLogin,
    this.onActivated,
  });
  final Map<String, dynamic> receipt;
  final StoreApplicationCall? call;
  final Future<void> Function(Map<String, dynamic>)? activate;
  final VoidCallback? onExplore, onLogin, onActivated;
  @override
  State<StorePendingAccountPage> createState() =>
      _StorePendingAccountPageState();
}

class _StorePendingAccountPageState extends State<StorePendingAccountPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false, _opening = false, _active = true, _completed = false;
  String _status = 'pending', _error = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted ||
        _busy ||
        _completed ||
        !_active ||
        ModalRoute.of(context)?.isCurrent == false)
      return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      if (widget.call == null &&
          SallaAuthService.firebaseAuth.currentUser?.uid !=
              widget.receipt['applicantUid']) {
        setState(() => _status = 'sign_in_required');
        return;
      }
      final response = await (widget.call ?? callMerchantAccount)({
        'action': 'get_pending_store_account',
        'applicationId': widget.receipt['applicationId'],
      });
      if (!mounted) return;
      if (response['ok'] != true ||
          ![
            'pending',
            'approved',
            'active',
            'sign_in_required',
          ].contains(response['status']))
        throw StateError('unconfirmed');
      setState(() => _status = '${response['status']}');
      if (_status == 'approved' || _status == 'active') {
        if (!_active || ModalRoute.of(context)?.isCurrent == false) return;
        setState(() => _opening = true);
        if (widget.activate != null) {
          await widget.activate!(response);
        } else {
          await activateMerchantAccount(widget.receipt, response);
        }
        if (!mounted) return;
        _completed = true;
        _timer?.cancel();
        widget.onActivated?.call();
      }
    } on FirebaseFunctionsException catch (error) {
      if (mounted)
        setState(() {
          if (error.code == 'permission-denied' ||
              error.code == 'unauthenticated')
            _status = 'sign_in_required';
          else
            _error =
                'تعذر تحديث حالة الحساب الآن. معلوماتك محفوظة؛ حاول مجدداً.';
        });
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error = 'تعذر إكمال التحقق الآن. معلوماتك محفوظة؛ أعد المحاولة.',
        );
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _opening = false;
        });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _step(
    IconData icon,
    String title,
    String subtitle, {
    bool done = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: appColor.withValues(alpha: .09),
          child: Icon(done ? Icons.check_rounded : icon, color: appColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: mutedText, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('حساب متجرك'),
        actions: [
          IconButton(
            tooltip: 'التواصل مع الدعم',
            onPressed: () => openMerchantSupport(context),
            icon: const Icon(Icons.chat_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF096D6B), appColor],
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _completed
                            ? Icons.verified_rounded
                            : Icons.hourglass_top_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _completed
                          ? 'تم تفعيل حسابك'
                          : _status == 'sign_in_required'
                          ? 'تابع حسابك مع الدعم'
                          : _opening
                          ? 'تمت الموافقة · جارٍ فتح حسابك'
                          : _status == 'approved' || _status == 'active'
                          ? 'تمت الموافقة على حسابك'
                          : 'حسابك قيد المراجعة',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status == 'sign_in_required'
                          ? 'استخدم رقم هاتفك ورمز الإدارة لتسجيل الدخول، أو تواصل مع الدعم لمتابعة حسابك.'
                          : 'استلمنا معلومات متجرك. تراجع الإدارة طلبك وتستكمل تفعيل حسابك خلال أقل من 24 ساعة.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, height: 1.8),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${widget.receipt['storeName'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.receipt['phone'] ?? ''}',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.receipt['address'] ?? ''}',
                        style: const TextStyle(color: mutedText, height: 1.6),
                      ),
                      const Divider(height: 30),
                      _step(
                        Icons.task_alt,
                        'تم استلام معلوماتك',
                        'لا تحتاج إلى تقديم البيانات مرة ثانية.',
                        done: true,
                      ),
                      _step(
                        Icons.fact_check_outlined,
                        'مراجعة الإدارة',
                        'نتحقق من معلومات المتجر ونكمل تفاصيل الحساب.',
                      ),
                      _step(
                        Icons.lock_open_rounded,
                        'تفعيل الحساب',
                        'بعد الموافقة يفتح حسابك من هذا الهاتف. للدخول من هاتف آخر استخدم رقمك ورمز الإدارة.',
                      ),
                    ],
                  ),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error,
                    style: const TextStyle(color: Colors.red, height: 1.6),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || _completed ? null : _refresh,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_busy ? 'جارٍ التحقق…' : 'تحديث حالة الحساب'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => openMerchantSupport(context),
                icon: const Icon(Icons.chat_outlined),
                label: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('التواصل مع الدعم'),
                ),
              ),
              if (widget.onLogin != null)
                TextButton(
                  onPressed: widget.onLogin,
                  child: const Text('تسجيل الدخول برمز الإدارة'),
                ),
              if (widget.onExplore != null)
                TextButton(
                  onPressed: widget.onExplore,
                  child: const Text('متابعة الاستكشاف'),
                ),
              const StorePublicLinks(compact: true),
            ],
          ),
        ),
      ),
    ),
  );
}

class StoreApplicationPage extends StatefulWidget {
  const StoreApplicationPage({
    super.key,
    this.call,
    this.load,
    this.save,
    this.clear,
    this.ensureSession,
  });
  final StoreApplicationCall? call;
  final Future<Map<String, dynamic>?> Function()? load;
  final Future<void> Function(Map<String, dynamic>)? save;
  final Future<void> Function()? clear;
  final Future<String> Function()? ensureSession;
  @override
  State<StoreApplicationPage> createState() => _StoreApplicationPageState();
}

class _StoreApplicationPageState extends State<StoreApplicationPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _address = TextEditingController();
  bool _ready = false, _busy = false, _consent = false, _done = false;
  String _error = '';
  Map<String, dynamic>? _intent;
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final saved = widget.load != null
          ? await widget.load!()
          : await loadMerchantAccountIntent();
      if (!mounted) return;
      if (saved != null) {
        _intent = Map<String, dynamic>.unmodifiable(saved);
        _name.text = '${saved['storeName'] ?? ''}';
        _phone.text = '${saved['phone'] ?? ''}';
        _address.text = '${saved['address'] ?? ''}';
        _consent = saved['consent'] == true;
        _done = saved['received'] == true;
      }
      setState(() => _ready = true);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'تعذر تجهيز الطلب المحفوظ. أعد فتح الصفحة.');
    }
  }

  Future<void> _save(Map<String, dynamic> value) => widget.save != null
      ? widget.save!(value)
      : saveMerchantAccountIntent(value);
  Future<void> _clear() =>
      widget.clear != null ? widget.clear!() : clearMerchantAccountIntent();
  Future<String> _session() async {
    if (widget.ensureSession != null) return widget.ensureSession!();
    final auth = SallaAuthService.firebaseAuth;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    if (user == null || !user.isAnonymous) throw StateError('missing-session');
    return user.uid;
  }

  Future<void> _submit() async {
    if (_busy || !_ready || !_form.currentState!.validate()) return;
    if (!_consent) {
      setState(() => _error = 'وافق على التواصل بخصوص طلبك أولاً.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final uid = await _session();
      if (_intent?['applicantUid'] != null && _intent!['applicantUid'] != uid) {
        if (mounted)
          setState(
            () => _error =
                'هذا التقديم مرتبط بجلسة أخرى. استخدم تسجيل الدخول أو تواصل مع الدعم.',
          );
        return;
      }
      _intent ??= Map<String, dynamic>.unmodifiable({
        'action': 'create_pending_store_account',
        'applicantUid': uid,
        'requestId': List.generate(
          24,
          (_) => math.Random.secure().nextInt(16).toRadixString(16),
        ).join(),
        'storeName': _name.text.trim(),
        'phone': merchantApplicationPhone(_phone.text),
        'address': _address.text.trim(),
        'consent': true,
      });
      await _save(_intent!);
      if (!mounted) return;
      final response = widget.call != null
          ? await widget.call!(_intent!)
          : await callMerchantAccount(_intent!);
      if (response['ok'] != true || response['received'] != true)
        throw StateError('unconfirmed');
      if (_intent!['action'] == 'create_pending_store_account') {
        if (!RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch('${response['applicationId'] ?? ''}'))
          throw StateError('missing-receipt');
        _intent = Map<String, dynamic>.unmodifiable({
          ..._intent!,
          'received': true,
          'applicationId': response['applicationId'],
        });
        await _save(_intent!);
      } else {
        // Complete an immutable pre-update enquiry without changing its payload.
        await _clear();
      }
      if (mounted) setState(() => _done = true);
    } on FirebaseFunctionsException catch (error) {
      // Validation rejects before any enquiry write. An unknown outcome must
      // retain the saved immutable intent even if this route is closed.
      if (error.code == 'invalid-argument' || error.code == 'already-exists') {
        try {
          await _clear();
          _intent = null;
        } catch (_) {}
      }
      if (mounted)
        setState(
          () => _error = error.code == 'invalid-argument'
              ? 'راجع اسم المتجر ورقم الهاتف والعنوان ثم أعد الإرسال.'
              : error.code == 'already-exists' ||
                    error.code == 'failed-precondition'
              ? 'يوجد تقديم سابق لهذا الرقم أو يحتاج متابعة. سجّل الدخول برمز الإدارة أو تواصل مع الدعم.'
              : error.code == 'resource-exhausted'
              ? 'وصلت إلى حد المحاولات. تواصل معنا عبر واتساب لمتابعة طلبك.'
              : 'لم يتأكد إرسال الطلب. أعد المحاولة بالبيانات نفسها أو تواصل معنا.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'لم يتأكد إرسال الطلب. أعد المحاولة؛ سنستخدم البيانات نفسها لمنع التكرار.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _done && _intent?['received'] == true
      ? StorePendingAccountPage(
          receipt: _intent!,
          call: widget.call,
          onExplore: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (pageContext) => StoreExplorePage(
                onLogin: () => Navigator.pop(pageContext),
                onApply: () => Navigator.pop(pageContext),
              ),
            ),
          ),
          onLogin: () {
            _merchantLoginRequested = true;
            merchantAccountChanges.value++;
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          onActivated: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        )
      : Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: const Text('إنشاء حساب')),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(22),
                  children: [
                    if (_done) ...[
                      const Icon(
                        Icons.task_alt_rounded,
                        size: 72,
                        color: appColor,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'وصل طلبك إلى الإدارة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'إذا سبق أن قدّمت طلباً بنفس الرقم، ستتابع الإدارة الطلب الموجود. تقديم الطلب لا يفعّل الحساب فوراً؛ سنتواصل معك لإكمال التفاصيل وإرسال بيانات الدخول.',
                        textAlign: TextAlign.center,
                        style: TextStyle(height: 1.8),
                      ),
                    ] else
                      Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'خلّينا نتعرّف على متجرك',
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'أنشئ حساب متجرك بثلاث معلومات. تراجع الإدارة التفاصيل وتفعّل حسابك خلال أقل من 24 ساعة.',
                              style: TextStyle(height: 1.7),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _name,
                              enabled: _ready && !_busy && _intent == null,
                              maxLength: 100,
                              decoration: const InputDecoration(
                                labelText: 'اسم المتجر',
                                prefixIcon: Icon(Icons.storefront_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  (v ?? '').trim().length < 2 ||
                                      RegExp(r'[\x00-\x1f]').hasMatch(v ?? '')
                                  ? 'اكتب اسم المتجر'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _phone,
                              enabled: _ready && !_busy && _intent == null,
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                              maxLength: 35,
                              decoration: const InputDecoration(
                                labelText: 'رقم الهاتف',
                                prefixIcon: Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  RegExp(
                                    r'^07[0-9]{9}$',
                                  ).hasMatch(merchantApplicationPhone(v ?? ''))
                                  ? null
                                  : 'اكتب رقم هاتف عراقي صحيحاً',
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _address,
                              enabled: _ready && !_busy && _intent == null,
                              maxLength: 300,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'عنوان المتجر كتابةً',
                                hintText:
                                    'المحافظة، المنطقة، الشارع وأقرب نقطة دالة',
                                prefixIcon: Icon(Icons.location_on_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  (v ?? '').trim().length < 5 ||
                                      RegExp(r'[\x00-\x1f]').hasMatch(v ?? '')
                                  ? 'اكتب عنواناً واضحاً للمتجر'
                                  : null,
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _consent,
                              onChanged: _busy || _intent != null
                                  ? null
                                  : (v) =>
                                        setState(() => _consent = v ?? false),
                              title: const Text(
                                'أوافق على استخدام هذه البيانات للتواصل معي ومراجعة طلب الحساب.',
                              ),
                            ),
                            if (_error.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  _error,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            FilledButton(
                              onPressed: _ready && !_busy ? _submit : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  _busy
                                      ? 'جارٍ إرسال طلبك…'
                                      : _intent == null
                                      ? 'إنشاء حساب'
                                      : 'إعادة إرسال الطلب نفسه',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => openMerchantSupport(context),
                      icon: const Icon(Icons.chat_outlined),
                      label: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text('التواصل مع الدعم'),
                      ),
                    ),
                    const Text(
                      '07775655367',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        _merchantLoginRequested = true;
                        merchantAccountChanges.value++;
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      },
                      child: const Text('لديك حساب؟ تسجيل الدخول'),
                    ),
                    const StorePublicLinks(compact: true),
                  ],
                ),
              ),
            ),
          ),
        );
}
