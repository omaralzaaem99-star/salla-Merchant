import 'package:flutter_test/flutter_test.dart';
import 'package:salla_data/salla_data.dart';

void main() {
  SallaDriverShiftSchedule schedule({
    Set<String> days = const <String>{'sat'},
    int startMinute = 8 * 60,
    int endMinute = 16 * 60,
  }) {
    return SallaDriverShiftSchedule(
      enabled: true,
      templateId: 'custom',
      label: 'اختباري',
      days: days,
      startMinute: startMinute,
      endMinute: endMinute,
    );
  }

  test('الدوام المرن لا يقيد استقبال الطلبات', () {
    final value = const SallaDriverShiftSchedule().evaluate(
      DateTime.parse('2026-08-29T03:00:00Z'),
    );
    expect(value.restricted, isFalse);
    expect(value.active, isTrue);
  });

  test('الشفت الصباحي يستخدم توقيت بغداد وحد نهاية غير شامل', () {
    final value = schedule();
    expect(
      value.evaluate(DateTime.parse('2026-08-29T05:00:00Z')).active,
      isTrue,
    );
    expect(
      value.evaluate(DateTime.parse('2026-08-29T13:00:00Z')).active,
      isFalse,
    );
  });

  test('الشفت العابر لمنتصف الليل يربط الساعات المبكرة بيوم البداية', () {
    final value = schedule(startMinute: 22 * 60, endMinute: 6 * 60);
    expect(
      value.evaluate(DateTime.parse('2026-08-29T20:30:00Z')).active,
      isTrue,
    );
    expect(
      value.evaluate(DateTime.parse('2026-08-30T02:59:00Z')).active,
      isTrue,
    );
    expect(
      value.evaluate(DateTime.parse('2026-08-30T03:00:00Z')).active,
      isFalse,
    );
  });

  test('التحويل إلى Firebase يحفظ عقداً صغيراً والأيام المختارة فقط', () {
    final saved = schedule(days: const <String>{'sat', 'mon'}).toFirebase();
    expect(saved['version'], sallaDriverShiftScheduleVersion);
    expect(saved['timeZone'], sallaDriverShiftTimeZone);
    expect(saved['days'], <String, bool>{'mon': true, 'sat': true});
    expect(saved['enabled'], isFalse);
    expect(saved['configured'], isTrue);
    expect(SallaDriverShiftSchedule.fromAdminValue(saved).days,
        <String>{'sat', 'mon'});
    expect(SallaDriverShiftSchedule.fromValue(saved).enabled, isFalse);
  });

  test('وقت العمل معلومة للإدارة ولا يقيد النسخ الحالية والقديمة للسائق', () {
    final saved =
        schedule(days: const <String>{'mon'}, startMinute: 600).toFirebase();
    final admin = SallaDriverShiftSchedule.fromAdminValue(saved);
    final driver = SallaDriverShiftSchedule.fromValue(saved);
    expect(admin.enabled, isTrue);
    expect(admin.startMinute, 600);
    expect(saved['enabled'] == true, isFalse);
    for (var hour = 0; hour < 168; hour++) {
      final now = DateTime.utc(2026, 9, 21).add(Duration(hours: hour));
      expect(driver.evaluate(now).active, isTrue);
      expect(driver.evaluate(now).restricted, isFalse);
    }
    final resaved = admin.toFirebase();
    expect(resaved, saved);
  });

  test('الجدول المحفوظ الفاسد يغلق الاستقبال بأمان', () {
    final parsed = SallaDriverShiftSchedule.fromValue(<String, Object?>{
      'enabled': true,
      'days': <String, bool>{},
      'startMinute': 480,
      'endMinute': 480,
    });
    expect(parsed.enabled, isTrue);
    expect(parsed.isValid, isFalse);
    expect(parsed.evaluate(DateTime.now()).active, isFalse);
  });
}
