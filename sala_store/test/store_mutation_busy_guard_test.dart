import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('تحديثات المنتج تمنع الضغط المتكرر وتعيد فتح الأزرار بعد النهاية', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _setProductAvailability');
    final end = source.indexOf('String _productOfferRequestId', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final section = source.substring(start, end);
    expect(section, contains('_busyProductIds.contains(product.id)'));
    expect(section, contains('_busyProductIds.add(product.id)'));
    expect(section, contains('_busyProductIds.remove(product.id)'));
    expect(section, contains('finally'));
    expect(section, contains("'manageStoreMenu'"));
    expect(section, contains("action: 'setProductAvailability'"));
    expect(section, contains("action: 'setProductStock'"));
    expect(section, contains("'expectedRevision': product.revision"));
    expect(section, contains('.timeout(const Duration(seconds: 30))'));
    expect(section, isNot(contains('database.update(')));
    expect(section, contains('on TimeoutException'));
    expect(section, contains('_showUncertainMutationMessage'));
  });

  test('إعدادات التحضير والتوزيع محمية وتعرض فشل الاتصال', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _setPrepMinutes');
    final end = source.indexOf('Future<void> _setProductAvailability', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final section = source.substring(start, end);
    expect(section, contains("_busyStoreSettingKeys.contains(actionKey)"));
    expect(section, contains("_busyStoreSettingKeys.add(actionKey)"));
    expect(section, contains("_busyStoreSettingKeys.remove(actionKey)"));
    expect(section, contains('تعذر تحديث وقت التحضير'));
    expect(section, contains('تعذر تحديث التوزيع التلقائي'));
    expect(section, contains('تعذر تحديث توقيت التوزيع'));
    expect(
      RegExp(r'\.timeout\(_storeMutationWriteTimeout\)').allMatches(section),
      hasLength(3),
    );
    expect(source, contains('النتيجة غير مؤكدة'));
    expect(source, contains('لن يعيد التطبيق الكتابة تلقائياً'));
    expect(section, isNot(contains('commissionPercent')));
    expect(
      section,
      isNot(contains("'storeCatalog/\$storeId/autoDispatchEnabled'")),
    );
    expect(
      section,
      isNot(contains("'storeCatalog/\$storeId/dispatchLeadMinutes'")),
    );
  });

  test('أزرار المنتجات والإعدادات تتعطل أثناء الحفظ', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();

    expect(
      RegExp(
        '_busyProductIds.contains\\(product.id\\)',
      ).allMatches(source).length,
      greaterThanOrEqualTo(7),
    );
    expect(source, contains("_busyStoreSettingKeys.contains('prep_minutes')"));
    expect(source, contains("_busyStoreSettingKeys.contains('auto_dispatch')"));
    expect(
      source,
      contains(
        "_busyStoreSettingKeys.contains(\n"
        "                            'dispatch_lead_minutes',",
      ),
    );
  });
}
