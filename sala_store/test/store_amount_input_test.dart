import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sala_store/main.dart';

void main() {
  test('Arabic and Persian phone digits preserve zeros, prefix and cursor', () {
    const formatter = StorePhoneInputFormatter();
    for (final input in ['٠٧٧١٢٣٤٥٦٧٨', '۰۷۷۱۲۳۴۵۶۷۸']) {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: input,
          selection: const TextSelection.collapsed(offset: 4),
        ),
      );
      expect(result.text, '07712345678');
      expect(result.selection.baseOffset, 4);
    }
    expect(normalizeStoreInputDigits('+٩٦٤ ٧٧١-٢٣٤-٥٦٧٨'), '+964 771-234-5678');
    expect(normalizeStoreInputDigits(''), '');
    expect(normalizeStoreInputDigits('07712345678'), '07712345678');
  });
  const formatter = StoreAmountInputFormatter();
  TextEditingValue value(String text, [int? cursor]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor ?? text.length),
  );

  test('groups typed and pasted Latin, Arabic and Persian integer amounts', () {
    for (final input in ['15000', '١٥٠٠٠', '۱۵۰۰۰', '15,000', '١٥٬٠٠٠']) {
      final result = formatter.formatEditUpdate(value(''), value(input));
      expect(result.text, '15,000');
      expect(result.selection.baseOffset, 6);
      expect(parseStoreAmountInput(result.text), 15000);
    }
    expect(formatStoreAmountInput('100000000'), '100,000,000');
    expect(formatStoreAmountInput('0'), '0');
    expect(formatStoreAmountInput(''), '');
    expect(parseStoreAmountInput(''), isNull);
  });

  test('keeps middle edits and selection near their original digits', () {
    final result = formatter.formatEditUpdate(
      value('12,345', 2),
      value('129,345', 3),
    );
    expect(result.text, '129,345');
    expect(result.selection.baseOffset, 3);
    final selected = formatter.formatEditUpdate(
      value(''),
      const TextEditingValue(
        text: '12345',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      ),
    );
    expect(
      selected.selection,
      const TextSelection(baseOffset: 1, extentOffset: 5),
    );
  });

  test(
    'backspace over separator moves caret so the next deletion can proceed',
    () {
      final result = formatter.formatEditUpdate(
        value('1,000', 2),
        value('1000', 1),
      );
      expect(result.text, '1,000');
      expect(result.selection.baseOffset, 1);
      final deleted = formatter.formatEditUpdate(result, value(',000', 0));
      expect(deleted.text, '000');
      expect(deleted.selection.baseOffset, 0);
      expect(formatter.formatEditUpdate(deleted, value('')).text, '');
    },
  );

  test(
    'does not turn decimal, negative or invalid text into a different price',
    () {
      final old = value('1,500');
      for (final input in ['1.5', '١٫٥', '-1500', '15abc', '1e3']) {
        expect(formatter.formatEditUpdate(old, value(input)), old);
        expect(parseStoreAmountInput(input), isNull);
      }
    },
  );
}
