import 'package:salla_data/salla_data.dart';
import 'package:test/test.dart';

void main() {
  int? score(String query, List<String> labels) =>
      sallaArabicPlaceSearchScore(query, labels);

  test('empty query and exact names/aliases retain the best score', () {
    expect(score('', ['المنصور']), 0);
    expect(score('   ', []), 0);
    expect(score('  الكرادة  ', ['الكرادة الشرقية', 'الكرادة']), 0);
    expect(score('مدينة الصدر', ['الثورة', 'مدينة الصدر']), 0);
  });
  test('place normalization handles Arabic and Kurdish character variants', () {
    expect(score('الأَعْظَمِيَّة', ['الاعظميه']), 0);
    expect(score('کَرّادة', ['كراده']), 0);
    expect(score('حي موسی', ['حي موسى']), 0);
    expect(score('رؤوف', ['رووف']), 0);
    expect(score('الکرادة، الداخلة', ['الكرادة الداخله']), 0);
    // Keep the old public normalizer's contract unchanged.
    expect(sallaNormalizeArabicSearchText('ک ی ؤ ئ'), 'ک ی ؤ ئ');
  });
  test('partial and multiword input match in any order', () {
    expect(score('منص', ['المنصور']), 1);
    expect(score('داخل كراد', ['الكرادة الداخلة']), 1);
    expect(score('الأولى أمين', ['الأمين الأولى']), 1);
    expect(score('شارع حي المنصور', ['المنصور']), 1);
    expect(score('مجمع الامل السكني', ['الأمل']), 1);
    expect(score('مدينة', ['مدينة الصدر']), 1);
    expect(score('حي شارع', ['المنصور']), isNull);
  });
  test('one substitution, deletion, insertion or adjacent swap is a typo', () {
    expect(score('المنصوؤ', ['المنصور']), 2);
    expect(score('المنصر', ['المنصور']), 2);
    expect(score('المنصوور', ['المنصور']), 2);
    expect(score('المصنور', ['المنصور']), 2);
    expect(score('الداخلة الكرادع', ['الكرادة الداخلة']), 2);
    expect(score('مجمع المنصرو السكني', ['المنصور']), 2);
    expect(score('منصرو', ['حي المنصور']), 2);
    expect(score('منصر', ['المنصور']), 2);
    expect(score('الكرح', ['الكرخ']), isNull);
  });
  test('short queries are strict and distant names do not become suggestions',
      () {
    expect(score('حي', ['حي الجامعة']), 1);
    expect(score('حر', ['حي']), isNull);
    expect(score('كرذ', ['كراد']), isNull);
    expect(score('بغداد', ['البصرة']), isNull);
    expect(score('المنصور', ['الزعفرانية']), isNull);
    expect(score('المصنور الكرادع', ['المنصور الكرادة']), isNull);
    expect(
        score('الجديدة الشرقية', ['بغداد الجديدة', 'الكرادة الشرقية']), isNull);
  });
  test('strict alias beats fuzzy alias and input bounds never truncate', () {
    expect(score('المنصور', ['المنصر', 'حي المنصور']), 1);
    expect(score('المنصور', ['المنصر', 'المنصور']), 0);
    expect(score('المنصور${'x' * 101}', ['المنصور']), isNull);
    expect(score('منصور', ['${'x' * 257} منصور']), isNull);
    expect(
        score('منصور', ['${List.filled(17, 'حي').join(' ')} منصور']), isNull);
  });
}
