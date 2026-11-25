import 'package:flutter/material.dart';
import '../../core/errors/app_failure.dart';
import '../common/app_error_display.dart';

/// A labeled text field with built-in [AppInlineError] wiring.
///
/// Exists so form screens — NSIN entry, Tutor login/register, Admin
/// setup — don't each separately wire up "show an inline error beneath
/// this field if [error] is non-null." Passing an [AppFailure] directly
/// (rather than a String) keeps the typed-error convention from
/// core/errors/ flowing all the way to the smallest form field, matching
/// the same reasoning as AppErrorDisplay in widgets/common/.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType keyboardType;
  final AppFailure? error;
  final void Function(String)? onChanged;
  final String? Function(String?)? validator;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.error,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onChanged: onChanged,
          validator: validator,
          decoration: InputDecoration(labelText: label),
        ),
        if (error != null) AppInlineError(failure: error!),
      ],
    );
  }
}
