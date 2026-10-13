import 'package:salla_data/salla_data.dart';
import 'package:test/test.dart';

void main() {
  test('مرجع بغداد المشترك يفتح غداً 05:00Z وينتهي 17:00Z', () {
    final window = sallaNextBaghdadCourierWindow(
      now: DateTime.parse('2026-08-13T10:00:00.000Z'),
      opensAtMinute: 8 * 60,
    );

    expect(
      window.dispatchStartsAt,
      DateTime.parse('2026-08-14T05:00:00.000Z'),
    );
    expect(
      window.deliveryEndsAt,
      DateTime.parse('2026-08-14T17:00:00.000Z'),
    );
  });

  test('نافذة اليوم التالي تثبت على فتح بغداد وتعبر السنة بأمان', () {
    final window = sallaNextBaghdadCourierWindow(
      now: DateTime.utc(2026, 12, 31, 20, 30),
      opensAtMinute: 8 * 60,
    );

    expect(window.dispatchStartsAt, DateTime.utc(2027, 1, 1, 5));
    expect(window.deliveryEndsAt, DateTime.utc(2027, 1, 1, 17));
  });

  test('ترفض دقيقة فتح أو مدة غير صالحة', () {
    expect(
      () => sallaNextBaghdadCourierWindow(
        now: DateTime.utc(2026, 8, 21),
        opensAtMinute: 1440,
      ),
      throwsArgumentError,
    );
    expect(
      () => sallaNextBaghdadCourierWindow(
        now: DateTime.utc(2026, 8, 21),
        opensAtMinute: 480,
        durationHours: 0,
      ),
      throwsArgumentError,
    );
  });
}
