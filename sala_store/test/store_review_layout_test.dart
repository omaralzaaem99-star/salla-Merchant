import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1024, 768),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('review entry and deletion fit $size at text scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Widget host(Widget child) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: child,
        );
        await tester.pumpWidget(
          host(StoreExplorePage(onLogin: () {}, onApply: () {})),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final readyFilter = find.widgetWithText(ChoiceChip, 'الجاهزة');
        await tester.ensureVisible(readyFilter);
        await tester.pumpAndSettle();
        await tester.tap(readyFilter);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(readyFilter).selected, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          host(StoreApplicationPage(load: () async => null)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        var writes = 0;
        await tester.pumpWidget(
          host(
            StorePrivacyRequestPage(
              storeId: 'review-fixture',
              call: (payload) async {
                if (payload['action'] != 'scheduled_privacy_status') writes++;
                return {'ok': true, 'request': null};
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byType(CheckboxListTile), 180);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('حذف الحساب وتسجيل الخروج'),
          120,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('حذف الحساب وتسجيل الخروج'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('تراجع'));
        await tester.tap(find.text('تراجع'));
        await tester.pumpAndSettle();
        expect(writes, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
