import 'package:flutter/services.dart';

/// For any field that takes a username: lowercases as it's typed and drops
/// anything [Username] wouldn't allow (a pasted "@" included).
final usernameInputFormatters = <TextInputFormatter>[
  _LowerCaseFormatter(),
  FilteringTextInputFormatter.allow(RegExp('[a-z0-9_]')),
];

/// Shows what will be stored as it's typed, instead of silently
/// lowercasing on save.
class _LowerCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toLowerCase());
  }
}
