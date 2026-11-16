import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Menampilkan ulang keyboard saat field yang sudah fokus diketuk lagi.
void showSoftKeyboard({FocusNode? focusNode}) {
  focusNode?.requestFocus();
  Future<void>.delayed(const Duration(milliseconds: 80), () {
    if (focusNode != null && !focusNode.hasFocus) return;
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  });
}
