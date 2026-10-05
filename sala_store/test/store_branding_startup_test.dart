import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  testWidgets('شاشة بدء المتجر واضحة على شاشة ضيقة وتكبير نص', (tester) async {
    await _setViewport(tester, width: 320, height: 568, textScale: 1.4);
    await tester.pumpWidget(const StoreStartupApp());
    await tester.pump();

    expect(find.text('سلة للتجار'), findsOneWidget);
    expect(find.text('كل طلب تحت السيطرة'), findsOneWidget);
    expect(find.text('نجهز الطلبات والقائمة والإشعارات'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/salla_store_app_icon.png',
    );
    expect(tester.takeException(), isNull);
  });

  test('يعرض المتجر أول إطار قبل تهيئة Firebase بلا انتظار مصطنع', () {
    final source = File('lib/main.dart').readAsStringSync();
    final mainStart = source.indexOf('Future<void> main() async');
    final mainEnd = source.indexOf('class StoreMobileOnlyApp', mainStart);
    expect(mainStart, greaterThanOrEqualTo(0));
    expect(mainEnd, greaterThan(mainStart));
    final body = source.substring(mainStart, mainEnd);

    expect(body, contains('runApp(const StoreStartupApp())'));
    expect(
      body.indexOf('runApp(const StoreStartupApp())'),
      lessThan(body.indexOf('await initializePlatformFirebase()')),
    );
    expect(body, isNot(contains('Future.delayed')));
  });

  test('شعار المتجر الجديد صالح ومربوط بموارد Android', () async {
    const assetPath = 'assets/images/salla_store_app_icon.png';
    final asset = File(assetPath);
    expect(asset.existsSync(), isTrue);
    final codec = await ui.instantiateImageCodec(await asset.readAsBytes());
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 384);
    expect(frame.image.height, 384);
    frame.image.dispose();
    codec.dispose();

    _expectAndroidBrandingResources();
  });

  test('اسم تطبيق المتجر إنجليزي ومتناسق من دون تغيير هوية الحزمة', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();

    expect(gradle, contains('applicationId = "com.selafood.store"'));
    expect(gradle, contains('"Salla Merchant Dev"'));
    expect(gradle, contains('"Salla Merchant"'));
    expect(gradle, isNot(contains('Salla Shop')));
    expect(gradle, isNot(contains('Sela Food Store')));
    expect(iosInfo, contains('<string>Salla Merchant</string>'));
    expect(iosInfo, isNot(contains('Salla Shop')));
    expect(iosInfo, isNot(contains('<string>متجر سلة</string>')));
    expect(iosInfo, isNot(contains('<string>Salla Store</string>')));
    expect(iosInfo, isNot(contains('<string>Sela Shop</string>')));
  });

  test('أيقونة مشغل المتجر ممتدة اللون بلا زوايا شفافة', () async {
    await _expectOpaqueAndroidLauncher();
  });

  test('رسم أيقونة المتجر المتكيفة مصغر ومتناسق داخل الخلفية', () async {
    await _expectInsetAdaptiveForeground();
  });
}

void _expectAndroidBrandingResources() {
  for (final density in const <String>[
    'mdpi',
    'hdpi',
    'xhdpi',
    'xxhdpi',
    'xxxhdpi',
  ]) {
    expect(
      File(
        'android/app/src/main/res/mipmap-$density/ic_launcher.png',
      ).existsSync(),
      isTrue,
      reason: density,
    );
    expect(
      File(
        'android/app/src/main/res/mipmap-$density/ic_launcher_round.png',
      ).existsSync(),
      isTrue,
      reason: density,
    );
    expect(
      File(
        'android/app/src/main/res/mipmap-$density/'
        'ic_launcher_foreground.png',
      ).existsSync(),
      isTrue,
      reason: density,
    );
    expect(
      File(
        'android/app/src/main/res/drawable-$density/salla_launch_logo.png',
      ).existsSync(),
      isTrue,
      reason: density,
    );
  }
  for (final path in const <String>[
    'android/app/src/main/res/drawable/launch_background.xml',
    'android/app/src/main/res/drawable-v21/launch_background.xml',
  ]) {
    expect(
      File(path).readAsStringSync(),
      contains('@drawable/salla_launch_logo'),
      reason: path,
    );
  }
  for (final path in const <String>[
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
  ]) {
    final source = File(path).readAsStringSync();
    expect(source, contains('<adaptive-icon'), reason: path);
    expect(source, contains('@mipmap/ic_launcher_foreground'), reason: path);
    expect(
      source,
      contains('@color/salla_store_icon_background'),
      reason: path,
    );
  }
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
}

Future<void> _expectOpaqueAndroidLauncher() async {
  for (final density in const <String>[
    'mdpi',
    'hdpi',
    'xhdpi',
    'xxhdpi',
    'xxxhdpi',
  ]) {
    final bytes = await File(
      'android/app/src/main/res/mipmap-$density/ic_launcher.png',
    ).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final rgba = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(rgba, isNotNull, reason: density);
    expect(rgba!.getUint8(3), 255, reason: '$density top-left alpha');
    final lastAlpha = (frame.image.width * frame.image.height * 4) - 1;
    expect(
      rgba.getUint8(lastAlpha),
      255,
      reason: '$density bottom-right alpha',
    );
    frame.image.dispose();
    codec.dispose();
  }
}

Future<void> _expectInsetAdaptiveForeground() async {
  for (final density in const <String>[
    'mdpi',
    'hdpi',
    'xhdpi',
    'xxhdpi',
    'xxxhdpi',
  ]) {
    final bytes = await File(
      'android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png',
    ).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final rgba = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(rgba, isNotNull, reason: density);
    expect(rgba!.getUint8(3), 0, reason: '$density top-left alpha');
    final centerPixel =
        ((frame.image.height ~/ 2) * frame.image.width +
            frame.image.width ~/ 2) *
        4;
    expect(rgba.getUint8(centerPixel + 3), 255, reason: '$density center');
    frame.image.dispose();
    codec.dispose();
  }
}

Future<void> _setViewport(
  WidgetTester tester, {
  required double width,
  required double height,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
