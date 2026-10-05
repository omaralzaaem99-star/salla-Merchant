import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

enum SallaAppCheckMonitoringState {
  disabled,
  active,
  unavailable,
  failed,
}

class SallaAppCheckMonitoringResult {
  final SallaAppCheckMonitoringState state;
  final String provider;

  const SallaAppCheckMonitoringResult({
    required this.state,
    this.provider = '',
  });

  bool get isActive => state == SallaAppCheckMonitoringState.active;
}

/// Activates Firebase App Check only after monitoring is explicitly enabled.
///
/// Enforcement remains a Firebase Console/server decision. Failures are kept
/// non-fatal while monitoring so an attestation outage cannot block app startup.
/// No App Check token or provider error is ever read or printed here.
class SallaAppCheckMonitoring {
  SallaAppCheckMonitoring._();

  static const bool enabled = bool.fromEnvironment(
    'SALLA_APP_CHECK_MONITORING',
    defaultValue: false,
  );

  static const String _webSiteKey = String.fromEnvironment(
    'SALLA_APP_CHECK_WEB_SITE_KEY',
    defaultValue: '',
  );

  static final Map<String, Future<SallaAppCheckMonitoringResult>>
      _activationByApp = <String, Future<SallaAppCheckMonitoringResult>>{};

  static Future<SallaAppCheckMonitoringResult> activateFor(
    FirebaseApp app,
  ) {
    if (!enabled) {
      return Future<SallaAppCheckMonitoringResult>.value(
        const SallaAppCheckMonitoringResult(
          state: SallaAppCheckMonitoringState.disabled,
        ),
      );
    }
    return _activationByApp.putIfAbsent(app.name, () => _activate(app));
  }

  static Future<SallaAppCheckMonitoringResult> _activate(
    FirebaseApp app,
  ) async {
    final appCheck = FirebaseAppCheck.instanceFor(app: app);
    try {
      if (kIsWeb) {
        final siteKey = _webSiteKey.trim();
        if (siteKey.isEmpty) {
          _logState(SallaAppCheckMonitoringState.unavailable);
          return const SallaAppCheckMonitoringResult(
            state: SallaAppCheckMonitoringState.unavailable,
            provider: 'recaptcha_enterprise',
          );
        }
        await appCheck.activate(
          providerWeb: ReCaptchaEnterpriseProvider(siteKey),
        );
        await appCheck.setTokenAutoRefreshEnabled(true);
        _logState(SallaAppCheckMonitoringState.active);
        return const SallaAppCheckMonitoringResult(
          state: SallaAppCheckMonitoringState.active,
          provider: 'recaptcha_enterprise',
        );
      }

      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await appCheck.activate(
            providerAndroid: const AndroidPlayIntegrityProvider(),
          );
          await appCheck.setTokenAutoRefreshEnabled(true);
          _logState(SallaAppCheckMonitoringState.active);
          return const SallaAppCheckMonitoringResult(
            state: SallaAppCheckMonitoringState.active,
            provider: 'play_integrity',
          );
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          await appCheck.activate(
            providerApple:
                const AppleAppAttestWithDeviceCheckFallbackProvider(),
          );
          await appCheck.setTokenAutoRefreshEnabled(true);
          _logState(SallaAppCheckMonitoringState.active);
          return const SallaAppCheckMonitoringResult(
            state: SallaAppCheckMonitoringState.active,
            provider: 'app_attest_with_device_check_fallback',
          );
        case TargetPlatform.windows:
        case TargetPlatform.linux:
        case TargetPlatform.fuchsia:
          _logState(SallaAppCheckMonitoringState.unavailable);
          return const SallaAppCheckMonitoringResult(
            state: SallaAppCheckMonitoringState.unavailable,
          );
      }
    } catch (_) {
      _logState(SallaAppCheckMonitoringState.failed);
      return const SallaAppCheckMonitoringResult(
        state: SallaAppCheckMonitoringState.failed,
      );
    }
  }

  static void _logState(SallaAppCheckMonitoringState state) {
    debugPrint('Firebase App Check monitoring: ${state.name}');
  }
}
