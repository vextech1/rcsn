import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/setup_provider.dart';

/// Shown while the app finds out whether the school has a Principal yet,
/// and when that check fails (usually no internet).
class SetupCheckScreen extends StatelessWidget {
  const SetupCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SetupProvider>();
    final failed = setup.status == SetupStatus.error;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Could not reach the school server.',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Check your internet connection and try again.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => context.read<SetupProvider>().check(),
                      child: const Text('Try again'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
