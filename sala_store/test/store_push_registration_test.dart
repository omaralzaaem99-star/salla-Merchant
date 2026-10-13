import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  test(
    'iOS never calls FCM before APNs and recovers when APNs arrives',
    () async {
      String? apns;
      var calls = 0;
      Future<String?> token() => storeMessagingToken(
        needsApns: true,
        apnsToken: () async => apns,
        messagingToken: () async {
          calls++;
          return 'fcm';
        },
      );
      expect(await token(), isNull);
      expect(calls, 0);
      apns = 'apns';
      expect(await token(), 'fcm');
      expect(calls, 1);
    },
  );
  test('Android does not request APNs; failed FCM can be retried', () async {
    var calls = 0;
    Future<String?> token() => storeMessagingToken(
      needsApns: false,
      apnsToken: () async => throw StateError('must not call'),
      messagingToken: () async {
        if (++calls == 1) throw StateError('offline');
        return 'fcm';
      },
    );
    await expectLater(token(), throwsStateError);
    expect(await token(), 'fcm');
  });
}
