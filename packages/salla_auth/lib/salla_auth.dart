import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'src/app_check_monitoring.dart';

enum SallaUserRole { customer, driver, store, admin }

enum SallaLoginMode { phone, email }

/// ينتظر إزالة طبقة الحوار وحركة الخروج بالكامل قبل إعادة النتيجة للمنادي.
/// هذا يمنع تغيير جذر الجلسة بينما Overlay القديم ما زال يفك inherited widgets.
Future<T?> showSallaLifecycleSafeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) async {
  TransitionRoute<dynamic>? transitionRoute;
  final result = await showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    builder: (dialogContext) {
      final route = ModalRoute.of(dialogContext);
      if (route is TransitionRoute<dynamic>) transitionRoute ??= route;
      return builder(dialogContext);
    },
  );
  final route = transitionRoute;
  if (route != null) await route.completed;
  return result;
}

/// نسخة آمنة لدورة حياة BottomSheet. النتيجة لا تكتمل حتى تزال طبقة المسار،
/// لذلك يصبح التخلص من TextEditingController في whenComplete آمناً.
Future<T?> showSallaLifecycleSafeModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
  Clip? clipBehavior,
}) async {
  TransitionRoute<dynamic>? transitionRoute;
  final result = await showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    shape: shape,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    clipBehavior: clipBehavior,
    builder: (sheetContext) {
      final route = ModalRoute.of(sheetContext);
      if (route is TransitionRoute<dynamic>) transitionRoute ??= route;
      return builder(sheetContext);
    },
  );
  final route = transitionRoute;
  if (route != null) await route.completed;
  return result;
}

class SallaAdminClipboardCredentials {
  final String requestedName;
  final String phone;
  final String linkCode;
  final String loginCode;

  const SallaAdminClipboardCredentials({
    required this.requestedName,
    required this.phone,
    required this.linkCode,
    required this.loginCode,
  });
}

SallaAdminClipboardCredentials? parseSallaAdminClipboardCredentials(
  String value,
) {
  final text = value.trim();
  if (!text.contains('بيانات دخول لوحة الإدارة')) return null;
  final fields = <String, String>{};
  for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.trim();
    final separator = line.indexOf(RegExp(r'[:：]'));
    if (separator <= 0 || separator >= line.length - 1) continue;
    final label = line.substring(0, separator).trim();
    final fieldValue = line.substring(separator + 1).trim();
    if (fieldValue.isNotEmpty) fields[label] = fieldValue;
  }
  final requestedName = fields['الاسم']?.trim() ?? '';
  final phone = normalizeIraqiPhone(fields['الهاتف'] ?? '');
  final linkCode = SallaAuthService.normalizeLinkCode(
    fields['رمز الربط'] ?? '',
  );
  final loginCode = SallaAuthService.normalizeLinkCode(
    fields['رمز الدخول'] ?? '',
  );
  if (requestedName.length < 3 ||
      !phone.startsWith('+') ||
      phone.length < 10 ||
      linkCode.length < 4 ||
      loginCode.length < 4) {
    return null;
  }
  return SallaAdminClipboardCredentials(
    requestedName: requestedName,
    phone: phone,
    linkCode: linkCode,
    loginCode: loginCode,
  );
}

class SallaAccountBlockedException implements Exception {
  final String message;

  const SallaAccountBlockedException(this.message);

  @override
  String toString() => message;
}

bool sallaIsExplicitAccountBlock(Object? error) =>
    error is SallaAccountBlockedException;

const Set<String> sallaBlockedOperationalStatuses = <String>{
  'blocked',
  'disabled',
  'suspended',
  'terminated',
};

String sallaEffectiveOperationalAdminStatus(
  Map<dynamic, dynamic> record, {
  DateTime? now,
}) {
  final status = record['adminStatus']?.toString().trim().toLowerCase() ?? '';
  if (status == 'suspended') {
    final rawUntil = record['adminStatusUntil']?.toString().trim() ?? '';
    final until = DateTime.tryParse(rawUntil);
    if (until != null && !until.isAfter(now ?? DateTime.now())) {
      return 'active';
    }
  }
  return status.isEmpty ? 'active' : status;
}

bool sallaOperationalRecordIsBlocked(
  Map<dynamic, dynamic> record, {
  DateTime? now,
}) {
  final status = record['status']?.toString().trim().toLowerCase() ?? '';
  final adminStatus = sallaEffectiveOperationalAdminStatus(record, now: now);
  return record['active'] == false ||
      sallaBlockedOperationalStatuses.contains(status) ||
      sallaBlockedOperationalStatuses.contains(adminStatus);
}

/// Separates a trusted identity binding from an operational driver block.
///
/// A suspended/disabled driver remains authenticated so the driver app can
/// keep reading an already accepted order. This exception is deliberately
/// limited to an administrative status on an otherwise active driver record;
/// an inactive entity or a blocked primary status still invalidates access.
bool sallaEntityRecordAllowsBoundSession(
  Map<dynamic, dynamic> record, {
  required SallaUserRole role,
  bool allowDriverOperationalBlock = false,
  DateTime? now,
}) {
  if (record['active'] == false) return false;
  final status = record['status']?.toString().trim().toLowerCase() ?? '';
  if (sallaBlockedOperationalStatuses.contains(status)) return false;
  final adminStatus = sallaEffectiveOperationalAdminStatus(record, now: now);
  if (!sallaBlockedOperationalStatuses.contains(adminStatus)) return true;
  return role == SallaUserRole.driver && allowDriverOperationalBlock;
}

String sallaOperationalBlockMessage(Map<dynamic, dynamic> record) {
  final reason = record['adminActionReason']?.toString().trim() ?? '';
  return reason.isEmpty
      ? 'هذا الحساب موقوف من لوحة الإدارة.'
      : 'هذا الحساب موقوف من لوحة الإدارة. السبب: $reason';
}

extension SallaUserRoleValue on SallaUserRole {
  String get value => name;

  String get arabicLabel {
    switch (this) {
      case SallaUserRole.customer:
        return 'زبون';
      case SallaUserRole.driver:
        return 'سائق';
      case SallaUserRole.store:
        return 'متجر';
      case SallaUserRole.admin:
        return 'إدارة';
    }
  }
}

class SallaIdentity {
  final String uid;
  final SallaUserRole role;
  final String entityId;
  final String name;
  final String phone;
  final String email;
  final bool active;

  const SallaIdentity({
    required this.uid,
    required this.role,
    required this.entityId,
    required this.name,
    this.phone = '',
    this.email = '',
    this.active = true,
  });

  factory SallaIdentity.fromMap(
    String uid,
    Map<String, dynamic> data,
  ) {
    final rawRole = data['role']?.toString().trim() ?? '';
    final matchingRoles = SallaUserRole.values.where(
      (item) => item.value == rawRole,
    );
    if (matchingRoles.isEmpty) {
      throw StateError('ملف الحساب يحتوي دوراً غير صالح.');
    }
    final entityId = data['entityId']?.toString().trim() ?? '';
    if (entityId.isEmpty) {
      throw StateError('الحساب غير مرتبط بمعرّف تشغيلي صالح.');
    }
    final role = matchingRoles.first;
    return SallaIdentity(
      uid: uid,
      role: role,
      entityId: entityId,
      name: data['name']?.toString() ?? role.arabicLabel,
      phone: data['phone']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      active: data['active'] != false,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'role': role.value,
      'entityId': entityId,
      'name': name,
      'phone': phone,
      'email': email,
      'active': active,
    };
  }
}

class SallaSavedLogin {
  final SallaUserRole role;
  final String name;
  final String phone;
  final String email;
  final DateTime savedAt;

  const SallaSavedLogin({
    required this.role,
    this.name = '',
    this.phone = '',
    this.email = '',
    required this.savedAt,
  });

  /// Kept only as a source-compatible boundary for older app consumers.
  /// Access codes are intentionally never restored from local storage.
  @Deprecated('Access codes are never persisted or restored.')
  String get linkCode => '';

  /// Kept only as a source-compatible boundary for older app consumers.
  /// Access codes are intentionally never restored from local storage.
  @Deprecated('Access codes are never persisted or restored.')
  String get loginCode => '';

