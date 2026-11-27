import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/student_fee.dart';

class FeeStatusLabel extends StatelessWidget {
  final FeeStatus status;
  const FeeStatusLabel(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      FeeStatus.cleared => Colors.green,
      FeeStatus.partlyPaid => Colors.orange,
      FeeStatus.notPaid => AppColors.error,
    };
    return Text(
      status.label,
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }
}
