import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salla_auth/salla_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'deletion clears saved merchant hints and pending personal data, preserving other role hints',
      () async {
    SharedPreferences.setMockInitialValues({});
    for (final role in [SallaUserRole.store, SallaUserRole.driver]) {
      await SallaAuthService.saveLoginCredentials(SallaSavedLogin(
          role: role,
          name: 'name',
          phone: '07700000000',
          savedAt: DateTime.now()));
    }
    await SallaAuthService.saveLocalRetryIntent(
        role: SallaUserRole.store,
        environment: 'demo-salla',
        ownerUid: 'guest',
        namespace: 'store_guest_application_v1',
        intentId: 'application',
        payload: {'phone': '07700000000', 'address': 'private'});
    await SallaAuthService.clearDeletedAccountLocalData(SallaUserRole.store);
    expect(await SallaAuthService.loadSavedLogin(SallaUserRole.store), isNull);
    expect(
        await SallaAuthService.loadSavedLogin(SallaUserRole.driver), isNotNull);
    expect(
        await SallaAuthService.loadLocalRetryIntents(
            role: SallaUserRole.store,
            environment: 'demo-salla',
            ownerUid: 'guest',
            namespace: 'store_guest_application_v1'),
        isEmpty);
  });
}