  factory SallaSavedLogin.fromMap(Map<String, dynamic> data) {
    final rawRole = data['role']?.toString() ?? '';
    final role = SallaUserRole.values.firstWhere(
      (item) => item.value == rawRole,
      orElse: () => SallaUserRole.customer,
    );
    return SallaSavedLogin(
      role: role,
      name: data['name']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      savedAt: DateTime.tryParse(data['savedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'role': role.value,
      'name': name,
      'phone': phone,
      'email': email,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  bool get hasUsableData =>
      name.trim().isNotEmpty ||
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty;
}

class SallaWhatsappOtpRequest {
  final String requestId;
  final String status;
  final String phoneMasked;
  final int resendSeconds;
  final int retryAfterSeconds;
  final int expiresAtMs;
  final bool deliveryUncertain;

  const SallaWhatsappOtpRequest({
    required this.requestId,
    required this.status,
    this.phoneMasked = '',
    this.resendSeconds = 30,
    this.retryAfterSeconds = 0,
    this.expiresAtMs = 0,
    this.deliveryUncertain = false,
  });
}

enum SallaWhatsappOtpSource {
  customerLogin('customer_login', false),
  customerCourier('customer_courier', true);

  final String value;
  final bool requiresPickup;

  const SallaWhatsappOtpSource(this.value, this.requiresPickup);
}

class SallaWhatsappOtpRequestContext {
  final double pickupLat;
  final double pickupLng;

  const SallaWhatsappOtpRequestContext({
    required this.pickupLat,
    required this.pickupLng,
  });

  bool get isValid =>
      pickupLat.isFinite &&
      pickupLng.isFinite &&
      pickupLat >= -90 &&
      pickupLat <= 90 &&
      pickupLng >= -180 &&
      pickupLng <= 180;
}

typedef SallaWhatsappOtpRequestContextProvider
    = Future<SallaWhatsappOtpRequestContext> Function();

class SallaWhatsappOtpException implements Exception {
  final String message;
  final String reason;
  final bool resultUncertain;
  final int retryAfterSeconds;

  const SallaWhatsappOtpException(
    this.message, {
    this.reason = '',
    this.resultUncertain = false,
    this.retryAfterSeconds = 0,
  });

  @override
  String toString() => message;
}

class SallaAuthService {
  SallaAuthService._();

  static const Duration _localIdentityStorageTimeout = Duration(seconds: 5);
  static const String _localRetryIntentKeyPrefix =
      'salla_local_retry_intent_v1';
  static const Duration _identityResolutionTimeout = Duration(seconds: 20);
  static FirebaseApp? _configuredApp;

  static void configureFirebaseApp(FirebaseApp app) {
    _configuredApp = app;
  }

  static FirebaseAuth get firebaseAuth => _configuredApp == null
      ? FirebaseAuth.instance
      : FirebaseAuth.instanceFor(app: _configuredApp!);

  static FirebaseDatabase get firebaseDatabase => _configuredApp == null
      ? FirebaseDatabase.instance
      : FirebaseDatabase.instanceFor(
          app: _configuredApp!,
          databaseURL: _configuredApp!.options.databaseURL,
        );

  static FirebaseAuth get _auth => firebaseAuth;
  static DatabaseReference get _database => firebaseDatabase.ref();
  static FirebaseFunctions get _functions => _configuredApp == null
      ? FirebaseFunctions.instanceFor(region: 'europe-west1')
      : FirebaseFunctions.instanceFor(
          app: _configuredApp!,
          region: 'europe-west1',
        );
  static final ValueNotifier<int> sessionRevision = ValueNotifier<int>(0);
  static bool _customerWhatsappOtpEnabled = false;

  static const Set<String> _whatsappOtpExplicitTerminalReasons = <String>{
    'invalid_iraqi_phone_number',
    'whatsapp_otp_disabled',
    'missing_otpiq_api_key',
    'missing_otp_hash_secret',
    'otpiq_credentials_rejected',
    'otpiq_rate_limited',
    'otpiq_insufficient_credit',
    'otpiq_whatsapp_unavailable',
    'otpiq_invalid_phone',
    'otpiq_request_rejected',
    'otpiq_contract_mismatch',
    'otp_session_not_found',
    'otp_phone_mismatch',
    'invalid_otp_code',
    'otp_expired',
    'otp_attempts_exceeded',
    'otp_code_mismatch',
    'otp_verification_id_conflict',
    'customer_sign_in_token_failed',
    'rate_limited',
    'operational_owner_is_not_firebase_functions',
  };

  static bool whatsappOtpCallableResultUncertain({
    required String code,
    required String reason,
  }) {
    final normalizedCode = code.trim().toLowerCase();
    final normalizedReason = reason.trim();
    if (_whatsappOtpExplicitTerminalReasons.contains(normalizedReason)) {
      return false;
    }
    if (normalizedReason == 'otpiq_delivery_unknown') return true;
    return const <String>{
      'cancelled',
      'deadline-exceeded',
      'data-loss',
      'unavailable',
      'internal',
      'resource-exhausted',
      'unknown',
    }.contains(normalizedCode);
  }

  static bool whatsappOtpRequestExpired({
    required String operationId,
    required DateTime? expiresAt,
    required DateTime now,
  }) {
    return operationId.trim().isNotEmpty &&
        expiresAt != null &&
        !now.isBefore(expiresAt);
  }

  static bool whatsappOtpSendBlockedByCooldown(int remainingSeconds) {
    return remainingSeconds > 0;
  }

  static bool whatsappOtpPhoneChanged({
    required String activePhone,
    required String nextPhone,
  }) {
    if (activePhone.trim().isEmpty) return false;
    return normalizeIraqiPhone(activePhone) != normalizeIraqiPhone(nextPhone);
  }

  static bool shouldReuseWhatsappOtpVerificationOperation({
    required String operationId,
    required String operationRequestId,
    required String operationCode,
    required String requestId,
    required String code,
  }) {
    return operationId.trim().isNotEmpty &&
        operationRequestId == requestId &&
        operationCode == code;
  }

  static bool get customerWhatsappOtpEnabled => _customerWhatsappOtpEnabled;

  static void configureCustomerWhatsappOtp({bool enabled = true}) {
    _customerWhatsappOtpEnabled = enabled;
  }

  static bool identityResolutionFailureRequiresSignOut(Object error) {
    if (error is SallaAccountBlockedException) return true;
    if (error is FirebaseAuthException) {
      return const <String>{
        'invalid-user-token',
        'user-disabled',
        'user-not-found',
        'user-token-expired',
      }.contains(error.code.trim().toLowerCase());
    }
    return false;
  }

  static Future<void> signOut() async {
    await _auth.signOut();
    await clearLocalSessions();
    sessionRevision.value += 1;
  }

  static Future<bool> confirmAndSignOut(
    BuildContext context, {
    Color primaryColor = const Color(0xFF0F766E),
  }) async {
    final shouldSignOut = await showSallaLifecycleSafeDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تسجيل الخروج'),
            content: const Text(
              'هل تريد تسجيل الخروج من هذا الحساب؟ ستبقى بيانات الدخول المحفوظة على هذا الجهاز إذا كنت قد حفظتها.',
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
                style: FilledButton.styleFrom(backgroundColor: primaryColor),
              ),
            ],
          ),
        );
      },
    );
    if (shouldSignOut != true) return false;
    await signOut();
    return true;
  }

  static String employeeIdForUid(String uid) {
    final normalized =
        uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final suffix =
        normalized.length <= 10 ? normalized : normalized.substring(0, 10);
    return 'EMP-$suffix';
  }

  static String accessRequestIdFor(String uid, SallaUserRole role) {
    final safeUid = uid.replaceAll(RegExp(r'[.#$/\[\]]'), '_');
    return '${safeUid}_${role.value}';
  }

  static String normalizeLinkCode(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  static String normalizeNameKey(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static String normalizePhoneDigits(String value) {
    var digits = value
        .split('')
        .map(_normalizePhoneDigit)
        .join()
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('9640')) {
      digits = '964${digits.substring(4)}';
    }
    if (digits.startsWith('0') && digits.length == 11) {
      return '964${digits.substring(1)}';
    }
    if (digits.startsWith('7') && digits.length == 10) {
      return '964$digits';
    }
    return digits;
  }

  static Map<String, dynamic> _databaseMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _whatsappOtpErrorMessage(String status, String error) {
    final cleanError = error.trim();
    switch (cleanError.isEmpty ? status : cleanError) {
      case 'invalid_iraqi_phone_number':
        return 'أدخل رقم واتساب عراقي صحيحاً مثل 07700000000 أو +9647700000000.';
      case 'whatsapp_otp_disabled':
        return 'التحقق عبر واتساب غير مفعل حالياً.';
      case 'missing_otpiq_api_key':
      case 'missing_otp_hash_secret':
        return 'إعدادات OTPIQ على خادم سلة غير مكتملة.';
      case 'otpiq_credentials_rejected':
        return 'رفض OTPIQ بيانات الإرسال. تواصل مع إدارة سلة.';
      case 'otpiq_rate_limited':
        return 'طلبات كثيرة على خدمة واتساب. انتظر قليلاً ثم حاول.';
      case 'otpiq_insufficient_credit':
        return 'رصيد خدمة واتساب غير كافٍ حالياً. تواصل مع إدارة سلة.';
      case 'otpiq_whatsapp_unavailable':
        return 'هذا الرقم غير متاح لاستلام الرمز عبر واتساب. تأكد أن الرقم عليه حساب واتساب فعال.';
      case 'otpiq_invalid_phone':
        return 'رفضت خدمة واتساب صيغة الرقم. اكتب رقماً عراقياً صحيحاً يبدأ بـ 07.';
      case 'otpiq_request_rejected':
        return 'تعذر قبول طلب واتساب لهذا الرقم حالياً.';
      case 'otpiq_contract_mismatch':
        return 'وصل رد غير متوقع من خدمة واتساب. لم نُعد إرسال الرسالة.';
      case 'otpiq_delivery_unknown':
        return 'نتيجة إرسال رمز واتساب غير مؤكدة. إذا وصلك الرمز فأدخله، ولا تطلب رمزاً جديداً قبل انتهاء المهلة.';
      case 'otp_session_not_found':
        return 'انتهت جلسة الرمز. أعد إرسال رمز واتساب.';
      case 'otp_request_source_invalid':
      case 'otp_source_mismatch':
        return 'انتهت محاولة التحقق القديمة. أعد إرسال رمز واتساب جديداً.';
      case 'invalid_coordinate':
      case 'customer_courier_pickup_invalid':
        return 'تعذر تثبيت موقع الاستلام. ارجع إلى اطلب مندوبك وحدد موقعك ثم حاول مجدداً.';
      case 'otp_phone_mismatch':
        return 'رقم الهاتف لا يطابق طلب الرمز.';
      case 'invalid_otp_code':
        return 'أدخل رمز التحقق المكوّن من 6 أرقام.';
      case 'otp_expired':
        return 'انتهت صلاحية رمز واتساب. أعد إرسال الرمز.';
      case 'otp_attempts_exceeded':
        return 'تم تجاوز عدد المحاولات. أعد إرسال رمز جديد.';
      case 'otp_code_mismatch':
        return 'رمز واتساب غير صحيح.';
      case 'customer_sign_in_token_failed':
        return 'تم التحقق من الرمز، لكن تعذر تجهيز جلسة الحساب. حاول مرة أخرى.';
      case 'rate_limited':
        return 'انتظر قليلاً قبل إعادة إرسال الرمز.';
      default:
        return 'تعذر إكمال تحقق واتساب الآن. حاول مرة أخرى.';
    }
  }

  static String newWhatsappOtpOperationId() {
    final operationId = _database.push().key?.trim() ?? '';
    if (operationId.isEmpty) {
      throw StateError('تعذر تجهيز محاولة التحقق. حاول مرة أخرى.');
    }
    return operationId;
  }

  static SallaWhatsappOtpException _callableOtpException(
    FirebaseFunctionsException error,
  ) {
    final details = _databaseMap(error.details);
    final reason = details['reason']?.toString().trim() ?? '';
    final uncertain = whatsappOtpCallableResultUncertain(
      code: error.code,
      reason: reason,
    );
    final message = uncertain
        ? _whatsappOtpErrorMessage('', 'otpiq_delivery_unknown')
        : _whatsappOtpErrorMessage(error.code, reason);
    return SallaWhatsappOtpException(
      message,
      reason: reason.isEmpty ? error.code : reason,
      resultUncertain: uncertain,
      retryAfterSeconds:
          int.tryParse(details['retryAfterSeconds']?.toString() ?? '') ?? 0,
    );
  }

  static Future<SallaWhatsappOtpRequest> requestCustomerWhatsappOtp(
    String phone, {
    required String requestId,
    required SallaWhatsappOtpSource source,
    SallaWhatsappOtpRequestContext? requestContext,
  }) async {
    final normalizedPhone = normalizeIraqiPhone(phone);
    final cleanRequestId = requestId.trim();
    if (!RegExp(r'^\+9647[0-9]{9}$').hasMatch(normalizedPhone)) {
      throw StateError(
        'أدخل رقم واتساب عراقي صحيحاً مثل 07700000000 أو +9647700000000.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(cleanRequestId)) {
      throw StateError('معرّف محاولة التحقق غير صالح. حاول مرة أخرى.');
    }
    if (source.requiresPickup &&
        (requestContext == null || !requestContext.isValid)) {
      throw StateError('تعذر تثبيت موقع الاستلام للتحقق. حاول مجدداً.');
    }
    Map<String, dynamic> value;
    try {
      final callable = _functions.httpsCallable(
        'whatsappOtpRequestOperations',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
      );
      final result = await callable.call<dynamic>(<String, dynamic>{
        'requestId': cleanRequestId,
        'phone': normalizedPhone,
        'source': source.value,
        if (source.requiresPickup) 'pickupLat': requestContext!.pickupLat,
        if (source.requiresPickup) 'pickupLng': requestContext!.pickupLng,
      });
      value = _databaseMap(result.data);
    } on FirebaseFunctionsException catch (error) {
      throw _callableOtpException(error);
    }
    final status = value['status']?.toString() ?? '';
    final result = SallaWhatsappOtpRequest(
      requestId: cleanRequestId,
      status: status,
      phoneMasked: value['phoneMasked']?.toString() ?? '',
      resendSeconds:
          int.tryParse(value['resendSeconds']?.toString() ?? '') ?? 30,
      retryAfterSeconds:
          int.tryParse(value['retryAfterSeconds']?.toString() ?? '') ?? 0,
      expiresAtMs: int.tryParse(value['expiresAtMs']?.toString() ?? '') ?? 0,
      deliveryUncertain:
          value['deliveryUncertain'] == true || status == 'delivery_unknown',
    );
    if (status == 'sent' || status == 'delivery_unknown') return result;
    if (status == 'rate_limited') {
      final seconds = result.retryAfterSeconds <= 0
          ? result.resendSeconds
          : result.retryAfterSeconds;
      throw SallaWhatsappOtpException(
        'يمكن إعادة إرسال رمز واتساب بعد $seconds ثانية.',
        reason: 'rate_limited',
        retryAfterSeconds: seconds,
      );
    }
    if (status == 'failed') {
      throw SallaWhatsappOtpException(
        _whatsappOtpErrorMessage(status, value['error']?.toString() ?? ''),
        reason: value['error']?.toString() ?? status,
      );
    }
    throw const SallaWhatsappOtpException(
      'لم يحسم الخادم نتيجة إرسال رمز واتساب. '
      'سنعيد فحص المحاولة نفسها دون إرسال رسالة جديدة.',
      reason: 'otp_request_pending',
      resultUncertain: true,
    );
  }

  static Future<SallaIdentity> verifyCustomerWhatsappOtp({
    required String phone,
    required String requestId,
    required String code,
    required String verificationId,
    required SallaWhatsappOtpSource source,
  }) async {
    final normalizedPhone = normalizeIraqiPhone(phone);
    final cleanRequestId = requestId.trim();
    final cleanVerificationId = verificationId.trim();
    final cleanCode = code
        .split('')
        .map(_normalizePhoneDigit)
        .join()
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^\+9647[0-9]{9}$').hasMatch(normalizedPhone) ||
        cleanRequestId.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(cleanVerificationId) ||
        !RegExp(r'^[0-9]{6}$').hasMatch(cleanCode)) {
      throw StateError('أدخل رقم الهاتف والرمز بشكل صحيح.');
    }
    Map<String, dynamic> value;
    try {
      final callable = _functions.httpsCallable(
        'whatsappOtpVerificationOperations',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      final result = await callable.call<dynamic>(<String, dynamic>{
        'verificationId': cleanVerificationId,
        'requestId': cleanRequestId,
        'phone': normalizedPhone,
        'code': cleanCode,
        'source': source.value,
      });
      value = _databaseMap(result.data);
    } on FirebaseFunctionsException catch (error) {
      throw _callableOtpException(error);
    }
    final status = value['status']?.toString() ?? '';
    if (status != 'verified') {
      throw SallaWhatsappOtpException(
        _whatsappOtpErrorMessage(status, value['error']?.toString() ?? ''),
        reason: value['error']?.toString() ?? status,
      );
    }

    final customToken = value['customToken']?.toString() ?? '';
    if (customToken.isEmpty) {
      throw StateError(
        'تم التحقق من الرمز، لكن لم تصل جلسة الدخول من السيرفر. حاول مرة أخرى.',
      );
    }
    final credential = await _auth
        .signInWithCustomToken(customToken)
        .timeout(const Duration(seconds: 30));
    final user = credential.user;
    if (user == null) {
      throw StateError('تعذر فتح جلسة الزبون بعد تحقق واتساب.');
    }
    final identity = await resolveIdentity(
      user: user,
      expectedRole: SallaUserRole.customer,
      allowFirstAdminBootstrap: false,
    );
    if (identity == null) {
      throw StateError('تم التحقق، لكن تعذر تحميل حساب الزبون.');
    }
    return identity;
  }

  static bool roleUsesCodeLogin(SallaUserRole role) {
    return role == SallaUserRole.driver ||
        role == SallaUserRole.store ||
        role == SallaUserRole.admin;
  }

  static String _localSessionKey(SallaUserRole role) {
    return 'salla_code_identity_${role.value}';
  }

  static String _savedLoginKey(SallaUserRole role) {
    return 'salla_saved_login_${role.value}';
  }

  static String _localRetryIntentPart(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 256) {
      throw ArgumentError.value(value, label, 'قيمة التخزين المحلي غير صالحة');
    }
    return base64Url.encode(utf8.encode(normalized)).replaceAll('=', '');
  }

  static String _localRetryIntentPrefix({
    required SallaUserRole role,
    required String environment,
    required String ownerUid,
    required String namespace,
  }) {
    return <String>[
      _localRetryIntentKeyPrefix,
      _localRetryIntentPart(environment, 'environment'),
      role.value,
      _localRetryIntentPart(ownerUid, 'ownerUid'),
      _localRetryIntentPart(namespace, 'namespace'),
    ].join('|');
  }

  static String _localRetryIntentKey({
    required SallaUserRole role,
    required String environment,
    required String ownerUid,
    required String namespace,
    required String intentId,
  }) {
    return <String>[
      _localRetryIntentPrefix(
        role: role,
        environment: environment,
        ownerUid: ownerUid,
        namespace: namespace,
      ),
      _localRetryIntentPart(intentId, 'intentId'),
    ].join('|');
  }

  /// Persists an outcome-uncertain trusted mutation before it is sent.
  ///
  /// This reuses the package's existing local storage and is deliberately
  /// scoped by role and Firebase UID. It is not a server receipt; callers must
  /// remove it only after the trusted server operation confirms success.
  static Future<void> saveLocalRetryIntent({
    required SallaUserRole role,
    required String environment,
    required String ownerUid,
    required String namespace,
    required String intentId,
    required Map<String, Object?> payload,
  }) async {
    final key = _localRetryIntentKey(
      role: role,
      environment: environment,
      ownerUid: ownerUid,
      namespace: namespace,
      intentId: intentId,
    );
    final record = <String, Object?>{
      'version': 1,
      'environment': environment.trim(),
      'role': role.value,
      'ownerUid': ownerUid.trim(),
      'namespace': namespace.trim(),
      'intentId': intentId.trim(),
      'savedAtMs': DateTime.now().millisecondsSinceEpoch,
      'payload': payload,
    };
    final encoded = jsonEncode(record);
    final prefs = await SharedPreferences.getInstance().timeout(
      _localIdentityStorageTimeout,
    );
    final saved = await prefs
        .setString(key, encoded)
        .timeout(_localIdentityStorageTimeout);
    if (!saved) {
      throw StateError('تعذر حفظ معرّف إعادة المحاولة محلياً.');
    }
  }

  /// Loads every retry intent in one trusted-mutation namespace.
  /// Malformed or cross-account records are discarded locally.
  static Future<Map<String, Map<String, dynamic>>> loadLocalRetryIntents({
    required SallaUserRole role,
    required String environment,
    required String ownerUid,
    required String namespace,
    Duration maxAge = const Duration(days: 90),
    DateTime? now,
  }) async {
    if (maxAge <= Duration.zero) {
      throw ArgumentError.value(maxAge, 'maxAge', 'يجب أن تكون موجبة');
    }
    final environmentRolePrefix = <String>[
      _localRetryIntentKeyPrefix,
      _localRetryIntentPart(environment, 'environment'),
      role.value,
    ].join('|');
    final prefs = await SharedPreferences.getInstance().timeout(
      _localIdentityStorageTimeout,
    );
    final result = <String, Map<String, dynamic>>{};
    final malformedKeys = <String>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('$environmentRolePrefix|')) continue;
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) {
        malformedKeys.add(key);
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException();
        final record = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final intentId = record['intentId']?.toString().trim() ?? '';
        final payload = record['payload'];
        final savedAtMs = record['savedAtMs'];
        final currentMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
        if (record['version'] != 1 ||
            record['environment']?.toString() != environment.trim() ||
            record['role']?.toString() != role.value) {
          throw const FormatException();
        }
        if (record['namespace']?.toString() != namespace.trim()) continue;
        if (record['ownerUid']?.toString() != ownerUid.trim()) {
          malformedKeys.add(key);
          continue;
        }
        if (intentId.isEmpty ||
            savedAtMs is! int ||
            savedAtMs <= 0 ||
            savedAtMs > currentMs + const Duration(minutes: 5).inMilliseconds ||
            currentMs - savedAtMs > maxAge.inMilliseconds ||
            payload is! Map) {
          throw const FormatException();
        }
        final expectedKey = _localRetryIntentKey(
          role: role,
          environment: environment,
          ownerUid: ownerUid,
          namespace: namespace,
          intentId: intentId,
        );
        if (expectedKey != key) throw const FormatException();
        result[intentId] = payload.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      } catch (_) {
        malformedKeys.add(key);
      }
    }
    for (final key in malformedKeys) {
      await prefs.remove(key).timeout(_localIdentityStorageTimeout);
    }
    return result;
  }

  static Future<void> removeLocalRetryIntent({
    required SallaUserRole role,
    required String environment,
    required String ownerUid,
    required String namespace,
    required String intentId,
  }) async {
    final key = _localRetryIntentKey(
      role: role,
      environment: environment,
      ownerUid: ownerUid,
      namespace: namespace,
      intentId: intentId,
    );
    final prefs = await SharedPreferences.getInstance().timeout(
      _localIdentityStorageTimeout,
    );
    final removed =
        await prefs.remove(key).timeout(_localIdentityStorageTimeout);
    if (!removed && prefs.containsKey(key)) {
      throw StateError('تعذر حذف معرّف إعادة المحاولة المحلي.');
    }
  }

  static Future<User?> _currentFirebaseUser() async {
    final current = _auth.currentUser;
    if (current != null) return current;
    try {
      return await _auth
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return _auth.currentUser;
    }
  }

  static Future<User> _ensureCodeLoginFirebaseUser() async {
    final current = await _currentFirebaseUser();
    if (current != null && current.isAnonymous) return current;
    if (current != null && !current.isAnonymous) {
      await _auth.signOut();
    }
    final credential = await _auth.signInAnonymously();
    final user = credential.user;
    if (user == null) {
      throw StateError(
          'تعذر إنشاء جلسة دخول آمنة. أعد فتح التطبيق وحاول مرة أخرى.');
    }
    return user;
  }

  static Future<SallaIdentity?> loadLocalIdentity(SallaUserRole role) async {
    if (!roleUsesCodeLogin(role)) return null;
    final prefs = await SharedPreferences.getInstance().timeout(
      _localIdentityStorageTimeout,
    );
    Future<void> removeStoredIdentity() async {
      try {
        await prefs
            .remove(_localSessionKey(role))
            .timeout(_localIdentityStorageTimeout);
      } catch (_) {
        // A stale record is harmless; the caller must still leave loading state.
      }
    }

    final raw = prefs.getString(_localSessionKey(role));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      final uid = data['uid']?.toString() ?? '';
      if (uid.isEmpty) {
        await removeStoredIdentity();
        return null;
      }
      final authUser = await _currentFirebaseUser();
      if (authUser == null || authUser.uid != uid) {
        await removeStoredIdentity();
        return null;
      }
      final identity = SallaIdentity.fromMap(uid, data);
      return identity.role == role ? identity : null;
    } catch (_) {
      await removeStoredIdentity();
      return null;
    }
  }

  static Future<SallaIdentity> validateLocalIdentity(
    SallaIdentity localIdentity, {
    bool allowDriverOperationalBlock = false,
  }) async {
    final user = await _currentFirebaseUser();
    if (user == null || user.uid != localIdentity.uid) {
      throw StateError('انتهت جلسة الدخول المحلية. سجل الدخول من جديد.');
    }
    final entityCollection = switch (localIdentity.role) {
      SallaUserRole.driver => 'drivers',
      SallaUserRole.store => 'stores',
      SallaUserRole.admin => 'employees',
      SallaUserRole.customer => 'customers',
    };
    // These records are independent once the signed local identity is known.
    // Reading them together removes two avoidable network round trips from
    // every warm launch without weakening any of the checks below.
    final snapshots = await Future.wait<DataSnapshot>([
      _database
          .child('userRoleProfiles')
          .child(user.uid)
          .child(localIdentity.role.value)
          .get(),
      _database.child('userProfiles').child(user.uid).get(),
      _database.child(entityCollection).child(localIdentity.entityId).get(),
    ]);
    final roleValue = snapshots[0].value;
    final roleIdentity = roleValue is Map
        ? SallaIdentity.fromMap(
            user.uid,
            roleValue.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : null;
    if (roleIdentity == null) {
      throw StateError('تعذر العثور على صلاحية الجلسة المحلية.');
    }
    if (roleIdentity.entityId != localIdentity.entityId) {
      throw StateError('صلاحية الجلسة المحلية مرتبطة بسجل آخر.');
    }
    if (!roleIdentity.active) {
      throw const SallaAccountBlockedException(
        'هذا الحساب موقوف من الإدارة.',
      );
    }
    final profileValue = snapshots[1].value;
    if (profileValue is! Map) {
      throw StateError('ملف الحساب المرتبط بالجلسة غير موجود.');
    }
    if (profileValue['active'] == false) {
      throw const SallaAccountBlockedException(
        'هذا الحساب موقوف من الإدارة.',
      );
    }
    await _verifyEntityOwnership(
      user: user,
      identity: roleIdentity,
      allowDriverOperationalBlock: allowDriverOperationalBlock,
      prefetchedEntityValue: snapshots[2].value,
      hasPrefetchedEntityValue: true,
    );
    return roleIdentity;
  }

  static Future<void> saveLocalIdentity(SallaIdentity identity) async {
    if (!roleUsesCodeLogin(identity.role)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _localSessionKey(identity.role),
      jsonEncode(identity.toMap()),
    );
  }

  static String normalizeCustomerDisplayName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Future<SallaIdentity> updateCustomerDisplayName({
    required SallaIdentity identity,
    required String displayName,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != identity.uid) {
      throw StateError('انتهت جلسة الحساب. أعد فتح التطبيق وحاول مرة أخرى.');
    }
    if (identity.role != SallaUserRole.customer ||
        identity.entityId != user.uid ||
        !identity.active) {
      throw StateError('هوية الزبون غير صالحة لتحديث الاسم.');
    }

    final normalizedName = normalizeCustomerDisplayName(displayName);
    if (normalizedName.length < 2 || normalizedName.length > 60) {
      throw StateError('اكتب اسماً واضحاً من حرفين إلى 60 حرفاً.');
    }

    final currentIdentity = await _loadRoleIdentity(
      user.uid,
      SallaUserRole.customer,
    );
    if (currentIdentity == null ||
        !currentIdentity.active ||
        currentIdentity.uid != user.uid ||
        currentIdentity.entityId != user.uid) {
      throw StateError('تعذر تثبيت هوية الزبون. أعد فتح التطبيق وحاول مجدداً.');
    }

    final now = DateTime.now().toIso8601String();
    await _database.update(<String, Object?>{
      'userRoleProfiles/${user.uid}/${SallaUserRole.customer.value}/name':
          normalizedName,
      'userRoleProfiles/${user.uid}/${SallaUserRole.customer.value}/updatedAt':
          now,
      'userProfiles/${user.uid}/name': normalizedName,
      'userProfiles/${user.uid}/updatedAt': now,
      'customers/${user.uid}/name': normalizedName,
      'customers/${user.uid}/updatedAt': now,
    });

    try {
      await user.updateDisplayName(normalizedName);
      await user.reload();
    } catch (_) {
      // The three canonical database identities above are the source of truth.
    }

    return SallaIdentity(
      uid: identity.uid,
      role: identity.role,
      entityId: identity.entityId,
      name: normalizedName,
      phone: identity.phone,
      email: identity.email,
      active: identity.active,
    );
  }

  static Future<void> clearLocalSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localSessionKey(SallaUserRole.driver));
    await prefs.remove(_localSessionKey(SallaUserRole.store));
    await prefs.remove(_localSessionKey(SallaUserRole.admin));
    await prefs.remove(_localSessionKey(SallaUserRole.customer));
    final retryIntentKeys = prefs
        .getKeys()
        .where((key) => key.startsWith('$_localRetryIntentKeyPrefix|'))
        .toList(growable: false);
    for (final key in retryIntentKeys) {
      await prefs.remove(key);
    }
  }

  static Future<SallaSavedLogin?> loadSavedLogin(SallaUserRole role) async {
    final prefs = await SharedPreferences.getInstance().timeout(
      _localIdentityStorageTimeout,
    );
    final storageKey = _savedLoginKey(role);
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      final containsLegacyAccessCodes =
          data.containsKey('linkCode') || data.containsKey('loginCode');
      data.remove('linkCode');
      data.remove('loginCode');
      final saved = SallaSavedLogin.fromMap(data);
      if (saved.role != role || !saved.hasUsableData) {
        await prefs.remove(storageKey).timeout(_localIdentityStorageTimeout);
        return null;
      }
      if (containsLegacyAccessCodes) {
        await prefs
            .setString(storageKey, jsonEncode(saved.toMap()))
            .timeout(_localIdentityStorageTimeout);
      }
      return saved;
    } catch (_) {
      try {
        await prefs.remove(storageKey).timeout(_localIdentityStorageTimeout);
      } catch (_) {
        // Failure to clean a malformed optional hint must not block login.
      }
      return null;
    }
  }

  static Future<void> saveLoginCredentials(SallaSavedLogin savedLogin) async {
    final prefs = await SharedPreferences.getInstance().timeout(
      _localIdentityStorageTimeout,
    );
    final storageKey = _savedLoginKey(savedLogin.role);
    if (!savedLogin.hasUsableData) {
      await prefs.remove(storageKey).timeout(_localIdentityStorageTimeout);
      return;
    }
    await prefs
        .setString(
          storageKey,
          jsonEncode(savedLogin.toMap()),
        )
        .timeout(_localIdentityStorageTimeout);
  }

  static Future<void> clearSavedLogin(SallaUserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedLoginKey(role));
  }

  static String collectionForRole(SallaUserRole role) {
    return switch (role) {
      SallaUserRole.driver => 'drivers',
      SallaUserRole.store => 'stores',
      SallaUserRole.admin => 'employees',
      SallaUserRole.customer => 'customers',
    };
  }

  static Future<SallaIdentity> _linkWithCodeOnServer({
    required User user,
    required SallaUserRole role,
    required String requestedName,
    required String phone,
    required String linkCode,
    String loginCode = '',
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('linkAccountWithCode');
      final result = await callable.call(<String, dynamic>{
        'role': role.value,
        'requestedName': requestedName.trim(),
        'phone': phone,
        'linkCode': linkCode,
        if (loginCode.isNotEmpty) 'loginCode': loginCode,
      });
      final response = _databaseMap(result.data);
      final identityValue = response['identity'];
      final identityMap = _databaseMap(identityValue);
      if (identityMap.isEmpty) {
        throw StateError('تعذر تحميل هوية الحساب بعد التحقق.');
      }
      final identity = SallaIdentity.fromMap(user.uid, identityMap);
      if (identity.role != role || identity.uid != user.uid) {
        throw StateError('استجابة ربط الحساب غير متطابقة.');
      }
      await saveLocalIdentity(identity);
      return identity;
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'failed-precondition' &&
          error.message?.trim().isNotEmpty == true) {
        throw SallaAccountBlockedException(error.message!.trim());
      }
      if (role == SallaUserRole.admin &&
          (error.code == 'permission-denied' ||
              error.code == 'invalid-argument')) {
        throw StateError('ADMIN_CODE_LOGIN_FAILED');
      }
      if (error.code == 'permission-denied' ||
          error.code == 'invalid-argument') {
        throw StateError('بيانات الدخول غير صحيحة أو تم إيقافها من الإدارة.');
      }
      if (error.code == 'internal' ||
          error.code == 'unavailable' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'resource-exhausted') {
        throw StateError(
          'تعذر الوصول إلى خدمة الدخول الآن. حاول مرة أخرى بعد قليل.',
        );
      }
      throw StateError(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'تعذر التحقق من بيانات الدخول. حاول مرة أخرى.',
      );
    }
  }

  static Future<SallaIdentity> signInWithLinkCode({
    required SallaUserRole role,
    required String requestedName,
    required String phone,
    required String linkCode,
    String loginCode = '',
  }) async {
    if (!roleUsesCodeLogin(role)) {
      throw StateError('هذا النوع من الحسابات لا يستخدم الدخول بالرمز.');
    }
    final code = normalizeLinkCode(linkCode);
    final adminLoginCode = normalizeLinkCode(loginCode);
    if (code.length < 4) {
      throw StateError('اكتب رمز الدخول الذي أعطته لك الإدارة.');
    }
    if (role == SallaUserRole.admin && adminLoginCode.length < 4) {
      throw StateError('اكتب رمز دخول الحساب الإداري.');
    }
    final normalizedPhone = normalizeIraqiPhone(phone);
    final enteredPhoneDigits = normalizePhoneDigits(normalizedPhone);
    if (!normalizedPhone.startsWith('+') || enteredPhoneDigits.length < 10) {
      throw StateError('أدخل رقم هاتف صحيح مع رمز الدولة.');
    }

    final authUser = await _ensureCodeLoginFirebaseUser();
    return _linkWithCodeOnServer(
      user: authUser,
      role: role,
      requestedName: requestedName,
      phone: normalizedPhone,
      linkCode: code,
      loginCode: adminLoginCode,
    );
  }

  static Future<SallaIdentity?> _loadRoleIdentity(
    String uid,
    SallaUserRole role,
  ) async {
    final snapshot = await _database
        .child('userRoleProfiles')
        .child(uid)
        .child(role.value)
        .get();
    final value = snapshot.value;
    if (value is! Map) return null;
    return SallaIdentity.fromMap(
      uid,
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  static Future<void> _activateRoleSession({
    required User user,
    required SallaIdentity identity,
    required String now,
  }) async {
    await _database.child('userProfiles').child(user.uid).set({
      ...identity.toMap(),
      'phone': user.phoneNumber ?? identity.phone,
      'email': user.email ?? identity.email,
      'updatedAt': now,
      'lastSeenAt': now,
    });
  }

  static Future<void> _saveRoleMembership(
    SallaIdentity identity, {
    required User user,
    required String now,
  }) async {
    await _database
        .child('userRoleProfiles')
        .child(user.uid)
        .child(identity.role.value)
        .update({
      ...identity.toMap(),
      'phone': user.phoneNumber ?? identity.phone,
      'email': user.email ?? identity.email,
      'updatedAt': now,
    });
  }

  static Future<void> _touchAccountProfile(
    User user, {
    required SallaIdentity identity,
    required String now,
  }) async {
    if (!identity.active || identity.uid != user.uid) return;
    try {
      final activeRole = await _loadRoleIdentity(user.uid, identity.role);
      if (activeRole == null ||
          !activeRole.active ||
          activeRole.uid != user.uid ||
          activeRole.entityId != identity.entityId) {
        return;
      }
      final displayName = user.displayName?.trim() ?? '';
      final phone = user.phoneNumber?.trim() ?? '';
      final email = user.email?.trim() ?? '';
      await _database.child('accountProfiles').child(user.uid).update({
        'uid': user.uid,
        if (phone.isNotEmpty) 'phone': phone,
        if (email.isNotEmpty) 'email': email,
        if (displayName.isNotEmpty) 'name': displayName,
        'active': true,
        'lastLinkedRole': identity.role.value,
        'lastLinkedEntityId': identity.entityId,
        'lastLinkedName': identity.name,
        'updatedAt': now,
        'lastSeenAt': now,
      });
    } catch (_) {
      // The role membership record remains the source of truth.
    }
  }

  static Future<SallaIdentity> _ensureCustomerIdentity({
    required User user,
    required String now,
  }) async {
    final identity = SallaIdentity(
      uid: user.uid,
      role: SallaUserRole.customer,
      entityId: user.uid,
      name: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : 'عميل سلة',
      phone: user.phoneNumber ?? '',
      email: user.email ?? '',
    );
    await _database.update({
      'userRoleProfiles/${user.uid}/${SallaUserRole.customer.value}': {
        ...identity.toMap(),
        'createdAt': now,
        'updatedAt': now,
      },
      'customers/${user.uid}': {
        'id': user.uid,
        'authUid': user.uid,
        'name': identity.name,
        'phone': identity.phone,
        'email': identity.email,
        'active': true,
        'createdAt': now,
        'updatedAt': now,
      },
    });
    await _activateRoleSession(user: user, identity: identity, now: now);
    await _touchAccountProfile(user, identity: identity, now: now);
    return identity;
  }

  static Future<SallaIdentity?> _linkIdentityFromInvitation({
    required User user,
    required SallaUserRole expectedRole,
    required String pendingLinkCode,
    required String pendingDisplayName,
  }) async {
    if (expectedRole == SallaUserRole.customer ||
        expectedRole == SallaUserRole.admin) {
      return null;
    }
    final code = normalizeLinkCode(pendingLinkCode);
    if (code.isEmpty) return null;
    return _linkWithCodeOnServer(
      user: user,
      role: expectedRole,
      requestedName: pendingDisplayName,
      phone: user.phoneNumber ?? '',
      linkCode: code,
    );
  }

  static Future<SallaIdentity?> _bootstrapFirstAdmin({
    required User user,
    required String now,
  }) async {
    final bootstrapRef =
        _database.child('system').child('bootstrap').child('adminUid');
    var bootstrapUid = (await bootstrapRef.get()).value?.toString() ?? '';
    if (bootstrapUid.isEmpty) {
      try {
        await bootstrapRef.set(user.uid);
        bootstrapUid = user.uid;
      } catch (_) {
        bootstrapUid = (await bootstrapRef.get()).value?.toString() ?? '';
      }
    }
    if (bootstrapUid != user.uid) return null;

    final employeeId = employeeIdForUid(user.uid);
    final identity = SallaIdentity(
      uid: user.uid,
      role: SallaUserRole.admin,
      entityId: employeeId,
      name: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : 'المدير العام',
      phone: user.phoneNumber ?? '',
      email: user.email ?? '',
    );
    await _database.update({
      'userRoleProfiles/${user.uid}/${SallaUserRole.admin.value}': {
        ...identity.toMap(),
        'createdAt': now,
        'updatedAt': now,
      },
      'userProfiles/${user.uid}': {
        ...identity.toMap(),
        'createdAt': now,
        'updatedAt': now,
        'lastSeenAt': now,
      },
      'employees/$employeeId/authUid': user.uid,
      'employees/$employeeId/id': employeeId,
      'employees/$employeeId/name': identity.name,
      'employees/$employeeId/role': 'admin',
      'employees/$employeeId/roleTitle': 'مدير عام',
      'employees/$employeeId/active': true,
      'employees/$employeeId/email': identity.email,
      'employees/$employeeId/createdAt': now,
      'employees/$employeeId/updatedAt': now,
    });
    await _touchAccountProfile(user, identity: identity, now: now);
    return identity;
  }

  static Future<SallaIdentity?> resolveIdentity({
    required User user,
    required SallaUserRole expectedRole,
    required bool allowFirstAdminBootstrap,
    String pendingLinkCode = '',
    String pendingDisplayName = '',
  }) {
    return _resolveIdentity(
      user: user,
      expectedRole: expectedRole,
      allowFirstAdminBootstrap: allowFirstAdminBootstrap,
      pendingLinkCode: pendingLinkCode,
      pendingDisplayName: pendingDisplayName,
    ).timeout(_identityResolutionTimeout);
  }

  static Future<SallaIdentity?> _resolveIdentity({
    required User user,
    required SallaUserRole expectedRole,
    required bool allowFirstAdminBootstrap,
    String pendingLinkCode = '',
    String pendingDisplayName = '',
  }) async {
    final now = DateTime.now().toIso8601String();
    final roleIdentity = await _loadRoleIdentity(user.uid, expectedRole);
    if (roleIdentity != null) {
      if (!roleIdentity.active) {
        throw const SallaAccountBlockedException(
          'هذا الحساب موقوف من الإدارة.',
        );
      }
      await _activateRoleSession(
        user: user,
        identity: roleIdentity,
        now: now,
      );
      await _verifyEntityOwnership(user: user, identity: roleIdentity);
      await _touchAccountProfile(user, identity: roleIdentity, now: now);
      return roleIdentity;
    }

    if (expectedRole == SallaUserRole.admin && allowFirstAdminBootstrap) {
      final identity = await _bootstrapFirstAdmin(user: user, now: now);
      if (identity != null) return identity;
    }

    final profileRef = _database.child('userProfiles').child(user.uid);
    final profileSnapshot = await profileRef.get();
    final profileValue = profileSnapshot.value;

    if (profileValue is Map) {
      final profile = profileValue.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final identity = SallaIdentity.fromMap(user.uid, profile);
      unawaited(
        _saveRoleMembership(
          identity,
          user: user,
          now: now,
        ).catchError((_) {}),
      );
      if (identity.role != expectedRole) {
        if (expectedRole == SallaUserRole.customer) {
          if (user.isAnonymous) return null;
          return _ensureCustomerIdentity(user: user, now: now);
        }
        final linked = await _linkIdentityFromInvitation(
          user: user,
          expectedRole: expectedRole,
          pendingLinkCode: pendingLinkCode,
          pendingDisplayName: pendingDisplayName,
        );
        if (linked != null) {
          await _verifyEntityOwnership(user: user, identity: linked);
          await _touchAccountProfile(user, identity: linked, now: now);
          return linked;
        }
        await ensureAccessRequest(
          user: user,
          requestedRole: expectedRole,
          linkCode: pendingLinkCode,
          requestedName: pendingDisplayName,
        );
        return null;
      }
      if (identity.role != expectedRole) {
        throw StateError(
          'هذا الحساب مرتبط بدور ${identity.role.arabicLabel} ولا يمكن فتح تطبيق ${expectedRole.arabicLabel}.',
        );
      }
      if (!identity.active) {
        throw const SallaAccountBlockedException(
          'هذا الحساب موقوف من الإدارة.',
        );
      }
      await _verifyEntityOwnership(
        user: user,
        identity: identity,
      );
      await _touchAccountProfile(user, identity: identity, now: now);
      unawaited(
        profileRef.update({
          'lastSeenAt': DateTime.now().toIso8601String(),
          'email': user.email ?? identity.email,
          'phone': user.phoneNumber ?? identity.phone,
        }),
      );
      return identity;
    }

    if (expectedRole == SallaUserRole.customer) {
      if (user.isAnonymous) return null;
      return _ensureCustomerIdentity(user: user, now: now);
    }

    if (expectedRole == SallaUserRole.customer) {
      final identity = SallaIdentity(
        uid: user.uid,
        role: SallaUserRole.customer,
        entityId: user.uid,
        name: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'عميل سلة',
        phone: user.phoneNumber ?? '',
        email: user.email ?? '',
      );
      final now = DateTime.now().toIso8601String();
      await _database.update({
        'userRoleProfiles/${user.uid}/${SallaUserRole.customer.value}': {
          ...identity.toMap(),
          'createdAt': now,
          'updatedAt': now,
        },
        'userProfiles/${user.uid}': {
          ...identity.toMap(),
          'createdAt': now,
          'updatedAt': now,
          'lastSeenAt': now,
        },
        'customers/${user.uid}': {
          'id': user.uid,
          'authUid': user.uid,
          'name': identity.name,
          'phone': identity.phone,
          'email': identity.email,
          'active': true,
          'createdAt': now,
          'updatedAt': now,
        },
      });
      return identity;
    }

    if (expectedRole == SallaUserRole.admin && allowFirstAdminBootstrap) {
      final identity = await _bootstrapFirstAdmin(user: user, now: now);
      if (identity != null) return identity;
    }

    final linked = await _linkIdentityFromInvitation(
      user: user,
      expectedRole: expectedRole,
      pendingLinkCode: pendingLinkCode,
      pendingDisplayName: pendingDisplayName,
    );
    if (linked != null) {
      await _verifyEntityOwnership(user: user, identity: linked);
      await _touchAccountProfile(user, identity: linked, now: now);
      return linked;
    }

    await ensureAccessRequest(
      user: user,
      requestedRole: expectedRole,
      linkCode: pendingLinkCode,
      requestedName: pendingDisplayName,
    );
    return null;
  }

  static Future<void> _verifyEntityOwnership({
    required User user,
    required SallaIdentity identity,
    bool allowDriverOperationalBlock = false,
    Object? prefetchedEntityValue,
    bool hasPrefetchedEntityValue = false,
  }) async {
    if (identity.role == SallaUserRole.customer) {
      if (identity.entityId != user.uid) {
        final roleSnapshot = await _database
            .child('userRoleProfiles')
            .child(user.uid)
            .child(SallaUserRole.customer.value)
            .get();
        final roleValue = roleSnapshot.value;
        final roleData = roleValue is Map
            ? roleValue.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{};
        if (roleData['active'] != true ||
            roleData['uid']?.toString() != user.uid ||
            roleData['entityId']?.toString() != identity.entityId) {
          throw StateError('معرّف الزبون لا يطابق حساب تسجيل الدخول.');
        }
        final customerSnapshot =
            await _database.child('customers').child(identity.entityId).get();
        final customerValue = customerSnapshot.value;
        if (customerValue is! Map || customerValue['active'] == false) {
          throw StateError('سجل الزبون غير مرتبط بهذا الحساب أو أنه موقوف.');
        }
        return;
      }
      final customerRef = _database.child('customers').child(user.uid);
      final customerSnapshot = await customerRef.get();
      if (!customerSnapshot.exists) {
        final now = DateTime.now().toIso8601String();
        await customerRef.set({
          'id': user.uid,
          'authUid': user.uid,
          'name': identity.name,
          'phone': user.phoneNumber ?? identity.phone,
          'email': user.email ?? identity.email,
          'active': true,
          'createdAt': now,
          'updatedAt': now,
        });
        return;
      }
      final value = customerSnapshot.value;
      if (value is! Map ||
          value['authUid']?.toString() != user.uid ||
          value['active'] == false) {
        throw StateError('سجل الزبون غير مرتبط بهذا الحساب أو أنه موقوف.');
      }
      return;
    }

    final collection = switch (identity.role) {
      SallaUserRole.driver => 'drivers',
      SallaUserRole.store => 'stores',
      SallaUserRole.admin => 'employees',
      SallaUserRole.customer => 'customers',
    };
    final value = hasPrefetchedEntityValue
        ? prefetchedEntityValue
        : (await _database.child(collection).child(identity.entityId).get())
            .value;
    if (value is! Map) {
      throw StateError('السجل التشغيلي المرتبط بالحساب غير موجود.');
    }
    if (value['authUid']?.toString() != user.uid) {
      throw StateError('هذا السجل التشغيلي مرتبط بحساب آخر.');
    }
    if (!sallaEntityRecordAllowsBoundSession(
      value,
      role: identity.role,
      allowDriverOperationalBlock: allowDriverOperationalBlock,
    )) {
      throw SallaAccountBlockedException(
        sallaOperationalBlockMessage(value),
      );
    }
  }

  static Future<String> _requestedDisplayName(User user) async {
    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    try {
      final snapshot = await _database
          .child('accountProfiles')
          .child(user.uid)
          .child('requestedName')
          .get();
      return snapshot.value?.toString().trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> ensureAccessRequest({
    required User user,
    required SallaUserRole requestedRole,
    String linkCode = '',
    String requestedName = '',
  }) async {
    final requestId = accessRequestIdFor(user.uid, requestedRole);
    final requestRef = _database.child('accessRequests').child(requestId);
    final storedRequestedName = requestedName.trim().isNotEmpty
        ? requestedName.trim()
        : await _requestedDisplayName(user);
    final normalizedLinkCode = normalizeLinkCode(linkCode);
    final current = await requestRef.get();
    if (current.exists) {
      final value = current.value;
      if (value is Map && value['status']?.toString() != 'rejected') {
        final currentName = value['name']?.toString().trim() ?? '';
        final currentLinkCode = normalizeLinkCode(
          value['linkCode']?.toString() ?? '',
        );
        final linkCodeChanged = normalizedLinkCode.isNotEmpty &&
            normalizedLinkCode != currentLinkCode;
        if (storedRequestedName.isNotEmpty && currentName.isEmpty) {
          await requestRef.update({
            'name': storedRequestedName,
            if (normalizedLinkCode.isNotEmpty) 'linkCode': normalizedLinkCode,
            if (linkCodeChanged) ...{
              'entityId': null,
              'employeeId': null,
              'provinceId': null,
              'branchId': null,
              'agencyId': null,
              'reviewBranchId': null,
              'reviewAgencyId': null,
              'accessScopeStatus': null,
              'accessScopeReason': null,
              'accessScopeVersion': null,
              'accessScopeSourceFingerprint': null,
              'accessScopeUpdatedAt': null,
            },
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
        return;
      }
    }
    final now = DateTime.now().toIso8601String();
    await requestRef.set({
      'requestId': requestId,
      'uid': user.uid,
      'requestedRole': requestedRole.value,
      'name': storedRequestedName,
      'phone': user.phoneNumber ?? '',
      'email': user.email ?? '',
      if (normalizedLinkCode.isNotEmpty) 'linkCode': normalizedLinkCode,
      'status': 'pending',
      'createdAt': now,
      'updatedAt': now,
    });
  }
}

class SallaAppErrorReporter {
  SallaAppErrorReporter._();

  static const Duration _dedupeWindow = Duration(minutes: 15);
  static const int _maxReportsPerWindow = 20;
  static const int _maxMessageLength = 600;
  static const int _maxFriendlyMessageLength = 200;
  static const int _maxStackLength = 2200;
  static const int _maxContextLength = 160;
  static bool _installed = false;
  static String _appName = '';
  static SallaUserRole? _role;
  static final Map<String, DateTime> _recentFingerprints = <String, DateTime>{};
  static final List<DateTime> _reportWindow = <DateTime>[];

  static void install({
    required String appName,
    required SallaUserRole role,
  }) {
    final requestedAppName = appName.trim();
    final canonicalAppName = _appNameForRole(role);
    _appName = requestedAppName == canonicalAppName
        ? requestedAppName
        : canonicalAppName;
    _role = role;
    if (_installed) return;
    _installed = true;

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previousFlutterHandler?.call(details);
      unawaited(
        report(
          message: details.exceptionAsString(),
          stackTrace: details.stack,
          screen: details.context?.toDescription() ?? '',
          fatal: false,
        ),
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(
        report(
          message: error.toString(),
          stackTrace: stack,
          screen: 'platform',
          fatal: true,
        ),
      );
      return false;
    };
  }

  static Future<void> report({
    required String message,
    StackTrace? stackTrace,
    String screen = '',
    String action = '',
    bool fatal = false,
  }) async {
    final currentUser = SallaAuthService.firebaseAuth.currentUser;
    final configuredRole = _role;
    if (currentUser == null || configuredRole == null) return;
    final userUid = currentUser.uid.trim();
    if (userUid.isEmpty) return;
    final appName =
        _appName.isEmpty ? _appNameForRole(configuredRole) : _appName;
    final role = configuredRole.value;
    final now = DateTime.now().toUtc();
    final cleanMessage = message.trim().isEmpty
        ? 'حدث خطأ غير معروف'
        : _limitText(message.trim(), _maxMessageLength);
    final cleanStack = stackTrace == null
        ? ''
        : _limitText(stackTrace.toString().trim(), _maxStackLength);
    final cleanScreen = _limitText(screen.trim(), _maxContextLength);
    final cleanAction = _limitText(action.trim(), _maxContextLength);
    final friendlyMessage = _limitText(
      _friendlyErrorMessage(cleanMessage),
      _maxFriendlyMessageLength,
    );
    final fingerprint = _errorFingerprint(
      '$appName|$role|$cleanScreen|$cleanAction|$cleanMessage|'
      '${cleanStack.split('\n').first}',
    );
    _recentFingerprints.removeWhere(
      (_, reportedAt) => now.difference(reportedAt) >= _dedupeWindow,
    );
    _reportWindow.removeWhere(
      (reportedAt) => now.difference(reportedAt) >= _dedupeWindow,
    );
    final lastReportedAt = _recentFingerprints[fingerprint];
    if (lastReportedAt != null &&
        now.difference(lastReportedAt) < _dedupeWindow) {
      return;
    }
    if (_reportWindow.length >= _maxReportsPerWindow) return;
    _recentFingerprints[fingerprint] = now;
    _reportWindow.add(now);
    try {
      await SallaAuthService.firebaseDatabase
          .ref()
          .child('appErrorLogs')
          .push()
          .set({
        'appName': appName,
        'role': role,
        'userUid': userUid,
        'screen': cleanScreen,
        'action': cleanAction,
        'fingerprint': fingerprint,
        'message': cleanMessage,
        'friendlyMessage': friendlyMessage,
        'stack': cleanStack,
        'fatal': fatal,
        'resolved': false,
        'createdAt': now.toIso8601String(),
        'createdAtServer': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Error logging must never break the app flow.
    }
  }

  static String _limitText(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    if (maxLength <= 3) return value.substring(0, maxLength);
    return '${value.substring(0, maxLength - 3)}...';
  }

  static String _appNameForRole(SallaUserRole role) {
    switch (role) {
      case SallaUserRole.customer:
        return 'تطبيق الزبون';
      case SallaUserRole.driver:
        return 'تطبيق السائق';
      case SallaUserRole.store:
        return 'تطبيق المتجر';
      case SallaUserRole.admin:
        return 'لوحة الإدارة';
    }
  }

  static String _errorFingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _friendlyErrorMessage(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('permission denied')) {
      return 'رفض صلاحية من قاعدة البيانات';
    }
    if (lower.contains('timeout')) {
      return 'انتهت مهلة الاتصال';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'مشكلة اتصال بالشبكة';
    }
    if (lower.contains('firebase')) {
      return 'خطأ في اتصال Firebase';
    }
    return 'حدث خطأ داخل التطبيق';
  }
}

class SallaAuthGate extends StatefulWidget {
  final SallaUserRole expectedRole;
  final SallaLoginMode loginMode;
  final Widget Function(BuildContext context, SallaIdentity identity)
      authenticatedBuilder;
  final bool allowRegistration;

  /// Optional public links provided by the host app, visible before sign-in.
  final Widget? loginFooter;
  final bool allowFirstAdminBootstrap;
  final bool allowDriverOperationalBlock;
  final Color primaryColor;
  final bool? customerWhatsappOtpEnabled;
  final SallaWhatsappOtpSource customerWhatsappOtpSource;
  final SallaWhatsappOtpRequestContextProvider?
      customerWhatsappOtpRequestContextProvider;

  const SallaAuthGate({
    super.key,
    required this.expectedRole,
    required this.loginMode,
    required this.authenticatedBuilder,
    this.allowRegistration = false,
    this.loginFooter,
    this.allowFirstAdminBootstrap = false,
    this.allowDriverOperationalBlock = false,
    this.primaryColor = const Color(0xFF0F766E),
    this.customerWhatsappOtpEnabled,
    this.customerWhatsappOtpSource = SallaWhatsappOtpSource.customerLogin,
    this.customerWhatsappOtpRequestContextProvider,
  });

  @override
  State<SallaAuthGate> createState() => _SallaAuthGateState();
}

class _SallaAuthGateState extends State<SallaAuthGate> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController(text: '+964');
  final codeController = TextEditingController();
  final requestedNameController = TextEditingController();
  final linkCodeController = TextEditingController();
  final loginCodeController = TextEditingController();
  String verificationId = '';
  String whatsappRequestOperationId = '';
  String whatsappRequestPhone = '';
  String whatsappRequestContextOperationId = '';
  SallaWhatsappOtpRequestContext? whatsappRequestContext;
  String whatsappVerificationOperationId = '';
  String whatsappVerificationOperationCode = '';
  String whatsappVerificationOperationRequestId = '';
  int? resendToken;
  Timer? whatsappResendTimer;
  final ValueNotifier<int> whatsappResendCountdownSeconds =
      ValueNotifier<int>(0);
  Timer? _phoneVerificationWatchdog;
  int _phoneVerificationAttempt = 0;
  DateTime? whatsappResendAvailableAt;
  DateTime? whatsappRequestExpiresAt;
  String errorText = '';
  bool busy = false;
  bool registerMode = false;
  bool localSessionLoaded = false;
  SallaIdentity? localIdentity;
  Object? localSessionError;
  SallaSavedLogin? savedLogin;
  bool savedLoginLoaded = false;
  int refreshRevision = 0;

  @override
  void initState() {
    super.initState();
    SallaAuthService.sessionRevision.addListener(handleSessionRevisionChanged);
    unawaited(loadLocalSession());
    unawaited(loadSavedLogin());
  }

  @override
  void dispose() {
    SallaAuthService.sessionRevision
        .removeListener(handleSessionRevisionChanged);
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    codeController.dispose();
    requestedNameController.dispose();
    linkCodeController.dispose();
    loginCodeController.dispose();
    whatsappResendTimer?.cancel();
    whatsappResendCountdownSeconds.dispose();
    _phoneVerificationAttempt += 1;
    _phoneVerificationWatchdog?.cancel();
    super.dispose();
  }

  bool get usesCodeLogin {
    return SallaAuthService.roleUsesCodeLogin(widget.expectedRole);
  }

  bool get usesCustomerWhatsappOtp {
    return widget.expectedRole == SallaUserRole.customer &&
        widget.loginMode == SallaLoginMode.phone &&
        (widget.customerWhatsappOtpEnabled ??
            SallaAuthService.customerWhatsappOtpEnabled);
  }

  int get whatsappResendRemainingSeconds {
    final availableAt = whatsappResendAvailableAt;
    if (availableAt == null) return 0;
    final remaining = availableAt.difference(DateTime.now()).inSeconds;
    return remaining <= 0 ? 0 : remaining;
  }

  void startWhatsappResendTimer(int seconds) {
    whatsappResendTimer?.cancel();
    whatsappResendAvailableAt = DateTime.now().add(
      Duration(seconds: seconds <= 0 ? 30 : seconds),
    );
    publishWhatsappResendRemaining();
    whatsappResendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      publishWhatsappResendRemaining();
      if (whatsappResendRemainingSeconds <= 0) timer.cancel();
    });
  }

  void publishWhatsappResendRemaining() {
    final remaining = whatsappResendRemainingSeconds;
    if (whatsappResendCountdownSeconds.value != remaining) {
      whatsappResendCountdownSeconds.value = remaining;
    }
  }

  void clearWhatsappResendTimer() {
    whatsappResendTimer?.cancel();
    whatsappResendTimer = null;
    whatsappResendAvailableAt = null;
    if (whatsappResendCountdownSeconds.value != 0) {
      whatsappResendCountdownSeconds.value = 0;
    }
  }

  void handleWhatsappPhoneInputChanged(String value) {
    final changed = SallaAuthService.whatsappOtpPhoneChanged(
      activePhone: whatsappRequestPhone,
      nextPhone: value,
    );
    if (!changed && errorText.isEmpty) return;
    if (changed) {
      clearWhatsappResendTimer();
      whatsappRequestOperationId = '';
      whatsappRequestPhone = '';
      whatsappRequestContextOperationId = '';
      whatsappRequestContext = null;
      whatsappRequestExpiresAt = null;
      verificationId = '';
      whatsappVerificationOperationId = '';
      whatsappVerificationOperationCode = '';
      whatsappVerificationOperationRequestId = '';
    }
    if (mounted) setState(() => errorText = '');
  }

  Future<void> loadLocalSession() async {
    if (!usesCodeLogin) {
      if (mounted) setState(() => localSessionLoaded = true);
      return;
    }
    SallaIdentity? identity;
    Object? validationError;
    try {
      identity = await (() async {
        final savedIdentity = await SallaAuthService.loadLocalIdentity(
          widget.expectedRole,
        );
        return savedIdentity == null
            ? null
            : await SallaAuthService.validateLocalIdentity(
                savedIdentity,
                allowDriverOperationalBlock: widget.allowDriverOperationalBlock,
              ).timeout(const Duration(seconds: 10));
      })()
          .timeout(const Duration(seconds: 16));
    } catch (error) {
      validationError = error;
    }
    if (!mounted) return;
    setState(() {
      localIdentity = identity;
      localSessionError = validationError;
      localSessionLoaded = true;
    });
  }

  Future<void> loadSavedLogin() async {
    SallaSavedLogin? saved;
    try {
      saved = await SallaAuthService.loadSavedLogin(widget.expectedRole);
    } catch (_) {
      // Saved profile hints are optional and must never block authentication.
      saved = null;
    }
    if (!mounted) return;
    setState(() {
      savedLogin = saved;
      savedLoginLoaded = true;
    });
    if (saved != null) applySavedLogin(saved);
  }

  void applySavedLogin(SallaSavedLogin saved) {
    if (requestedNameController.text.trim().isEmpty &&
        saved.name.trim().isNotEmpty) {
      requestedNameController.text = saved.name;
    }
    if (phoneController.text.trim() == '+964' &&
        saved.phone.trim().isNotEmpty) {
      phoneController.text = saved.phone;
    }
    if (emailController.text.trim().isEmpty && saved.email.trim().isNotEmpty) {
      emailController.text = saved.email;
    }
  }

  void handleSessionRevisionChanged() {
    if (!usesCodeLogin) return;
    setState(() {
      localIdentity = null;
      localSessionError = null;
      localSessionLoaded = false;
    });
    unawaited(loadLocalSession());
    unawaited(loadSavedLogin());
  }

  @override
  Widget build(BuildContext context) {
    if (usesCodeLogin) {
      if (!localSessionLoaded) return loadingScreen();
      final sessionError = localSessionError;
      if (sessionError != null) {
        final isBlocked = sallaIsExplicitAccountBlock(sessionError);
        return accessStateScreen(
          title: isBlocked ? 'الحساب موقوف' : 'تعذر التحقق من الحساب',
          message: friendlyError(sessionError),
          icon: isBlocked ? Icons.lock_person_rounded : Icons.cloud_off_rounded,
          retry: true,
        );
      }
      final identity = localIdentity;
      if (identity != null) {
        return widget.authenticatedBuilder(context, identity);
      }
      return loginScreen();
    }
    return StreamBuilder<User?>(
      stream: SallaAuthService.firebaseAuth.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return loadingScreen();
        }
        final user = authSnapshot.data;
        if (user == null) return loginScreen();

        return FutureBuilder<SallaIdentity?>(
          key: ValueKey('${user.uid}_$refreshRevision'),
          future: SallaAuthService.resolveIdentity(
            user: user,
            expectedRole: widget.expectedRole,
            allowFirstAdminBootstrap: widget.allowFirstAdminBootstrap,
            pendingLinkCode: linkCodeInput,
            pendingDisplayName: requestedDisplayNameInput,
          ),
          builder: (context, identitySnapshot) {
            if (identitySnapshot.connectionState != ConnectionState.done) {
              return loadingScreen();
            }
            if (identitySnapshot.hasError) {
              return accessStateScreen(
                title: 'تعذر فتح الحساب',
                message: friendlyError(identitySnapshot.error),
                icon: Icons.lock_person_rounded,
                retry: true,
              );
            }
            final identity = identitySnapshot.data;
            if (identity == null) {
              return accessStateScreen(
                title: 'طلب الربط قيد المراجعة',
                message:
                    'تم تسجيل الحساب، لكنه يحتاج إلى ربطه من لوحة الإدارة بدور ${widget.expectedRole.arabicLabel}.',
                icon: Icons.hourglass_top_rounded,
                retry: true,
              );
            }
            return widget.authenticatedBuilder(context, identity);
          },
        );
      },
    );
  }

  Widget loadingScreen() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(color: widget.primaryColor),
        ),
      ),
    );
  }

  Widget loginScreen() {
    final phoneMode = widget.loginMode == SallaLoginMode.phone;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor:
                            widget.primaryColor.withValues(alpha: 0.10),
                        child: Icon(
                          roleIcon(widget.expectedRole),
                          size: 36,
                          color: widget.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        registerMode ? 'إنشاء حساب' : 'تسجيل الدخول',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        loginSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (savedLoginLoaded &&
                          savedLogin != null &&
                          !registerMode) ...[
                        const SizedBox(height: 14),
                        savedLoginCard(savedLogin!),
                      ],
                      const SizedBox(height: 22),
                      if (usesCodeLogin)
                        ...codeLoginFields()
                      else if (phoneMode)
                        ...phoneFields()
                      else
                        ...emailFields(),
                      if (errorText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      ValueListenableBuilder<int>(
                        valueListenable: whatsappResendCountdownSeconds,
                        builder: (context, resendRemaining, _) {
                          return FilledButton.icon(
                            onPressed: busy ||
                                    (usesCustomerWhatsappOtp &&
                                        verificationId.isEmpty &&
                                        SallaAuthService
                                            .whatsappOtpSendBlockedByCooldown(
                                          resendRemaining,
                                        ))
                                ? null
                                : usesCodeLogin
                                    ? submitCodeLogin
                                    : phoneMode
                                        ? (usesCustomerWhatsappOtp
                                            ? (verificationId.isEmpty
                                                ? sendWhatsappPhoneCode
                                                : verifyWhatsappPhoneCode)
                                            : (verificationId.isEmpty
                                                ? sendPhoneCode
                                                : verifyPhoneCode))
                                        : submitEmail,
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: busy
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : usesCodeLogin
                                    ? const Icon(Icons.login_rounded)
                                    : Icon(
                                        verificationId.isEmpty
                                            ? Icons.login_rounded
                                            : Icons.verified_rounded,
                                      ),
                            label: Text(
                              usesCodeLogin
                                  ? 'دخول بالرمز'
                                  : phoneMode
                                      ? (verificationId.isEmpty
                                          ? (usesCustomerWhatsappOtp
                                              ? 'إرسال رمز واتساب'
                                              : 'إرسال رمز التحقق')
                                          : (usesCustomerWhatsappOtp
                                              ? 'تأكيد رمز واتساب'
                                              : 'تأكيد الرمز'))
                                      : (registerMode
                                          ? 'إنشاء الحساب'
                                          : 'تسجيل الدخول'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          );
                        },
                      ),
                      if (!phoneMode && widget.allowRegistration) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  setState(() {
                                    registerMode = !registerMode;
                                    errorText = '';
                                  });
                                },
                          child: Text(
                            registerMode
                                ? 'لديك حساب؟ سجل الدخول'
                                : 'إنشاء حساب جديد',
                            style: TextStyle(
                              color: widget.primaryColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      if (widget.loginFooter != null) ...[
                        const SizedBox(height: 16),
                        widget.loginFooter!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> emailFields() {
    return [
      if (shouldCollectAccessDetails) ...[
        TextField(
          controller: requestedNameController,
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
          decoration: fieldDecoration(
            requestedNameLabel,
            requestedNameIcon,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: linkCodeController,
          keyboardType: TextInputType.text,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
          decoration: fieldDecoration(
            linkCodeLabel,
            Icons.password_rounded,
          ),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: emailController,
        keyboardType: TextInputType.emailAddress,
        textDirection: TextDirection.ltr,
        decoration: fieldDecoration(
          'البريد الإلكتروني',
          Icons.alternate_email_rounded,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: passwordController,
        obscureText: true,
        textDirection: TextDirection.ltr,
        decoration: fieldDecoration('كلمة المرور', Icons.lock_rounded),
      ),
    ];
  }

  bool get shouldCollectAccessDetails {
    return widget.expectedRole != SallaUserRole.customer &&
        verificationId.isEmpty;
  }

  String get requestedDisplayNameInput => requestedNameController.text.trim();

  String get linkCodeInput =>
      SallaAuthService.normalizeLinkCode(linkCodeController.text);

  String get loginCodeInput =>
      SallaAuthService.normalizeLinkCode(loginCodeController.text);

  bool get needsLinkCode {
    return widget.expectedRole != SallaUserRole.customer &&
        !(widget.expectedRole == SallaUserRole.admin &&
            widget.allowFirstAdminBootstrap);
  }

  String get linkCodeLabel {
    if (widget.expectedRole == SallaUserRole.admin &&
        widget.allowFirstAdminBootstrap) {
      return 'رمز الربط للموظفين فقط';
    }
    return 'رمز الربط من الإدارة';
  }

  String get requestedNameLabel {
    return switch (widget.expectedRole) {
      SallaUserRole.store => 'اسم المتجر أو الفرع',
      SallaUserRole.driver => 'اسم السائق',
      SallaUserRole.admin => 'اسم الحساب الإداري',
      SallaUserRole.customer => 'الاسم',
    };
  }

  Future<void> pasteAdminClipboardCredentials() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final credentials = parseSallaAdminClipboardCredentials(
        clipboard?.text ?? '',
      );
      if (!mounted) return;
      if (credentials == null) {
        setState(() {
          errorText =
              'انسخ بيانات الدخول من زر النسخ في بطاقة الموظف، ثم اضغط اللصق هنا.';
        });
        return;
      }
      setState(() {
        requestedNameController.text = credentials.requestedName;
        phoneController.text = credentials.phone;
        linkCodeController.text = credentials.linkCode;
        loginCodeController.text = credentials.loginCode;
        errorText = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        errorText = 'تعذر قراءة الحافظة. انسخ بيانات الموظف ثم حاول مرة أخرى.';
      });
    }
  }

  String get loginSubtitle {
    return switch (widget.expectedRole) {
      SallaUserRole.admin => 'لوحة إدارة سلة',
      _ => 'تطبيق ${widget.expectedRole.arabicLabel} سلة',
    };
  }

  IconData get requestedNameIcon {
    return switch (widget.expectedRole) {
      SallaUserRole.store => Icons.storefront_rounded,
      SallaUserRole.driver => Icons.delivery_dining_rounded,
      SallaUserRole.admin => Icons.admin_panel_settings_rounded,
      SallaUserRole.customer => Icons.person_rounded,
    };
  }

  List<Widget> codeLoginFields() {
    final adminMode = widget.expectedRole == SallaUserRole.admin;
    return [
      TextField(
        controller: requestedNameController,
        keyboardType: TextInputType.name,
        textInputAction: TextInputAction.next,
        decoration: fieldDecoration(
          requestedNameLabel,
          requestedNameIcon,
        ).copyWith(
          helperText: adminMode
              ? 'اكتب اسم الموظف المسجل؛ اختلاف الهمزات والمسافات مقبول.'
              : null,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: phoneController,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        textInputAction: TextInputAction.next,
        decoration: fieldDecoration(
          'رقم الهاتف المسجل في الإدارة',
          Icons.phone_rounded,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: linkCodeController,
        keyboardType: TextInputType.text,
        textDirection: TextDirection.ltr,
        textInputAction:
            adminMode ? TextInputAction.next : TextInputAction.done,
        decoration: fieldDecoration(
          adminMode ? 'رمز الربط من الإدارة' : 'رمز الدخول من الإدارة',
          Icons.password_rounded,
        ),
      ),
      if (adminMode) ...[
        const SizedBox(height: 12),
        TextField(
          controller: loginCodeController,
          keyboardType: TextInputType.text,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.done,
          obscureText: true,
          decoration: fieldDecoration(
            'رمز دخول الحساب الإداري',
            Icons.lock_rounded,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: busy ? null : pasteAdminClipboardCredentials,
            icon: const Icon(Icons.content_paste_rounded),
            label: const Text('لصق بيانات الدخول المنسوخة من الإدارة'),
          ),
        ),
      ],
    ];
  }

  List<Widget> phoneFields() {
    return [
      if (shouldCollectAccessDetails) ...[
        TextField(
          controller: requestedNameController,
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
          decoration: fieldDecoration(
            requestedNameLabel,
            requestedNameIcon,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: linkCodeController,
          keyboardType: TextInputType.text,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
          decoration: fieldDecoration(
            linkCodeLabel,
            Icons.password_rounded,
          ),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: phoneController,
        keyboardType: TextInputType.phone,
        enabled: verificationId.isEmpty,
        textDirection: TextDirection.ltr,
        onChanged:
            usesCustomerWhatsappOtp ? handleWhatsappPhoneInputChanged : null,
        decoration: fieldDecoration(
          usesCustomerWhatsappOtp
              ? 'رقم واتساب بصيغة +964'
              : 'رقم الهاتف بصيغة +964',
          usesCustomerWhatsappOtp ? Icons.chat_rounded : Icons.phone_rounded,
        ),
      ),
      if (usesCustomerWhatsappOtp && verificationId.isEmpty) ...[
        const SizedBox(height: 8),
        const Text(
          'بعد التحقق مرة واحدة، يبقى هذا الجهاز موثوقاً وتُستعاد الجلسة '
          'بأمان من دون رسالة جديدة ما لم تُزل الحساب من الجهاز.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.45,
          ),
        ),
      ],
      if (verificationId.isNotEmpty) ...[
        const SizedBox(height: 12),
        TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          maxLength: 6,
          decoration: fieldDecoration(
            usesCustomerWhatsappOtp ? 'رمز واتساب' : 'رمز التحقق',
            Icons.password_rounded,
          ),
        ),
        if (usesCustomerWhatsappOtp)
          ValueListenableBuilder<int>(
            valueListenable: whatsappResendCountdownSeconds,
            builder: (context, resendRemaining, _) {
              return TextButton.icon(
                onPressed:
                    busy || resendRemaining > 0 ? null : sendWhatsappPhoneCode,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  resendRemaining > 0
                      ? 'إعادة الإرسال بعد $resendRemaining ثانية'
                      : 'إعادة إرسال رمز واتساب',
                ),
              );
            },
          ),
        TextButton(
          onPressed: busy
              ? null
              : () {
                  clearWhatsappResendTimer();
                  setState(() {
                    verificationId = '';
                    codeController.clear();
                    errorText = '';
                    whatsappRequestOperationId = '';
                    whatsappRequestPhone = '';
                    whatsappRequestContextOperationId = '';
                    whatsappRequestContext = null;
                    whatsappRequestExpiresAt = null;
                    whatsappVerificationOperationId = '';
                    whatsappVerificationOperationCode = '';
                    whatsappVerificationOperationRequestId = '';
                  });
                },
          child: const Text('تغيير رقم الهاتف'),
        ),
      ],
    ];
  }

  InputDecoration fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: widget.primaryColor),
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget savedLoginCard(SallaSavedLogin saved) {
    final title = saved.name.trim().isNotEmpty
        ? saved.name.trim()
        : widget.expectedRole.arabicLabel;
    final subtitleParts = [
      if (saved.phone.trim().isNotEmpty) saved.phone.trim(),
      if (saved.email.trim().isNotEmpty) saved.email.trim(),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark_added_rounded, color: widget.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'بيانات حساب محفوظة: $title',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          if (subtitleParts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitleParts.join(' • '),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          setState(() {
                            applySavedLogin(saved);
                            errorText = '';
                          });
                        },
                  icon: const Icon(Icons.input_rounded),
                  label: const Text('تعبئة البيانات'),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        await SallaAuthService.clearSavedLogin(
                          widget.expectedRole,
                        );
                        if (!mounted) return;
                        setState(() => savedLogin = null);
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('مسح'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  SallaSavedLogin currentLoginDraft() {
    return SallaSavedLogin(
      role: widget.expectedRole,
      name: requestedNameController.text.trim(),
      phone: normalizeIraqiPhone(phoneController.text),
      email: emailController.text.trim(),
      savedAt: DateTime.now(),
    );
  }

  bool sameSavedLogin(SallaSavedLogin a, SallaSavedLogin b) {
    return a.role == b.role &&
        a.name.trim() == b.name.trim() &&
        a.phone.trim() == b.phone.trim() &&
        a.email.trim() == b.email.trim();
  }

  Future<void> askToSaveCurrentLogin() async {
    final draft = currentLoginDraft();
    if (!draft.hasUsableData) return;
    final existing = savedLogin;
    if (existing != null && sameSavedLogin(existing, draft)) return;
    if (!mounted) return;
    if (busy) setState(() => busy = false);
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('حفظ بيانات الحساب'),
            content: Text(
              'هل تريد حفظ الاسم وبيانات التعريف لحساب ${widget.expectedRole.arabicLabel} على هذا الجهاز؟ لا يُحفظ رمز الربط أو رمز الدخول، ويجب إدخاله من جديد عند الحاجة.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('لا تحفظ'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.bookmark_added_rounded),
                label: const Text('حفظ'),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.primaryColor,
                ),
              ),
            ],
          ),
        );
      },
    );
    if (shouldSave != true) return;
    try {
      await SallaAuthService.saveLoginCredentials(draft);
    } catch (_) {
      // Authentication already succeeded; optional local hints may fail safely.
      return;
    }
    if (!mounted) return;
    setState(() => savedLogin = draft);
  }

  Future<void> submitEmail() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (shouldCollectAccessDetails && requestedDisplayNameInput.length < 3) {
      setState(() => errorText = 'اكتب $requestedNameLabel قبل تسجيل الدخول.');
      return;
    }
    if (needsLinkCode && linkCodeInput.length < 4) {
      setState(() => errorText = 'اكتب رمز الربط الذي أعطته لك الإدارة.');
      return;
    }
    if (email.isEmpty || password.length < 6) {
      setState(
          () => errorText = 'أدخل بريداً صحيحاً وكلمة مرور لا تقل عن 6 أحرف.');
      return;
    }
    await runAuthAction(() async {
      if (registerMode) {
        final credential = await SallaAuthService.firebaseAuth
            .createUserWithEmailAndPassword(
              email: email,
              password: password,
            )
            .timeout(const Duration(seconds: 30));
        await saveRequestedDisplayName(
          credential.user,
        ).timeout(const Duration(seconds: 20));
        final user = credential.user;
        if (user != null) {
          await user
              .sendEmailVerification()
              .timeout(const Duration(seconds: 15));
        }
        await askToSaveCurrentLogin();
      } else {
        await SallaAuthService.firebaseAuth
            .signInWithEmailAndPassword(
              email: email,
              password: password,
            )
            .timeout(const Duration(seconds: 30));
        await saveRequestedDisplayName(
          SallaAuthService.firebaseAuth.currentUser,
        ).timeout(const Duration(seconds: 20));
        await askToSaveCurrentLogin();
      }
    });
  }

  Future<void> submitCodeLogin() async {
    final requestedName = requestedDisplayNameInput;
    final phone = normalizeIraqiPhone(phoneController.text);
    if (requestedName.length < 3) {
      setState(() => errorText = 'اكتب $requestedNameLabel قبل الدخول.');
      return;
    }
    if (!phone.startsWith('+') || phone.length < 10) {
      setState(() => errorText = 'أدخل رقم هاتف صحيح مع رمز الدولة.');
      return;
    }
    if (linkCodeInput.length < 4) {
      setState(() => errorText = 'اكتب رمز الدخول الذي أعطته لك الإدارة.');
      return;
    }
    if (widget.expectedRole == SallaUserRole.admin &&
        loginCodeInput.length < 4) {
      setState(() => errorText = 'اكتب رمز دخول الحساب الإداري.');
      return;
    }
    setState(() {
      busy = true;
      errorText = '';
    });
    try {
      final identity = await SallaAuthService.signInWithLinkCode(
        role: widget.expectedRole,
        requestedName: requestedName,
        phone: phone,
        linkCode: linkCodeInput,
        loginCode: loginCodeInput,
      ).timeout(const Duration(seconds: 40));
      if (!mounted) return;
      await askToSaveCurrentLogin();
      if (!mounted) return;
      setState(() {
        localIdentity = identity;
        localSessionLoaded = true;
      });
    } catch (error) {
      if (SallaAuthService.firebaseAuth.currentUser?.isAnonymous == true) {
        await SallaAuthService.signOut().timeout(const Duration(seconds: 10));
      }
      if (mounted) {
        setState(() => errorText = friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendWhatsappPhoneCode() async {
    final phone = normalizeIraqiPhone(phoneController.text);
    if (!RegExp(r'^\+9647[0-9]{9}$').hasMatch(phone)) {
      setState(
        () => errorText =
            'أدخل رقم واتساب عراقي صحيحاً مثل 07700000000 أو +9647700000000.',
      );
      return;
    }
    if (SallaAuthService.whatsappOtpPhoneChanged(
      activePhone: whatsappRequestPhone,
      nextPhone: phone,
    )) {
      handleWhatsappPhoneInputChanged(phone);
    }
    final remaining = whatsappResendRemainingSeconds;
    if (SallaAuthService.whatsappOtpSendBlockedByCooldown(remaining)) {
      setState(
        () => errorText = 'يمكن إعادة إرسال رمز واتساب بعد $remaining ثانية.',
      );
      return;
    }
    phoneController.value = TextEditingValue(
      text: phone,
      selection: TextSelection.collapsed(offset: phone.length),
    );
    whatsappRequestPhone = phone;
    setState(() {
      busy = true;
      errorText = '';
    });
    var requestOperationId = whatsappRequestOperationId;
    var callableStarted = false;
    try {
      final requestExpired = SallaAuthService.whatsappOtpRequestExpired(
        operationId: requestOperationId,
        expiresAt: whatsappRequestExpiresAt,
        now: DateTime.now(),
      );
      if (requestExpired) {
        requestOperationId = '';
        whatsappRequestOperationId = '';
        whatsappRequestPhone = '';
        whatsappRequestContextOperationId = '';
        whatsappRequestContext = null;
        whatsappRequestExpiresAt = null;
        verificationId = '';
        whatsappVerificationOperationId = '';
        whatsappVerificationOperationCode = '';
        whatsappVerificationOperationRequestId = '';
      }
      requestOperationId = requestOperationId.isEmpty
          ? SallaAuthService.newWhatsappOtpOperationId()
          : requestOperationId;
      whatsappRequestOperationId = requestOperationId;
      final otpSource = widget.customerWhatsappOtpSource;
      var requestContext = otpSource.requiresPickup &&
              whatsappRequestContextOperationId == requestOperationId
          ? whatsappRequestContext
          : null;
      if (otpSource.requiresPickup && requestContext == null) {
        final provider = widget.customerWhatsappOtpRequestContextProvider;
        if (provider == null) {
          throw StateError(
            'حدد موقعك أولاً للتأكد من توفر خدمة المندوب.',
          );
        }
        requestContext = await provider();
        if (!mounted) return;
        if (!requestContext.isValid) {
          throw StateError(
            'تعذر تثبيت موقعك. تحقق من GPS ثم حاول مجدداً.',
          );
        }
        whatsappRequestContextOperationId = requestOperationId;
        whatsappRequestContext = requestContext;
      }
      callableStarted = true;
      final request = await SallaAuthService.requestCustomerWhatsappOtp(
        phone,
        requestId: requestOperationId,
        source: otpSource,
        requestContext: requestContext,
      );
      if (!mounted) return;
      startWhatsappResendTimer(request.resendSeconds);
      final previousRequestId = verificationId;
      final expiresAt = request.expiresAtMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              request.expiresAtMs,
              isUtc: true,
            ).toLocal()
          : DateTime.now().add(const Duration(minutes: 5));
      setState(() {
        verificationId = request.requestId;
        whatsappRequestExpiresAt = expiresAt;
        if (previousRequestId != request.requestId) {
          whatsappVerificationOperationId = '';
          whatsappVerificationOperationCode = '';
          whatsappVerificationOperationRequestId = '';
        }
        if (!request.deliveryUncertain) {
          whatsappRequestOperationId = '';
          whatsappRequestPhone = '';
          whatsappRequestContextOperationId = '';
          whatsappRequestContext = null;
        }
        resendToken = null;
        codeController.clear();
        errorText = request.deliveryUncertain
            ? 'قد تكون الرسالة وصلت رغم تعذر تأكيد التسليم. أدخل الرمز إن وصلك، ولا تطلب رمزاً جديداً قبل انتهاء المهلة.'
            : '';
      });
    } catch (error) {
      if (mounted) {
        final resultUncertain = callableStarted &&
            (error is! SallaWhatsappOtpException || error.resultUncertain);
        if (resultUncertain) {
          final retryAfter =
              error is SallaWhatsappOtpException ? error.retryAfterSeconds : 0;
          startWhatsappResendTimer(retryAfter > 0 ? retryAfter : 30);
          whatsappRequestExpiresAt ??=
              DateTime.now().add(const Duration(minutes: 5));
        } else {
          whatsappRequestOperationId = '';
          whatsappRequestPhone = '';
          whatsappRequestContextOperationId = '';
          whatsappRequestContext = null;
          whatsappRequestExpiresAt = null;
          final retryAfter =
              error is SallaWhatsappOtpException ? error.retryAfterSeconds : 0;
          if (retryAfter > 0) startWhatsappResendTimer(retryAfter);
        }
        setState(() {
          if (resultUncertain) verificationId = requestOperationId;
          errorText = friendlyError(error);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyWhatsappPhoneCode() async {
    final phone = normalizeIraqiPhone(phoneController.text);
    final code = codeController.text
        .split('')
        .map(_normalizePhoneDigit)
        .join()
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (verificationId.isEmpty) {
      setState(() => errorText = 'أرسل رمز واتساب أولاً.');
      return;
    }
    if (code.length != 6) {
      setState(() => errorText = 'أدخل رمز التحقق المكوّن من 6 أرقام.');
      return;
    }
    await runAuthAction(() async {
      var callableStarted = false;
      try {
        if (!SallaAuthService.shouldReuseWhatsappOtpVerificationOperation(
          operationId: whatsappVerificationOperationId,
          operationRequestId: whatsappVerificationOperationRequestId,
          operationCode: whatsappVerificationOperationCode,
          requestId: verificationId,
          code: code,
        )) {
          whatsappVerificationOperationId =
              SallaAuthService.newWhatsappOtpOperationId();
          whatsappVerificationOperationCode = code;
          whatsappVerificationOperationRequestId = verificationId;
        }
        callableStarted = true;
        await SallaAuthService.verifyCustomerWhatsappOtp(
          phone: phone,
          requestId: verificationId,
          code: code,
          verificationId: whatsappVerificationOperationId,
          source: widget.customerWhatsappOtpSource,
        );
      } catch (error) {
        final resultUncertain = callableStarted &&
            (error is! SallaWhatsappOtpException || error.resultUncertain);
        if (!resultUncertain) {
          whatsappVerificationOperationId = '';
          whatsappVerificationOperationCode = '';
          whatsappVerificationOperationRequestId = '';
          if (error is SallaWhatsappOtpException &&
              const <String>{
                'otp_session_not_found',
                'otp_expired',
                'otp_attempts_exceeded',
              }.contains(error.reason)) {
            whatsappRequestOperationId = '';
            whatsappRequestPhone = '';
            whatsappRequestContextOperationId = '';
            whatsappRequestContext = null;
            whatsappRequestExpiresAt = null;
            verificationId = '';
          }
        }
        rethrow;
      }
      whatsappVerificationOperationId = '';
      whatsappVerificationOperationCode = '';
      whatsappVerificationOperationRequestId = '';
      whatsappRequestOperationId = '';
      whatsappRequestPhone = '';
      whatsappRequestContextOperationId = '';
      whatsappRequestContext = null;
      clearWhatsappResendTimer();
      whatsappRequestExpiresAt = null;
    });
  }

  Future<void> sendPhoneCode() async {
    final phone = normalizeIraqiPhone(phoneController.text);
    if (widget.expectedRole != SallaUserRole.customer &&
        requestedDisplayNameInput.length < 3) {
      setState(() => errorText = 'اكتب $requestedNameLabel قبل إرسال الرمز.');
      return;
    }
    if (needsLinkCode && linkCodeInput.length < 4) {
      setState(() => errorText = 'اكتب رمز الربط الذي أعطته لك الإدارة.');
      return;
    }
    if (!phone.startsWith('+') || phone.length < 10) {
      setState(() => errorText = 'أدخل رقم هاتف صحيحاً مع رمز الدولة.');
      return;
    }
    setState(() {
      busy = true;
      errorText = '';
    });
    final attempt = ++_phoneVerificationAttempt;
    _phoneVerificationWatchdog?.cancel();
    _phoneVerificationWatchdog = Timer(const Duration(seconds: 75), () {
      if (!mounted || attempt != _phoneVerificationAttempt) return;
      _phoneVerificationAttempt += 1;
      _phoneVerificationWatchdog = null;
      setState(() {
        busy = false;
        errorText =
            'لم يصل رد التحقق من الهاتف ضمن المهلة. تحقق من الاتصال ثم أعد المحاولة.';
      });
    });

    bool isCurrentAttempt() => mounted && attempt == _phoneVerificationAttempt;
    void cancelWatchdog() {
      if (attempt != _phoneVerificationAttempt) return;
      _phoneVerificationWatchdog?.cancel();
      _phoneVerificationWatchdog = null;
    }

    try {
      await SallaAuthService.firebaseAuth
          .verifyPhoneNumber(
            phoneNumber: phone,
            forceResendingToken: resendToken,
            timeout: const Duration(seconds: 60),
            verificationCompleted: (credential) async {
              if (!isCurrentAttempt()) return;
              try {
                final result = await SallaAuthService.firebaseAuth
                    .signInWithCredential(credential)
                    .timeout(const Duration(seconds: 30));
                await saveRequestedDisplayName(
                  result.user,
                ).timeout(const Duration(seconds: 20));
                if (!isCurrentAttempt()) return;
                cancelWatchdog();
                setState(() => busy = false);
                await askToSaveCurrentLogin();
              } catch (error) {
                if (isCurrentAttempt()) {
                  setState(() => errorText = friendlyError(error));
                }
              } finally {
                if (isCurrentAttempt()) {
                  cancelWatchdog();
                  setState(() => busy = false);
                }
              }
            },
            verificationFailed: (error) {
              if (!isCurrentAttempt()) return;
              cancelWatchdog();
              setState(() {
                busy = false;
                errorText = friendlyError(error);
              });
            },
            codeSent: (id, token) {
              if (!isCurrentAttempt()) return;
              cancelWatchdog();
              setState(() {
                busy = false;
                verificationId = id;
                resendToken = token;
              });
            },
            codeAutoRetrievalTimeout: (id) {
              if (!isCurrentAttempt()) return;
              cancelWatchdog();
              setState(() {
                busy = false;
                verificationId = id;
              });
            },
          )
          .timeout(const Duration(seconds: 70));
    } catch (error) {
      if (!isCurrentAttempt()) return;
      cancelWatchdog();
      _phoneVerificationAttempt += 1;
      setState(() {
        busy = false;
        errorText = friendlyError(error);
      });
    }
  }

  Future<void> verifyPhoneCode() async {
    final code = codeController.text.trim();
    if (code.length != 6) {
      setState(() => errorText = 'أدخل رمز التحقق المكوّن من 6 أرقام.');
      return;
    }
    await runAuthAction(() async {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      final result = await SallaAuthService.firebaseAuth
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 30));
      await saveRequestedDisplayName(
        result.user,
      ).timeout(const Duration(seconds: 20));
      if (mounted) setState(() => busy = false);
      await askToSaveCurrentLogin();
    });
  }

  Future<void> saveRequestedDisplayName(User? user) async {
    final requestedName = requestedDisplayNameInput;
    final requestedLinkCode = linkCodeInput;
    if (user == null || (requestedName.isEmpty && requestedLinkCode.isEmpty)) {
      return;
    }
    if (requestedName.isNotEmpty) {
      try {
        await user.updateDisplayName(requestedName);
        await user.reload();
      } catch (_) {
        // Some phone-auth environments delay profile updates; the database copy
        // below is enough for the pending access request.
      }
    }
    try {
      final phone = user.phoneNumber?.trim() ?? '';
      final email = user.email?.trim() ?? '';
      await SallaAuthService.firebaseDatabase
          .ref()
          .child('accountProfiles')
          .child(user.uid)
          .update({
        'uid': user.uid,
        if (phone.isNotEmpty) 'phone': phone,
        if (email.isNotEmpty) 'email': email,
        if (requestedName.isNotEmpty) 'requestedName': requestedName,
        if (requestedLinkCode.isNotEmpty)
          'requestedLinkCode': requestedLinkCode,
        if (widget.expectedRole == SallaUserRole.store &&
            requestedName.isNotEmpty)
          'requestedStoreName': requestedName,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // The access request can still fall back to FirebaseAuth displayName.
    }
  }

  Future<void> runAuthAction(Future<void> Function() action) async {
    setState(() {
      busy = true;
      errorText = '';
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => errorText = friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget accessStateScreen({
    required String title,
    required String message,
    required IconData icon,
    required bool retry,
  }) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 62, color: widget.primaryColor),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          height: 1.6,
                        ),
                      ),
                      if (retry) ...[
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: () {
                            if (usesCodeLogin) {
                              setState(() {
                                localIdentity = null;
                                localSessionError = null;
                                localSessionLoaded = false;
                              });
                              unawaited(loadLocalSession());
                              return;
                            }
                            setState(() => refreshRevision += 1);
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة التحقق'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => unawaited(
                          SallaAuthService.confirmAndSignOut(
                            context,
                            primaryColor: widget.primaryColor,
                          ),
                        ),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData roleIcon(SallaUserRole role) {
  switch (role) {
    case SallaUserRole.customer:
      return Icons.shopping_bag_rounded;
    case SallaUserRole.driver:
      return Icons.delivery_dining_rounded;
    case SallaUserRole.store:
      return Icons.storefront_rounded;
    case SallaUserRole.admin:
      return Icons.admin_panel_settings_rounded;
  }
}

String normalizeIraqiPhone(String value) {
  var phone = value
      .split('')
      .map(_normalizePhoneDigit)
      .join()
      .replaceAll(RegExp(r'[^0-9+]'), '');
  if (phone.startsWith('00')) phone = '+${phone.substring(2)}';
  if (phone.startsWith('+9640')) phone = '+964${phone.substring(5)}';
  if (phone.startsWith('07')) phone = '+964${phone.substring(1)}';
  if (phone.startsWith('9640')) phone = '+964${phone.substring(4)}';
  if (phone.startsWith('7') && phone.length == 10) phone = '+964$phone';
  if (phone.startsWith('964')) phone = '+$phone';
  return phone;
}

String _normalizePhoneDigit(String char) {
  if (char.isEmpty) return char;
  final codeUnit = char.codeUnitAt(0);
  if (codeUnit >= 0x0660 && codeUnit <= 0x0669) {
    return '${codeUnit - 0x0660}';
  }
  if (codeUnit >= 0x06F0 && codeUnit <= 0x06F9) {
    return '${codeUnit - 0x06F0}';
  }
  return char;
}

String friendlyError(Object? error) {
  final errorMessage = error?.toString() ?? '';
  final normalizedErrorMessage = errorMessage.toLowerCase();
  if (normalizedErrorMessage.contains('firebase_database') &&
      (normalizedErrorMessage.contains('permission denied') ||
          normalizedErrorMessage.contains('permission-denied') ||
          normalizedErrorMessage.contains('permission_denied') ||
          normalizedErrorMessage.contains('unknown'))) {
    return 'رفضت Firebase قراءة بيانات الربط. حدّث قواعد قاعدة البيانات ثم أعد فتح التطبيق وجرب الدخول مرة أخرى.';
  }
  if (errorMessage.contains('ADMIN_CODE_LOGIN_FAILED')) {
    return 'بيانات الدخول أو الرمز غير صحيح.';
  }
  if (normalizedErrorMessage.contains('stacktrace') ||
      normalizedErrorMessage.contains('java.lang') ||
      normalizedErrorMessage.contains('persistentconnection') ||
      normalizedErrorMessage.contains('permission denied') ||
      normalizedErrorMessage.contains('firebase_database/unknown')) {
    return 'تعذر فتح الحساب الآن. تحقق من الاتصال أو صلاحيات Firebase ثم حاول مرة أخرى.';
  }
  if (error is SallaWhatsappOtpException) return error.message;
  if (error is SallaAccountBlockedException) return error.message;
  if (error is TimeoutException) {
    return 'تعذر التحقق من الحساب ضمن المهلة. تحقق من الاتصال ثم اضغط إعادة التحقق.';
  }
  if (error is StateError) return error.message;
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'configuration-not-found':
        return 'Firebase Authentication غير مفعّل بعد في مشروع salla-dev.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'بيانات الدخول غير صحيحة.';
      case 'email-already-in-use':
        return 'البريد مستخدم في حساب آخر.';
      case 'invalid-email':
        return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة.';
      case 'invalid-verification-code':
        return 'رمز التحقق غير صحيح.';
      case 'invalid-phone-number':
        return 'رقم الهاتف غير صحيح. اكتب الرقم مثل 07700000000 أو +9647700000000.';
      case 'too-many-requests':
        return 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة.';
      case 'network-request-failed':
        return 'تعذر الاتصال بالشبكة.';
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return 'تطبيق Android لم يكن موثقاً في Firebase. أعد تشغيل التطبيق بعد إضافة بصمات SHA.';
      case 'captcha-check-failed':
        return 'فشل التحقق الأمني. أوقف التطبيق وافتحه من جديد ثم أعد المحاولة.';
      case 'operation-not-allowed':
        final message = error.message?.toLowerCase() ?? '';
        if (message.contains('anonymous')) {
          return 'فعّل Anonymous في Firebase Authentication حتى يعمل دخول السائق والمتجر بالرمز.';
        }
        return 'تعذر إرسال SMS لهذا الرقم. تأكد من تفعيل Phone ومن السماح لبلد الرقم في SMS region policy.';
    }
    final message = error.message ?? '';
    if (message.contains('Exception') ||
        message.contains('Stacktrace') ||
        message.contains('java.lang')) {
      return 'تعذر إكمال تسجيل الدخول. حاول مرة أخرى.';
    }
    return message.isEmpty ? 'تعذر إكمال تسجيل الدخول.' : message;
  }
  return 'حدث خطأ غير متوقع. حاول مرة أخرى.';
}
