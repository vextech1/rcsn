import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/errors/app_failure.dart';
import '../../data/models/uhpab.dart';
import '../../data/repositories/uhpab_repository.dart';
import '../../data/services/storage_service.dart';

/// Downloads a result document and opens it. Students pass [studentNsin];
/// staff use their sign-in.
Future<void> openResultDocument(
  BuildContext context,
  String nsin,
  UhpabDocument document, {
  String? studentNsin,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Opening...')));
  try {
    final folder = await getTemporaryDirectory();
    final file = await StorageService().downloadForOffline(
      storagePath: UhpabRepository.pathOf(nsin, document),
      localPath: '${folder.path}/${document.id}_${document.name}',
      studentNsin: studentNsin,
    );
    final result = await OpenFilex.open(file.path);
    messenger.hideCurrentSnackBar();
    if (result.type != ResultType.done) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No app on this phone can open this file.')),
      );
    }
  } on AppFailure catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  }
}
