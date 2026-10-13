import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salla_auth/salla_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 7, 21, 12);

  group('وضع تسجيل الدخول', () {
    test('الزبون يتحقق بالهاتف والحسابات التشغيلية تستخدم رمز الإدارة', () {
      expect(
        SallaAuthService.roleUsesCodeLogin(SallaUserRole.customer),
        isFalse,
      );
      for (final role in <SallaUserRole>[
        SallaUserRole.driver,
        SallaUserRole.store,
        SallaUserRole.admin,
      ]) {
        expect(SallaAuthService.roleUsesCodeLogin(role), isTrue);
      }
    });

    test('حل الهوية محدود زمنياً وخطأ المهلة قابل لإعادة المحاولة', () {
      final source = File('lib/salla_auth.dart').readAsStringSync();
      final start = source.indexOf(
        'static Future<SallaIdentity?> resolveIdentity(',
      );
      final end = source.indexOf(
        'static Future<SallaIdentity?> _resolveIdentity(',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final wrapper = source.substring(start, end);
      expect(wrapper, contains('.timeout(_identityResolutionTimeout)'));
      expect(
        friendlyError(TimeoutException('identity resolution timeout')),
        contains('إعادة التحقق'),
      );
      expect(source, contains('setState(() => refreshRevision += 1)'));
    });

    test('الحفظ المحلي لا يكتب رموز الربط أو الدخول', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final saved = SallaSavedLogin(
        role: SallaUserRole.driver,
        name: 'سائق تجريبي',
        phone: '+9647000000000',
        savedAt: DateTime.utc(2026, 8, 2),
      );

      await SallaAuthService.saveLoginCredentials(saved);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('salla_saved_login_driver');
      expect(raw, isNotNull);
      final stored = jsonDecode(raw!) as Map<String, dynamic>;
      expect(stored, isNot(contains('linkCode')));
      expect(stored, isNot(contains('loginCode')));
      expect(stored['name'], 'سائق تجريبي');
    });

    test('الترحيل يمسح الرموز القديمة ويبقي الجلسة التشغيلية', () async {
      const sessionKey = 'salla_code_identity_driver';
      const sessionValue = '{"uid":"driver-1","role":"driver"}';
      SharedPreferences.setMockInitialValues(<String, Object>{
        sessionKey: sessionValue,
        'salla_saved_login_driver': jsonEncode(<String, Object>{
          'role': 'driver',
          'name': 'سائق قديم',
          'phone': '+9647000000000',
          'linkCode': 'legacy-link-code',
          'loginCode': 'legacy-login-code',
          'savedAt': '2026-08-02T00:00:00.000Z',
        }),
      });

      final loaded = await SallaAuthService.loadSavedLogin(
        SallaUserRole.driver,
      );

      expect(loaded?.name, 'سائق قديم');
      expect(loaded?.linkCode, isEmpty);
      expect(loaded?.loginCode, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final migrated = jsonDecode(
        prefs.getString('salla_saved_login_driver')!,
      ) as Map<String, dynamic>;
      expect(migrated, isNot(contains('linkCode')));
      expect(migrated, isNot(contains('loginCode')));
      expect(prefs.getString(sessionKey), sessionValue);
    });

    test('السجل القديم الذي لا يحوي سوى الرموز يُحذف', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'salla_saved_login_admin': jsonEncode(<String, Object>{
          'role': 'admin',
          'linkCode': 'legacy-link-code',
          'loginCode': 'legacy-login-code',
          'savedAt': '2026-08-02T00:00:00.000Z',
        }),
      });

      final loaded = await SallaAuthService.loadSavedLogin(
        SallaUserRole.admin,
      );

      expect(loaded, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('salla_saved_login_admin'), isFalse);
    });
  });

  group('حالة الحساب التشغيلية', () {
    test('يبقى التعليق المفتوح محظوراً من دون تاريخ انتهاء', () {
      final record = <String, dynamic>{
        'active': true,
        'status': 'offline',
        'adminStatus': 'suspended',
        'adminStatusUntil': '',
      };

      expect(
          sallaEffectiveOperationalAdminStatus(record, now: now), 'suspended');
      expect(sallaOperationalRecordIsBlocked(record, now: now), isTrue);
    });

    test('ينتهي التعليق المؤقت في وقته فقط', () {
      final futureSuspension = <String, dynamic>{
        'active': true,
        'adminStatus': 'suspended',
        'adminStatusUntil':
            now.add(const Duration(minutes: 1)).toIso8601String(),
      };
      final expiredSuspension = <String, dynamic>{
        ...futureSuspension,
        'adminStatusUntil': now.toIso8601String(),
      };

      expect(
          sallaOperationalRecordIsBlocked(futureSuspension, now: now), isTrue);
      expect(sallaEffectiveOperationalAdminStatus(expiredSuspension, now: now),
          'active');
      expect(sallaOperationalRecordIsBlocked(expiredSuspension, now: now),
          isFalse);
    });

    test('التعطيل والإنهاء لا ينتهيان تلقائياً', () {
      for (final status in <String>['disabled', 'terminated']) {
        expect(
          sallaOperationalRecordIsBlocked(
            <String, dynamic>{
              'active': true,
              'adminStatus': status,
              'adminStatusUntil': now.subtract(const Duration(days: 1)),
            },
            now: now,
          ),
          isTrue,
        );
      }
    });

    test('الحظر الإداري يبقي ربط جلسة السائق فقط عند الاختيار الصريح', () {
      for (final adminStatus in <String>[
        'suspended',
        'disabled',
        'terminated',
        'blocked',
      ]) {
        final record = <String, dynamic>{
          'active': true,
          'status': 'offline',
          'adminStatus': adminStatus,
          'adminStatusUntil': '',
        };
        expect(
          sallaEntityRecordAllowsBoundSession(
            record,
            role: SallaUserRole.driver,
          ),
          isFalse,
        );
        expect(
          sallaEntityRecordAllowsBoundSession(
            record,
            role: SallaUserRole.driver,
            allowDriverOperationalBlock: true,
          ),
          isTrue,
        );
        expect(
          sallaEntityRecordAllowsBoundSession(
            record,
            role: SallaUserRole.store,
            allowDriverOperationalBlock: true,
          ),
          isFalse,
        );
      }
    });

    test('تعطيل الهوية نفسها لا يستفيد من استثناء السائق التشغيلي', () {
      expect(
        sallaEntityRecordAllowsBoundSession(
          <String, dynamic>{
            'active': false,
            'status': 'offline',
            'adminStatus': 'suspended',
          },
          role: SallaUserRole.driver,
          allowDriverOperationalBlock: true,
        ),
        isFalse,
      );
      expect(
        sallaEntityRecordAllowsBoundSession(
          <String, dynamic>{
            'active': true,
            'status': 'disabled',
            'adminStatus': 'active',
          },
          role: SallaUserRole.driver,
          allowDriverOperationalBlock: true,
        ),
        isFalse,
      );
    });

    test('رسالة الحظر الصريح تحتفظ بسبب الإدارة', () {
      expect(
        sallaOperationalBlockMessage(<String, dynamic>{
          'adminActionReason': 'مراجعة المستندات',
        }),
        contains('مراجعة المستندات'),
      );
    });

    test('مهلة الشبكة ليست إيقاف حساب صريحاً', () {
      expect(
        sallaIsExplicitAccountBlock(TimeoutException('network timeout')),
        isFalse,
      );
      expect(
        sallaIsExplicitAccountBlock(
          const SallaAccountBlockedException('الحساب موقوف'),
        ),
        isTrue,
      );
    });
  });
}
