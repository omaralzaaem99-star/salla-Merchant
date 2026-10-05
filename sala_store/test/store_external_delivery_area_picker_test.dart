import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';
import 'package:salla_data/salla_data.dart';

void main() {
  testWidgets('البحث يقبل اسم المنطقة ومرادفاتها العربية', (tester) async {
    final area = StoreExternalDeliveryArea.fromMap({
      'id': 'bgd_bismayah',
      'nameAr': 'بسماية',
      'aliases': ['مدينة بسماية', 'بسمايه', 'بسمية'],
      'immediateFee': 2500,
      'scheduledFee': 5000,
      'distanceKm': 8,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showStoreExternalDeliveryAreaPicker(context, areas: [area]),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('store_external_area_search'));
    await tester.enterText(search, 'بسمايه');
    await tester.pump();
    expect(find.text('بسماية'), findsOneWidget);
    await tester.enterText(search, 'مدينة بسماية');
    await tester.pump();
    expect(find.text('بسماية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('البحث يعرض المطابقة قبل المشابه ثم الأقرب دون اختيار تلقائي', (
    tester,
  ) async {
    StoreExternalDeliveryArea area(String id, String name, double distance) =>
        StoreExternalDeliveryArea(
          id: id,
          nameAr: name,
          aliases: const [],
          immediateFee: 2500,
          scheduledFee: 5000,
          distanceKm: distance,
        );
    StoreExternalDeliveryArea? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showStoreExternalDeliveryAreaPicker(
                  context,
                  areas: [
                    area('similar', 'المنصورة', 1),
                    area('exact', 'المنصور', 8),
                    area('unrelated', 'البصرة', 0),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('store_external_area_search'));
    await tester.enterText(search, 'المنصور');
    await tester.pump();
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('store_external_area_exact')))
          .dy,
      lessThan(tester.getTopLeft(find.text('المنصورة')).dy),
    );
    expect(find.text('البصرة'), findsNothing);
    await tester.enterText(search, 'المنصرو');
    await tester.pump();
    expect(find.text('المنصور'), findsOneWidget);
    expect(selected, isNull);
    await tester.tap(find.text('المنصور'));
    await tester.pumpAndSettle();
    expect(selected!.id, 'exact');
    expect(tester.takeException(), isNull);
  });
  testWidgets('المناطق حسب قربها من المتجر مع حفظ البحث والسعر والاختيار', (
    tester,
  ) async {
    StoreExternalDeliveryArea area(String id, Object? distance) =>
        StoreExternalDeliveryArea.fromMap({
          'id': id,
          'nameAr': 'حي $id',
          'aliases': ['مجمع $id'],
          if (distance != null) 'distanceKm': distance,
          'immediateFee': 2500,
          'scheduledFee': 5000,
        });
    var areas = [area('a', 9), area('b', 0), area('c', null)];
    StoreExternalDeliveryArea? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showStoreExternalDeliveryAreaPicker(
                  context,
                  areas: areas,
                  selectedAreaId: 'a',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('حي b')).dy,
      lessThan(tester.getTopLeft(find.text('حي a')).dy),
    );
    expect(
      tester.getTopLeft(find.text('حي a')).dy,
      lessThan(tester.getTopLeft(find.text('حي c')).dy),
    );
    expect(selected, isNull);
    expect(areas.map((a) => a.id), ['a', 'b', 'c']);
    await tester.enterText(
      find.byKey(const ValueKey('store_external_area_search')),
      'مجمع a',
    );
    await tester.pump();
    expect(find.text('حي b'), findsNothing);
    await tester.tap(find.text('حي a'));
    await tester.pumpAndSettle();
    expect(selected, same(areas.first));
    expect(selected!.immediateFee, 2500);
    expect(selected!.scheduledFee, 5000);
    // Another store receives different trusted distances, including ties and
    // unusable data. No previously selected area is promoted above closer ones.
    areas = [area('b', 4), area('a', 4), area('c', -1), area('d', 'NaN')];
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('حي a')).dy,
      lessThan(tester.getTopLeft(find.text('حي b')).dy),
    );
    expect(
      tester.getTopLeft(find.text('حي b')).dy,
      lessThan(tester.getTopLeft(find.text('حي c')).dy),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'اسم الدبوس يرتب قرب النقطة ولا يختار تلقائيا أو يعرض سعر المنطقة',
    (tester) async {
      StoreExternalDeliveryArea area(
        String id,
        double? lat,
        double storeDistance,
      ) => StoreExternalDeliveryArea.fromMap({
        'id': id,
        'nameAr': id,
        'distanceKm': storeDistance,
        'immediateFee': 9500,
        'scheduledFee': 5000,
        if (lat != null) 'pricingAnchor': {'lat': lat, 'lng': 44.3},
      });
      StoreExternalDeliveryArea? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showStoreExternalDeliveryAreaPicker(
                    context,
                    areas: [
                      area('far', 33.5, 1),
                      area('missing', null, 0),
                      area('near', 33.31, 20),
                    ],
                    labelPoint: const SallaGeoPoint(33.31, 44.3),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.text(formatIqd(9500)), findsNothing);
      expect(find.text('اختيار الاسم فقط'), findsNWidgets(3));
      expect(
        tester.getTopLeft(find.text('near')).dy,
        lessThan(tester.getTopLeft(find.text('far')).dy),
      );
      expect(
        tester.getTopLeft(find.text('far')).dy,
        lessThan(tester.getTopLeft(find.text('missing')).dy),
      );
      await tester.tap(find.text('near'));
      await tester.pumpAndSettle();
      expect(selected?.id, 'near');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('اختيار المنطقة لا يعيد لوحة أرقام مبلغ البضاعة', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final amountFocus = FocusNode();
    addTearDown(amountFocus.dispose);
    StoreExternalDeliveryArea? selected;
    const area = StoreExternalDeliveryArea(
      id: 'area_keyboard_guard',
      nameAr: 'منطقة اختبار التركيز',
      aliases: <String>[],
      immediateFee: 2500,
      scheduledFee: 5000,
      distanceKm: 4,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: appColor),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  key: const ValueKey<String>('store_external_goods_field'),
                  focusNode: amountFocus,
                  keyboardType: TextInputType.number,
                ),
                FilledButton(
                  onPressed: () async {
                    selected = await showStoreExternalDeliveryAreaPicker(
                      context,
                      areas: const <StoreExternalDeliveryArea>[area],
                    );
                  },
                  child: const Text('افتح المناطق'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.showKeyboard(
      find.byKey(const ValueKey<String>('store_external_goods_field')),
    );
    expect(amountFocus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('افتح المناطق'));
    await tester.pumpAndSettle();
    expect(amountFocus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('store_external_area_area_keyboard_guard'),
      ),
    );
    await tester.pumpAndSettle();

    expect(selected?.id, area.id);
    expect(amountFocus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('منتقي المناطق يبقي متحكم البحث حياً أثناء الرجوع والاختيار', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final areas = List<StoreExternalDeliveryArea>.generate(
      120,
      (index) => StoreExternalDeliveryArea(
        id: 'area_$index',
        nameAr: 'منطقة $index',
        aliases: <String>['حي $index'],
        immediateFee: 2000 + (index * 500),
        scheduledFee: 5000,
        distanceKm: index / 2,
      ),
      growable: false,
    );
    StoreExternalDeliveryArea? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: appColor),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  selected = await showStoreExternalDeliveryAreaPicker(
                    context,
                    areas: areas,
                    selectedAreaId: selected?.id ?? '',
                  );
                },
                child: const Text('اختر المنطقة'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('اختر المنطقة'));
    await tester.pumpAndSettle();
    final search = find.byKey(
      const ValueKey<String>('store_external_area_search'),
    );
    await tester.showKeyboard(search);
    await tester.enterText(search, '42');
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('store_external_area_area_42')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('اختر المنطقة'));
    await tester.pumpAndSettle();
    final reopenedSearch = find.byKey(
      const ValueKey<String>('store_external_area_search'),
    );
    await tester.showKeyboard(reopenedSearch);
    await tester.enterText(reopenedSearch, '42');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('store_external_area_area_42')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(selected?.id, 'area_42');
    expect(tester.takeException(), isNull);
  });
}
