import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('تحقق الجلسة المحلية يقرأ السجلات المستقلة بالتوازي مرة واحدة', () {
    final source = File('lib/salla_auth.dart').readAsStringSync();
    final start = source.indexOf(
      '  static Future<SallaIdentity> validateLocalIdentity(',
    );
    final end = source.indexOf(
      '  static Future<void> saveLocalIdentity(',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);

    expect(body, contains('Future.wait<DataSnapshot>'));
    expect(body, contains(".child('userRoleProfiles')"));
    expect(body, contains(".child('userProfiles')"));
    expect(body, contains('.child(entityCollection)'));
    expect(body, contains('hasPrefetchedEntityValue: true'));
  });
}
