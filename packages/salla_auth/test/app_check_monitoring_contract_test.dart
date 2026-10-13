import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salla_auth/salla_auth.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('وضع المراقبة معطل افتراضياً ولا يكشف أي رمز', () {
    final source = _read('lib/src/app_check_monitoring.dart');

    expect(
      source,
      contains("'SALLA_APP_CHECK_MONITORING',\n    defaultValue: false"),
    );
    expect(source, contains('AndroidPlayIntegrityProvider'));
    expect(
      source,
      contains('AppleAppAttestWithDeviceCheckFallbackProvider'),
    );
    expect(source, contains('ReCaptchaEnterpriseProvider'));
    expect(source, isNot(contains('AndroidDebugProvider')));
    expect(source, isNot(contains('AppleDebugProvider')));
    expect(source, isNot(contains('WebDebugProvider')));
    expect(source, isNot(contains('.getToken(')));
    expect(source, isNot(contains('getLimitedUseToken')));
  });

  test('نتيجة المراقبة تميز الحالة النشطة من بقية الحالات', () {
    const active = SallaAppCheckMonitoringResult(
      state: SallaAppCheckMonitoringState.active,
      provider: 'test',
    );
    const failed = SallaAppCheckMonitoringResult(
      state: SallaAppCheckMonitoringState.failed,
    );

    expect(active.isActive, isTrue);
    expect(failed.isActive, isFalse);
  });

  test('التطبيقات الأربعة تفعّل الطبقة المشتركة بعد تهيئة فايربيس', () {
    final sources = <String, String>{
      'customer': _read('../../sala_customer/lib/main.dart'),
      'driver': _read('../../sala_driver/lib/main.dart'),
      'store': _read('../../sala_store/lib/main.dart'),
      'admin': _read('../../sala_admin/lib/main.dart'),
    };

    for (final entry in sources.entries) {
      expect(
        entry.value,
        contains('SallaAppCheckMonitoring.activateFor(firebaseApp)'),
        reason: 'App Check is missing from ${entry.key}',
      );
      expect(
        RegExp(
          r'SallaAppCheckMonitoring\.activateFor\(firebaseApp\)',
        ).allMatches(entry.value).length,
        greaterThanOrEqualTo(2),
        reason:
            'App Check must cover foreground and background startup for ${entry.key}',
      );
    }
  });
}
