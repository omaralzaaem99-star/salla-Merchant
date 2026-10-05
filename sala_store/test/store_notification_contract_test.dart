import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final home = File('lib/src/pages/store_home_page.dart').readAsStringSync();
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final service = File(
    'android/app/src/main/kotlin/com/salla/sala_store/'
    'UrgentOrderMessagingService.kt',
  ).readAsStringSync();

  String section(String startMarker, String endMarker) {
    final start = home.indexOf(startMarker);
    final end = home.indexOf(endMarker, start + startMarker.length);
    expect(start, greaterThanOrEqualTo(0), reason: startMarker);
    expect(end, greaterThan(start), reason: endMarker);
    return home.substring(start, end);
  }

  test('store registers one account-bound device through the callable', () {
    final configure = section(
      '  Future<void> _configurePushNotifications()',
      '  Future<void> _openOrderFromPushMessage',
    );
    final save = section(
      '  Future<void> _saveMessagingToken(',
      '  Future<void> _removeMessagingToken()',
    );
    expect(configure, contains('await _messagingTokenSubscription?.cancel()'));
    expect(home, contains('sallaPushTargetsCurrentAccount('));
    expect(configure, contains("type == 'store_driver_arrived'"));
    expect(configure, isNot(contains("type == 'new_order'")));
    expect(configure, isNot(contains("type == 'store_settlement_paid'")));
    expect(save, contains("httpsCallable('manageNotificationDevice')"));
    expect(save, contains("'role': 'store'"));
    expect(save, isNot(contains("child('notificationDevices')")));
  });

  test('new-order sound is deferred while notification taps open the app', () {
    final orderMerge = section(
      '  void _publishMergedOrders(',
      '  Map<String, dynamic>? _initialStoreHistoryCursor()',
    );
    expect(orderMerge, isNot(contains('_playIncomingOrderAlert(')));
    expect(service, contains('if (data["type"] == "new_order")'));
    expect(service, isNot(contains('val title = data["title"]')));
    expect(manifest, contains('android:name="FLUTTER_NOTIFICATION_CLICK"'));
  });
}
