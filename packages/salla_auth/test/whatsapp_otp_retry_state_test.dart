import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salla_auth/salla_auth.dart';

void main() {
  test('أخطاء النقل غير المحسومة تحتفظ بمعرف محاولة إرسال واتساب', () {
    for (final code in <String>[
      'cancelled',
      'deadline-exceeded',
      'data-loss',
      'unavailable',
      'internal',
      'resource-exhausted',
      'unknown',
    ]) {
      expect(
        SallaAuthService.whatsappOtpCallableResultUncertain(
          code: code,
          reason: '',
        ),
        isTrue,
        reason: code,
      );
    }
    expect(
      SallaAuthService.whatsappOtpCallableResultUncertain(
        code: 'internal',
        reason: 'otpiq_rate_limited',
      ),
      isFalse,
    );
    expect(
      SallaAuthService.whatsappOtpCallableResultUncertain(
        code: 'invalid-argument',
        reason: 'invalid_iraqi_phone_number',
      ),
      isFalse,
    );
  });

  test('المحاولة غير المؤكدة تبقى نفسها حتى انتهاء جلسة الرمز فقط', () {
    final expiry = DateTime.utc(2026, 8, 19, 12);
    expect(
      SallaAuthService.whatsappOtpRequestExpired(
        operationId: 'otp-request-stable',
        expiresAt: expiry,
        now: expiry.subtract(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
    expect(
      SallaAuthService.whatsappOtpRequestExpired(
        operationId: 'otp-request-stable',
        expiresAt: expiry,
        now: expiry,
      ),
      isTrue,
    );
    expect(
      SallaAuthService.whatsappOtpRequestExpired(
        operationId: '',
        expiresAt: expiry,
        now: expiry.add(const Duration(minutes: 1)),
      ),
      isFalse,
    );
    expect(
      SallaAuthService.whatsappOtpRequestExpired(
        operationId: 'otp-request-stable',
        expiresAt: null,
        now: expiry.add(const Duration(minutes: 1)),
      ),
      isFalse,
    );
  });

  test('مهلة إعادة الإرسال تمنع زر الإرسال حتى بلا جلسة تحقق مرئية', () {
    expect(SallaAuthService.whatsappOtpSendBlockedByCooldown(30), isTrue);
    expect(SallaAuthService.whatsappOtpSendBlockedByCooldown(1), isTrue);
    expect(SallaAuthService.whatsappOtpSendBlockedByCooldown(0), isFalse);
  });

  test('رقم الصورة يطبّع ويبدأ محاولة مستقلة عند تبديل الرقم', () {
    expect(normalizeIraqiPhone('+96407728568034'), '+9647728568034');
    expect(normalizeIraqiPhone('07728568034'), '+9647728568034');
    expect(
      SallaAuthService.whatsappOtpPhoneChanged(
        activePhone: '+9647765294438',
        nextPhone: '+96407728568034',
      ),
      isTrue,
    );
    expect(
      SallaAuthService.whatsappOtpPhoneChanged(
        activePhone: '+9647728568034',
        nextPhone: '07728568034',
      ),
      isFalse,
    );
  });

  test('محاولة التحقق ترتبط بمعرف الإرسال والرمز معاً', () {
    expect(
      SallaAuthService.shouldReuseWhatsappOtpVerificationOperation(
        operationId: 'verify-stable',
        operationRequestId: 'request-a',
        operationCode: '123456',
        requestId: 'request-a',
        code: '123456',
      ),
      isTrue,
    );
    expect(
      SallaAuthService.shouldReuseWhatsappOtpVerificationOperation(
        operationId: 'verify-stable',
        operationRequestId: 'request-a',
        operationCode: '123456',
        requestId: 'request-b',
        code: '123456',
      ),
      isFalse,
      reason: 'إعادة إرسال الرمز لا تعيد verificationId للطلب السابق.',
    );
    expect(
      SallaAuthService.shouldReuseWhatsappOtpVerificationOperation(
        operationId: 'verify-stable',
        operationRequestId: 'request-a',
        operationCode: '123456',
        requestId: 'request-a',
        code: '654321',
      ),
      isFalse,
    );
  });

  test('تعطل الشبكة لا يمسح جلسة الجهاز الموثوقة', () {
    expect(
      SallaAuthService.identityResolutionFailureRequiresSignOut(
        TimeoutException('network timeout'),
      ),
      isFalse,
    );
    expect(
      SallaAuthService.identityResolutionFailureRequiresSignOut(
        StateError('temporary database read failed'),
      ),
      isFalse,
    );
    expect(
      SallaAuthService.identityResolutionFailureRequiresSignOut(
        FirebaseAuthException(code: 'user-disabled'),
      ),
      isTrue,
    );
    expect(
      SallaAuthService.identityResolutionFailureRequiresSignOut(
        const SallaAccountBlockedException('الحساب موقوف'),
      ),
      isTrue,
    );
  });

  test('عداد إعادة الإرسال لا يعيد بناء شاشة الدخول كلها كل ثانية', () {
    final source = File('lib/salla_auth.dart').readAsStringSync();
    final start = source.indexOf('void startWhatsappResendTimer(');
    final end = source.indexOf('void publishWhatsappResendRemaining()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final timerBody = source.substring(start, end);

    expect(timerBody, contains('publishWhatsappResendRemaining()'));
    expect(timerBody, isNot(contains('setState(')));
    expect(
      source,
      contains('ValueListenableBuilder<int>(\n'
          '                        valueListenable: '
          'whatsappResendCountdownSeconds'),
    );
  });

  test('دخول الزبون العام يرسل مصدر واتساب دون اشتراط موقع', () {
    expect(SallaWhatsappOtpSource.customerLogin.value, 'customer_login');
    expect(SallaWhatsappOtpSource.customerLogin.requiresPickup, isFalse);
    expect(SallaWhatsappOtpSource.customerCourier.value, 'customer_courier');
    expect(SallaWhatsappOtpSource.customerCourier.requiresPickup, isTrue);

    final source = File('lib/salla_auth.dart').readAsStringSync();
    expect(source, contains("'source': source.value"));
    expect(
      source,
      contains(
        "if (source.requiresPickup) 'pickupLat': requestContext!.pickupLat",
      ),
    );
    expect(
      source,
      contains(
        'this.customerWhatsappOtpSource = '
        'SallaWhatsappOtpSource.customerLogin',
      ),
    );
  });

  test('خطأ إحداثيات مندوب الزبون لا يتحول إلى رسالة واتساب عامة', () {
    final source = File('lib/salla_auth.dart').readAsStringSync();
    expect(source, contains("case 'invalid_coordinate':"));
    expect(source, contains("case 'customer_courier_pickup_invalid':"));
    expect(
      source,
      contains(
          'تعذر تثبيت موقع الاستلام. ارجع إلى اطلب مندوبك وحدد موقعك ثم حاول مجدداً.'),
    );
  });
}
