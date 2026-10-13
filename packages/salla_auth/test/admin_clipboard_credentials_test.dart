import 'package:flutter_test/flutter_test.dart';
import 'package:salla_auth/salla_auth.dart';

void main() {
  test('يلصق عقد بطاقة الموظف في حقول دخول الإدارة من دون إعادة كتابة', () {
    final parsed = parseSallaAdminClipboardCredentials('''
بيانات دخول لوحة الإدارة
الاسم: موظف اختبار
الهاتف: 07700000000
رمز الربط: LINK-100
رمز الدخول: login 200
الدور: موظف الطلبات
''');

    expect(parsed, isNotNull);
    expect(parsed!.requestedName, 'موظف اختبار');
    expect(parsed.phone, '+9647700000000');
    expect(parsed.linkCode, 'LINK100');
    expect(parsed.loginCode, 'LOGIN200');
  });

  test('يرفض نصاً عادياً أو بيانات موظف ناقصة', () {
    expect(parseSallaAdminClipboardCredentials('نص عادي'), isNull);
    expect(
      parseSallaAdminClipboardCredentials('''
بيانات دخول لوحة الإدارة
الاسم: موظف اختبار
الهاتف: 07700000000
رمز الربط: LINK100
'''),
      isNull,
    );
  });
}
