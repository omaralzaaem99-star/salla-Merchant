import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salla_auth/src/session_read_recovery.dart';

void main() {
  testWidgets('slow verified result opens session without another read',
      (tester) async {
    var reads = 0;
    final pending = Completer<String>();
    final seen = <String>[];
    final errors = <Object>[];
    final sub = sallaRecoveringSessionRead(() {
      reads++;
      return pending.future;
    }).listen(seen.add, onError: errors.add);
    await tester.pump(const Duration(seconds: 35));
    expect(errors.single, isA<TimeoutException>());
    expect(seen, isEmpty);
    expect(reads, 1);
    pending.complete('verified');
    await tester.pump();
    expect(seen, ['verified']);
    await tester.pump(const Duration(minutes: 2));
    expect(reads, 1);
    unawaited(sub.cancel());
    await tester.pump();
  });

  testWidgets('transport failure retries but permission denial does not',
      (tester) async {
    var reads = 0;
    final seen = <String>[];
    final sub = sallaRecoveringSessionRead<String>(() async {
      reads++;
      if (reads == 1)
        throw FirebaseException(
            plugin: 'firebase_database', code: 'unavailable');
      throw FirebaseException(
          plugin: 'firebase_database', code: 'permission-denied');
    }).listen(seen.add, onError: (Object _) {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(reads, 2);
    await tester.pump(const Duration(minutes: 3));
    expect(reads, 2);
    expect(seen, isEmpty);
    unawaited(sub.cancel());
    await tester.pump();
  });

  testWidgets('hard timeout retries and ignores the superseded result',
      (tester) async {
    final pending = <Completer<String>>[];
    final seen = <String>[];
    final sub = sallaRecoveringSessionRead(() {
      final read = Completer<String>();
      pending.add(read);
      return read.future;
    }).listen(seen.add, onError: (Object _) {});
    await tester.pump(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 5));
    expect(pending, hasLength(2));
    pending.first.complete('old');
    pending.last.complete('new verified');
    await tester.pump();
    expect(seen, ['new verified']);
    unawaited(sub.cancel());
    await tester.pump();
  });

  testWidgets('leaving or changing account discards late verification',
      (tester) async {
    final pending = Completer<String>();
    final seen = <String>[];
    final errors = <Object>[];
    final sub = sallaRecoveringSessionRead(() => pending.future)
        .listen(seen.add, onError: errors.add);
    unawaited(sub.cancel());
    await tester.pump();
    pending.complete('previous account');
    await tester.pump(const Duration(minutes: 2));
    expect(seen, isEmpty);
    expect(errors, isEmpty);
  });

  testWidgets('revoked account stays blocked without retries', (tester) async {
    var reads = 0;
    final seen = <String>[];
    final sub = sallaRecoveringSessionRead<String>(() async {
      reads++;
      throw StateError('account revoked');
    }).listen(seen.add, onError: (Object _) {});
    await tester.pump(const Duration(minutes: 3));
    expect(reads, 1);
    expect(seen, isEmpty);
    unawaited(sub.cancel());
    await tester.pump();
  });
}
