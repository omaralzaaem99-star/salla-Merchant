library sala_store;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:salla_auth/salla_auth.dart';
import 'package:salla_data/salla_data.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

part 'src/data/models.dart';
part 'src/data/store_numeric_input.dart';
part 'src/pages/store_home_page.dart';
part 'src/pages/store_external_delivery.dart';
part 'src/pages/store_order_report.dart';
part 'src/pages/store_report_protection_settings.dart';
part 'src/pages/store_public_links.dart';
part 'src/pages/store_guest.dart';
part 'src/pages/store_privacy_request.dart';

const Duration _storeStartupTimeout = Duration(seconds: 25);

const appColor = Color(0xFF0C8F7B);
const orangeColor = Color(0xFFFF7A00);
const bgColor = Color(0xFFF5F7F9);
const darkText = Color(0xFF111827);
const mutedText = Color(0xFF6B7280);
const minPrepMinutes = 5;
const maxPrepMinutes = 45;
const minDispatchLeadMinutes = 0;
const maxDispatchLeadMinutes = 60;
const defaultDispatchLeadMinutes = 5;
const defaultStoreCommissionPercent = 18;
const minStoreCommissionPercent = 5;
const maxStoreCommissionPercent = 35;
late final DatabaseReference database;
late SallaIdentity sallaIdentity;
String get storeId => sallaIdentity.entityId;
String get storeName => sallaIdentity.name;

// The canonical order contains company-only financial data. Store reads use
// the existing filtered history callable and operational projection instead.
Future<Map<String, dynamic>?> readStorePublicOrder(String orderId) async {
  final expectedStoreId = storeId;
  final expectedUid = sallaIdentity.uid;
  final response = await FirebaseFunctions.instanceFor(region: 'europe-west1')
      .httpsCallable(
        'getStoreOrderHistoryPage',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      )
      .call<dynamic>({'storeId': expectedStoreId, 'orderId': orderId})
      .timeout(const Duration(seconds: 30));
  if (storeId != expectedStoreId || sallaIdentity.uid != expectedUid) {
    throw StateError('تغير حساب المتجر أثناء قراءة الطلب.');
  }
  final page = response.data;
  if (page is! Map || page['orders'] is! List) {
    throw const FormatException('استجابة قراءة الطلب غير صالحة.');
  }
  final rows = page['orders'] as List;
  if (rows.isEmpty) return null;
  if (rows.length != 1 || rows.first is! Map) {
    throw const FormatException('استجابة قراءة الطلب غير صالحة.');
  }
  final order = (rows.first as Map).map(
    (key, value) => MapEntry(key.toString(), value),
  );
  if (order['key'] != orderId || order['storeId'] != expectedStoreId) {
    throw const FormatException('استجابة قراءة الطلب لا تطابق المتجر.');
  }
  return order;
}

Stream<Map<String, dynamic>?> storePublicOrderStream({
  required Stream<Object?> projection,
  required Future<Map<String, dynamic>?> Function() readOrder,
  required String expectedStoreId,
}) => projection.asyncMap((value) async {
  // Legacy active references may not yet contain the projection. A removed
  // reference also needs a final, filtered read of the completed order.
  final order = value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : await readOrder();
  if (order != null && order['storeId'] != expectedStoreId) {
    throw const FormatException('الطلب لا يخص هذا المتجر.');
  }
  return order;
});

Stream<Map<String, dynamic>?> watchStorePublicOrder(String orderId) {
  final expectedStoreId = storeId;
  return storePublicOrderStream(
    projection: database
        .child('operationalOrderRefs')
        .child('stores')
        .child(expectedStoreId)
        .child(orderId)
        .child('publicOrder')
        .onValue
        .map((event) => event.snapshot.value),
    readOrder: () => readStorePublicOrder(orderId),
    expectedStoreId: expectedStoreId,
  );
}

Future<FirebaseApp> initializePlatformFirebase() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return Firebase.initializeApp();
  }
  return Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

int firebaseIntValue(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String sallaUtcNowIso() => DateTime.now().toUtc().toIso8601String();

int normalizedStoreCommissionPercent(int value) {
  return value
      .clamp(minStoreCommissionPercent, maxStoreCommissionPercent)
      .toInt();
}

Future<T?> waitForFirebaseResult<T>(
  Future<T> operation, {
  required String debugLabel,
  Duration timeout = const Duration(seconds: 20),
}) async {
  T? result;
  Object? failure;
  StackTrace? failureStack;
  final completed = await operation
      .then(
        (value) {
          result = value;
          return true;
        },
        onError: (Object error, StackTrace stackTrace) {
          failure = error;
          failureStack = stackTrace;
          return true;
        },
      )
      .timeout(
        timeout,
        onTimeout: () {
          debugPrint('$debugLabel timed out after ${timeout.inSeconds}s');
          return false;
        },
      );
  if (!completed) return null;
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack ?? StackTrace.current);
  }
  return result;
}

