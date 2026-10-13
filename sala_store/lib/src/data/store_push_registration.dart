part of '../../main.dart';

/// APNs can arrive after Firebase initialization on Apple devices. Failure to
/// register must not prevent the app from installing its message listeners.
Future<String?> storeMessagingToken({
  required bool needsApns,
  required Future<String?> Function() apnsToken,
  required Future<String?> Function() messagingToken,
}) async {
  if (needsApns) {
    final apns = await apnsToken().timeout(const Duration(seconds: 8));
    if (apns == null || apns.isEmpty) return null;
  }
  return messagingToken().timeout(const Duration(seconds: 12));
}
