import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(1024, 768)]) {
    testWidgets('startup failure is safe and retryable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var attempts = 0;
      await tester.pumpWidget(
        StoreStartupErrorApp(
          error: StateError('private-internal-diagnostic'),
          retry: () async {
            attempts++;
          },
        ),
      );
      expect(find.textContaining('private-internal-diagnostic'), findsNothing);
      await tester.ensureVisible(find.text('إعادة المحاولة'));
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pump();
      expect(attempts, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
