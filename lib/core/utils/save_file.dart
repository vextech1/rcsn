import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Lets the user choose where on the phone to keep [bytes], and says how it
/// went.
Future<void> saveToPhone(
  BuildContext context,
  String fileName,
  Uint8List bytes,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final path = await FilePicker.platform
        .saveFile(fileName: fileName, bytes: bytes);
    if (path != null) {
      messenger.showSnackBar(SnackBar(content: Text('Saved $fileName')));
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not save the file.')),
    );
  }
}
