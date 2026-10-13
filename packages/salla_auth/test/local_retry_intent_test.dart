import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salla_auth/salla_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('يحفظ نية إعادة المحاولة ويعزلها حسب الحساب والنطاق', () async {
    await SallaAuthService.saveLocalRetryIntent(
      role: SallaUserRole.store,
      environment: 'salla-dev',
      ownerUid: 'store-owner-a',
      namespace: 'store_operational_status',
      intentId: 'store-a',
      payload: const <String, Object?>{
        'action': 'open',
        'requestId': 'open-request-1',
      },
    );

    final production = await SallaAuthService.loadLocalRetryIntents(
      role: SallaUserRole.store,
      environment: 'salla-prod',
      ownerUid: 'store-owner-a',
      namespace: 'store_operational_status',
    );
    final matching = await SallaAuthService.loadLocalRetryIntents(
      role: SallaUserRole.store,
      environment: 'salla-dev',
      ownerUid: 'store-owner-a',
      namespace: 'store_operational_status',
    );
    final otherOwner = await SallaAuthService.loadLocalRetryIntents(
      role: SallaUserRole.store,
      environment: 'salla-dev',
      ownerUid: 'store-owner-b',
      namespace: 'store_operational_status',
    );

    expect(matching['store-a'], <String, dynamic>{
      'action': 'open',
      'requestId': 'open-request-1',
    });
    expect(otherOwner, isEmpty);
    expect(production, isEmpty);
    expect(
      await SallaAuthService.loadLocalRetryIntents(
        role: SallaUserRole.store,
        environment: 'salla-dev',
        ownerUid: 'store-owner-a',
        namespace: 'store_operational_status',
      ),
      isEmpty,
      reason: 'فتح حساب آخر يمسح intent الحساب السابق ولا يعيد محاولته',
    );
  });

  test('يحذف intent المنتهي حسب TTL ولا يعيد محاولة قديمة', () async {
    final savedAt = DateTime.utc(2026, 8, 1);
    final encodedEnvironment =
        base64Url.encode(utf8.encode('salla-dev')).replaceAll('=', '');
    final encodedOwner =
        base64Url.encode(utf8.encode('store-owner-a')).replaceAll('=', '');
    final encodedNamespace = base64Url
        .encode(utf8.encode('store_operational_status'))
        .replaceAll('=', '');
    final encodedIntent =
        base64Url.encode(utf8.encode('store-a')).replaceAll('=', '');
    final key =
        'salla_local_retry_intent_v1|$encodedEnvironment|store|$encodedOwner|$encodedNamespace|$encodedIntent';
    SharedPreferences.setMockInitialValues(<String, Object>{
      key: jsonEncode(<String, Object?>{
        'version': 1,
        'environment': 'salla-dev',
        'role': 'store',
        'ownerUid': 'store-owner-a',
        'namespace': 'store_operational_status',
        'intentId': 'store-a',
        'savedAtMs': savedAt.millisecondsSinceEpoch,
        'payload': <String, Object?>{
          'action': 'open',
          'requestId': 'expired-request',
        },
      }),
    });

    final loaded = await SallaAuthService.loadLocalRetryIntents(
      role: SallaUserRole.store,
      environment: 'salla-dev',
      ownerUid: 'store-owner-a',
      namespace: 'store_operational_status',
      maxAge: const Duration(days: 7),
      now: savedAt.add(const Duration(days: 8)),
    );
    final prefs = await SharedPreferences.getInstance();

    expect(loaded, isEmpty);
    expect(prefs.containsKey(key), isFalse);
  });

  test('لا يحذف النية إلا بطلب صريح بعد تأكيد الخادم', () async {
    await SallaAuthService.saveLocalRetryIntent(
      role: SallaUserRole.admin,
      environment: 'salla-dev',
      ownerUid: 'admin-owner',
      namespace: 'store_admin_status',
      intentId: 'store-a',
      payload: const <String, Object?>{
        'action': 'pause',
        'reason': 'مراجعة تشغيلية',
        'requestId': 'pause-request-1',
      },
    );
    expect(
      await SallaAuthService.loadLocalRetryIntents(
        role: SallaUserRole.admin,
        environment: 'salla-dev',
        ownerUid: 'admin-owner',
        namespace: 'store_admin_status',
      ),
      contains('store-a'),
    );

    await SallaAuthService.removeLocalRetryIntent(
      role: SallaUserRole.admin,
      environment: 'salla-dev',
      ownerUid: 'admin-owner',
      namespace: 'store_admin_status',
      intentId: 'store-a',
    );

    expect(
      await SallaAuthService.loadLocalRetryIntents(
        role: SallaUserRole.admin,
        environment: 'salla-dev',
        ownerUid: 'admin-owner',
        namespace: 'store_admin_status',
      ),
      isEmpty,
    );
  });

  test('ينظف السجل المحلي المشوه ولا يعيده كتجربة صالحة', () async {
    final encodedOwner =
        base64Url.encode(utf8.encode('admin-owner')).replaceAll('=', '');
    final encodedEnvironment =
        base64Url.encode(utf8.encode('salla-dev')).replaceAll('=', '');
    final encodedNamespace =
        base64Url.encode(utf8.encode('store_admin_status')).replaceAll('=', '');
    SharedPreferences.setMockInitialValues(<String, Object>{
      'salla_local_retry_intent_v1|$encodedEnvironment|admin|$encodedOwner|$encodedNamespace|bad':
          '{not-json',
    });

    final loaded = await SallaAuthService.loadLocalRetryIntents(
      role: SallaUserRole.admin,
      environment: 'salla-dev',
      ownerUid: 'admin-owner',
      namespace: 'store_admin_status',
    );
    final prefs = await SharedPreferences.getInstance();

    expect(loaded, isEmpty);
    expect(
      prefs.getKeys().where(
            (key) => key.startsWith('salla_local_retry_intent_v1|'),
          ),
      isEmpty,
    );
  });

  test('تسجيل الخروج يمسح نوايا الحسابات المحلية', () async {
    await SallaAuthService.saveLocalRetryIntent(
      role: SallaUserRole.store,
      environment: 'salla-dev',
      ownerUid: 'store-owner-a',
      namespace: 'store_operational_status',
      intentId: 'store-a',
      payload: const <String, Object?>{
        'action': 'close',
        'requestId': 'close-request-1',
      },
    );

    await SallaAuthService.clearLocalSessions();
    final prefs = await SharedPreferences.getInstance();

    expect(
      prefs.getKeys().where(
            (key) => key.startsWith('salla_local_retry_intent_v1|'),
          ),
      isEmpty,
    );
  });
}
