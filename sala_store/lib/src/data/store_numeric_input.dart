part of '../../main.dart';

String normalizeStoreInputDigits(String text) {
  return String.fromCharCodes(
    text.runes.map((rune) {
      if (rune >= 0x660 && rune <= 0x669) return rune - 0x660 + 0x30;
      if (rune >= 0x6f0 && rune <= 0x6f9) return rune - 0x6f0 + 0x30;
      return rune;
    }),
  );
}

String _storeAmountDigits(String text) =>
    normalizeStoreInputDigits(text).replaceAll(RegExp(r'[,\u066c\s]'), '');

/// Preserve leading zeros, country codes and phone formatting; only map digits.
class StorePhoneInputFormatter extends TextInputFormatter {
  const StorePhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    return newValue.copyWith(text: normalizeStoreInputDigits(newValue.text));
  }
}

int? parseStoreAmountInput(String text) {
  final digits = _storeAmountDigits(text);
  if (!RegExp(r'^[0-9]+$').hasMatch(digits)) return null;
  return int.tryParse(digits);
}

String formatStoreAmountInput(String text) {
  final digits = _storeAmountDigits(text);
  if (!RegExp(r'^[0-9]*$').hasMatch(digits)) return text;
  return digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
}

/// Display-only grouping; call parseStoreAmountInput before sending amounts.
class StoreAmountInputFormatter extends TextInputFormatter {
  const StoreAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final digits = _storeAmountDigits(newValue.text);
    // Reject decimal points/signs rather than silently changing their value.
    if (!RegExp(r'^[0-9]*$').hasMatch(digits)) return oldValue;
    final formatted = formatStoreAmountInput(digits);
    int offset(int position) {
      if (position < 0) return formatted.length;
      final count = _storeAmountDigits(
        newValue.text.substring(0, math.min(position, newValue.text.length)),
      ).length;
      if (count == 0) return 0;
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != ',') seen++;
        if (seen == count) return i + 1;
      }
      return formatted.length;
    }

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }
}
