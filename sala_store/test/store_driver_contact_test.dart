import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

Widget page(String phone, Future<bool> Function(Uri) open) => MaterialApp(
  home: Scaffold(
    body: Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: 320,
        child: StoreDriverContact(phone: phone, openLink: open),
      ),
    ),
  ),
);

void main() {
  testWidgets('compact support button opens the existing support phone', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              StoreSupportCallButton(
                openLink: (uri) async {
                  opened = uri;
                  return true;
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('الاتصال بالدعم'));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'tel:+9647775655367');
    expect(
      tester.getSize(find.byType(StoreSupportCallButton)).width,
      lessThanOrEqualTo(48),
    );
  });
  testWidgets('Arabic phone opens dialer and WhatsApp for the same driver', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      page('٠٧٧٠١٢٣٤٥٦٧', (uri) async {
        opened.add(uri);
        return true;
      }),
    );
    await tester.tap(find.text('+9647701234567'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('واتساب السائق'));
    await tester.pumpAndSettle();
    expect(opened.map((u) => u.toString()), [
      'tel:+9647701234567',
      'https://wa.me/9647701234567',
    ]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unavailable number exposes no contact action', (tester) async {
    for (final phone in ['', 'غير متوفر', '1234']) {
      await tester.pumpWidget(
        page(phone, (_) async {
          fail('must not launch');
        }),
      );
      expect(find.byType(TextButton), findsNothing);
    }
  });
  testWidgets('failed launch offers selectable number and retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      page('07701234567', (_) async {
        calls++;
        return calls > 1;
      }),
    );
    await tester.tap(find.text('واتساب السائق'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    await tester.tap(find.text('واتساب السائق'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(SelectableText), findsNothing);
  });
  testWidgets('launch is single flight and completion after close is safe', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      page('+9647701234567', (_) {
        calls++;
        return pending.future;
      }),
    );
    await tester.tap(find.text('واتساب السائق'));
    await tester.pump();
    await tester.tap(find.text('+9647701234567'));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
