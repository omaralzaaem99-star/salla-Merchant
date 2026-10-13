import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salla_auth/salla_auth.dart';

void main() {
  testWidgets(
    'الحوار الآمن لا يعيد النتيجة قبل إزالة طبقة الانتقال',
    (tester) async {
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                unawaited(
                  showSallaLifecycleSafeDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('حوار اختبار'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('إغلاق'),
                        ),
                      ],
                    ),
                  ).then((_) => returned = true),
                );
              },
              child: const Text('فتح الحوار'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('فتح الحوار'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إغلاق'));
      await tester.pump();

      expect(returned, isFalse);
      expect(find.text('حوار اختبار'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(find.text('حوار اختبار'), findsNothing);
    },
  );

  testWidgets(
    'النافذة السفلية الآمنة تؤخر التخلص من حقول الكتابة حتى اكتمال الخروج',
    (tester) async {
      final controller = TextEditingController(text: 'قيمة آمنة');
      var disposed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                final sheet = showSallaLifecycleSafeModalBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(controller: controller),
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('إغلاق النافذة'),
                        ),
                      ],
                    ),
                  ),
                );
                unawaited(
                  sheet.whenComplete(() {
                    controller.dispose();
                    disposed = true;
                  }),
                );
              },
              child: const Text('فتح النافذة'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('فتح النافذة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إغلاق النافذة'));
      await tester.pump();

      expect(disposed, isFalse);
      expect(find.text('قيمة آمنة'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(disposed, isTrue);
      expect(find.text('قيمة آمنة'), findsNothing);
    },
  );
}
