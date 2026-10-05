import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  test(
    'filtered stream handles old refs and final history without exposing canonical reads',
    () async {
      var reads = 0;
      final values = await storePublicOrderStream(
        projection: Stream<Object?>.fromIterable([
          null,
          {'storeId': 'store-a', 'status': 'preparing'},
          null,
        ]),
        expectedStoreId: 'store-a',
        readOrder: () async => {
          'storeId': 'store-a',
          'status': ++reads == 1 ? 'accepted' : 'delivered',
        },
      ).toList();
      expect(values.map((value) => value?['status']), [
        'accepted',
        'preparing',
        'delivered',
      ]);
      expect(reads, 2);
    },
  );

  test(
    'failed or foreign filtered read is not diagnosed as an absent order',
    () async {
      await expectLater(
        storePublicOrderStream(
          projection: Stream<Object?>.value(null),
          expectedStoreId: 'store-a',
          readOrder: () async => throw StateError('network-unknown'),
        ),
        emitsError(isA<StateError>()),
      );
      await expectLater(
        storePublicOrderStream(
          projection: Stream<Object?>.value({'storeId': 'store-b'}),
          expectedStoreId: 'store-a',
          readOrder: () async => null,
        ),
        emitsError(isA<FormatException>()),
      );
    },
  );
  test(
    'subscription config keeps private contract fields out of the model',
    () {
      final config = StoreExternalDeliveryConfiguration.fromMap({
        'enabled': true,
        'requiresDeliveryPin': true,
        'subscription': {
          'status': 'active',
          'startsAt': '2026-09-09T00:00:00Z',
          'endsAt': '2026-10-09T00:00:00Z',
        },
        'areas': [
          {'id': 'mansour', 'nameAr': 'المنصور', 'requiresDeliveryPin': true},
        ],
      });
      expect(config.requiresDeliveryPin, isTrue);
      expect(config.subscriptionStatus, 'active');
      expect(config.subscriptionEndsAt?.month, 10);
      expect(config.areas.single.requiresDeliveryPin, isTrue);
      expect(
        StoreExternalDeliveryConfiguration.fromMap({}).subscriptionStatus,
        'none',
      );
    },
  );

  testWidgets(
    'full order number wraps in narrow RTL with large text and copies once',
    (tester) async {
      const number = 'EXT-5F678149-1234567890';
      var copied = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SizedBox(
                  width: 145,
                  child: StoreOrderNumberLabel(
                    number: number,
                    onCopy: () => copied++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text(number));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.textDirection, TextDirection.ltr);
      await tester.tap(find.text(number));
      expect(copied, 1);
    },
  );
}
