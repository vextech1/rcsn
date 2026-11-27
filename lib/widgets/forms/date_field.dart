import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A date chosen from a calendar, held in [controller] as YYYY-MM-DD.
class DateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const DateField({super.key, required this.controller, required this.label});

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text) ?? DateTime(2005),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      // Typing is quicker than scrolling back many years.
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        readOnly: true,
        onTap: () => _pick(context),
        validator: (v) => (v ?? '').isEmpty ? 'Choose the date' : null,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today),
        ),
      );
}
