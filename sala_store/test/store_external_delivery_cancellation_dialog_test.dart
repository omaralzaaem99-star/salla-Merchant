import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  testWidgets(
    'متحكم سبب إلغاء الطلب الخارجي يبقى حياً حتى انتهاء إغلاق النافذة',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 780);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showStoreExternalCancellationReasonDialog(
                    context,
                    orderNumber: 'EXT-TEST',
                  );
                },
                child: const Text('إلغاء الطلب'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('إلغاء الطلب'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('store_external_cancel_reason')),
        'تعذر التسليم إلى المستلم',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('store_external_cancel_confirm')),
      );

      // The previous flow disposed a local controller as soon as the dialog
      // Future completed while the reverse route animation still rebuilt it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      expect(result, 'تعذر التسليم إلى المستلم');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('سبب الإلغاء الفارغ يبقى داخل النافذة ولا يبدأ العملية', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showStoreExternalCancellationReasonDialog(
                context,
                orderNumber: 'EXT-EMPTY',
              ),
              child: const Text('فتح'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('store_external_cancel_confirm')),
    );
    await tester.pump();

    expect(find.text('اكتب سبب الإلغاء أولاً.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('store_external_cancel_reason')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