Iterable<Map<String, dynamic>> firebaseOrderItemMaps(dynamic rawItems) sync* {
  Iterable<dynamic> values;
  if (rawItems is List) {
    values = rawItems;
  } else if (rawItems is Map) {
    final entries = rawItems.entries.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a.key.toString());
        final bi = int.tryParse(b.key.toString());
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.key.toString().compareTo(b.key.toString());
      });
    values = entries.map((entry) => entry.value);
  } else {
    values = const [];
  }

  for (final rawItem in values) {
    if (rawItem is! Map) continue;
    yield rawItem.map((key, value) => MapEntry(key.toString(), value));
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final firebaseApp = Firebase.apps.isEmpty
      ? await initializePlatformFirebase()
      : Firebase.app();
  await SallaAppCheckMonitoring.activateFor(firebaseApp);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    runApp(const StoreMobileOnlyApp());
    return;
  }
  runApp(const StoreStartupApp());
  try {
    final firebaseApp = await initializePlatformFirebase().timeout(
      _storeStartupTimeout,
      onTimeout: () => throw TimeoutException(
        'انتهت مهلة الاتصال بخدمات سلة. تحقق من الإنترنت ثم أعد تشغيل التطبيق.',
      ),
    );
    await SallaAppCheckMonitoring.activateFor(firebaseApp).timeout(
      _storeStartupTimeout,
      onTimeout: () => throw TimeoutException(
        'انتهت مهلة التحقق من حماية التطبيق. تحقق من الإنترنت ثم أعد المحاولة.',
      ),
    );
    SallaAppErrorReporter.install(
      appName: 'تطبيق المتجر',
      role: SallaUserRole.store,
    );
    SallaDatabase.configure(firebaseAuth: SallaAuthService.firebaseAuth);
    database = SallaDatabase.instance.ref();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    runApp(const StoreApp());
  } catch (error, stackTrace) {
    debugPrint('Store startup failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    runApp(StoreStartupErrorApp(error: error));
  }
}

class StoreMobileOnlyApp extends StatelessWidget {
  const StoreMobileOnlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bgColor,
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_rounded, color: appColor, size: 54),
                  SizedBox(height: 14),
                  Text(
                    'تطبيق المتجر يعمل على الهاتف فقط',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'من VS Code اختر: المتجر - فايربيس (الهاتف)، وتأكد أن الهاتف متصل قبل التشغيل.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StoreStartupApp extends StatelessWidget {
  const StoreStartupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bgColor,
        fontFamily: 'Arial',
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(backgroundColor: bgColor, body: _StoreStartupSurface()),
      ),
    );
  }
}

class _StoreStartupSurface extends StatelessWidget {
  const _StoreStartupSurface();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF5F7F9), Color(0xFFE6F6F1), Color(0xFFFFFFFF)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: -92,
              right: -68,
              child: _StoreStartupGlow(size: 252, color: Color(0x200C8F7B)),
            ),
            const Positioned(
              bottom: -122,
              left: -82,
              child: _StoreStartupGlow(size: 292, color: Color(0x16FF7A00)),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 36,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x260C8F7B),
                              blurRadius: 36,
                              offset: Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Semantics(
                          image: true,
                          label: 'شعار تطبيق سلة للتجار',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(36),
                            child: Image.asset(
                              'assets/images/salla_store_app_icon.png',
                              width: 124,
                              height: 124,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      const Text(
                        'سلة للتجار',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: darkText,
                          fontSize: 31,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'كل طلب تحت السيطرة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: appColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0x1A0C8F7B)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: orangeColor,
                                strokeWidth: 2.8,
                              ),
                            ),
                            SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'نجهز الطلبات والقائمة والإشعارات',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: mutedText,
                                  fontWeight: FontWeight.w800,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreStartupGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _StoreStartupGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class StoreStartupErrorApp extends StatelessWidget {
  final Object error;

  const StoreStartupErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bgColor,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red,
                    size: 46,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'تعذر تشغيل تطبيق المتجر',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StoreApp extends StatelessWidget {
  const StoreApp({super.key});

  Future<void> _requestMerchantAccount(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StoreApplicationPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'سلة للتجار',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bgColor,
        colorScheme: ColorScheme.fromSeed(seedColor: appColor),
        fontFamily: 'Arial',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF17202A),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      home: StoreAccessEntry(
        authBuilder: (explore) => SallaAuthGate(
          expectedRole: SallaUserRole.store,
          loginMode: SallaLoginMode.phone,
          allowRegistration: true,
          loginFooter: Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: explore,
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('استكشف التطبيق بدون حساب'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _requestMerchantAccount(context),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text(
                    'إنشاء حساب',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: appColor,
                    side: const BorderSide(color: appColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                const StorePublicLinks(compact: true),
              ],
            ),
          ),
          authenticatedBuilder: (context, identity) {
            sallaIdentity = identity;
            return const Directionality(
              textDirection: TextDirection.rtl,
              child: StoreHomePage(),
            );
          },
        ),
      ),
    );
  }
}
