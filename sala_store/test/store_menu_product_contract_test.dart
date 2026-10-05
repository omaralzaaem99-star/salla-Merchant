import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  test('نموذج منتج المتجر يحتفظ بالمحتوى والصورة والترتيب والمراجعة', () {
    final product = StoreProduct.fromFirebase('product-1', {
      'name': 'وجبة دجاج',
      'category': 'الوجبات',
      'categoryId': 'meals',
      'categoryDisplayOrder': 2,
      'categoryActive': true,
      'displayOrder': 4,
      'description': 'وجبة كاملة',
      'unit': 'وجبة',
      'imagePath': 'https://example.test/large.jpg',
      'thumbImagePath': 'https://example.test/thumb.jpg',
      'price': 9000,
      'available': true,
      'stockQuantity': 8,
      'archived': false,
      'revision': 12,
    });

    expect(product.categoryId, 'meals');
    expect(product.categoryDisplayOrder, 2);
    expect(product.displayOrder, 4);
    expect(product.description, 'وجبة كاملة');
    expect(product.unit, 'وجبة');
    expect(product.preferredThumbnailPath, 'https://example.test/thumb.jpg');
    expect(product.revision, 12);
    expect(product.canManageAvailability, isTrue);
  });

  test('المؤرشف والقسم المتوقف يظهران كنموذج لكن لا يقبلان التفعيل', () {
    final archived = StoreProduct.fromFirebase('archived', {
      'name': 'قديم',
      'category': 'عام',
      'price': 1000,
      'available': true,
      'archived': true,
    });
    final inactiveCategory = StoreProduct.fromFirebase('inactive', {
      'name': 'متوقف',
      'category': 'عام',
      'price': 1000,
      'available': true,
      'categoryActive': false,
    });

    expect(archived.available, isFalse);
    expect(archived.canManageAvailability, isFalse);
    expect(inactiveCategory.available, isFalse);
    expect(inactiveCategory.canManageAvailability, isFalse);
  });

  test('ترتيب القائمة يحترم ترتيب القسم ثم الصنف', () {
    const products = [
      StoreProduct(
        id: '3',
        name: 'ج',
        category: 'ب',
        categoryDisplayOrder: 2,
        displayOrder: 1,
        price: 1,
        available: true,
      ),
      StoreProduct(
        id: '2',
        name: 'ب',
        category: 'أ',
        categoryDisplayOrder: 1,
        displayOrder: 2,
        price: 1,
        available: true,
      ),
      StoreProduct(
        id: '1',
        name: 'أ',
        category: 'أ',
        categoryDisplayOrder: 1,
        displayOrder: 1,
        price: 1,
        available: true,
      ),
    ];
    final sorted = [...products]..sort(compareStoreMenuProducts);
    expect(sorted.map((item) => item.id), ['1', '2', '3']);
  });

  test('التوفر والمخزون يمران حصراً عبر callable موثوق ومراجع', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();
    final start = source.indexOf('  Future<void> _setProductAvailability(');
    final end = source.indexOf('  String _productOfferRequestId(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final mutationSection = source.substring(start, end);

    expect(mutationSection, contains("'manageStoreMenu'"));
    expect(mutationSection, contains("action: 'setProductAvailability'"));
    expect(mutationSection, contains("action: 'setProductStock'"));
    expect(mutationSection, contains("'expectedRevision': product.revision"));
    expect(mutationSection, contains("'requestId': operationRequestId"));
    expect(
      mutationSection,
      contains('requestId ?? _storeMenuRequestId(product, action, value)'),
    );
    expect(mutationSection, isNot(contains('database.update')));
    expect(mutationSection, isNot(contains("'stores/\$storeId/products/")));
    expect(mutationSection, contains('إعادة المحاولة'));
    expect(mutationSection, contains("reason == 'store_menu_stale_revision'"));
    expect(
      mutationSection,
      isNot(contains("error.code == 'failed-precondition' ||")),
    );
    expect(mutationSection, contains('_safeStoreMenuFunctionMessage(error)'));
  });

  test('واجهة المتجر تعرض المصغرة والمحتوى وحالة الأرشفة بلا تحميل دائم', () {
    final source = File(
      'lib/src/pages/store_home_page.dart',
    ).readAsStringSync();

    expect(source, contains('product.preferredThumbnailPath'));
    expect(source, contains('product.description'));
    expect(source, contains('صنف مؤرشف — للقراءة فقط'));
    expect(source, contains('_productsLiveStatus'));
    expect(source, contains('تعذر تحديث منتجات المتجر'));
    expect(source, contains('لا توجد منتجات مسجلة لهذا المتجر حالياً'));
  });
}
