import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves every local file under one app-private root.
///
/// Android's application-support directory is internal storage owned by the
/// app. No shared-storage or SAF permission is requested for normal use.
class LocalStoragePaths {
  LocalStoragePaths({required String rootDirectory})
    : rootDirectory = p.normalize(p.absolute(rootDirectory));

  final String rootDirectory;

  String get databaseFile => p.join(rootDirectory, 'lore.sqlite');
  String get documentsDirectory => p.join(rootDirectory, 'documents');
  String get importsDirectory => p.join(rootDirectory, 'imports');
  String get processingDirectory => p.join(rootDirectory, 'processing');
  String get recoveryDirectory => p.join(rootDirectory, 'recovery');
  String get orphanedRecoveryDirectory => p.join(recoveryDirectory, 'orphaned');
  String get incompleteRecoveryDirectory =>
      p.join(recoveryDirectory, 'incomplete');

  Future<void> ensureDirectories() async {
    for (final path in <String>[
      rootDirectory,
      documentsDirectory,
      importsDirectory,
      processingDirectory,
      orphanedRecoveryDirectory,
      incompleteRecoveryDirectory,
    ]) {
      await Directory(path).create(recursive: true);
    }
  }

  static Future<LocalStoragePaths> forApplication() async {
    final support = await getApplicationSupportDirectory();
    return LocalStoragePaths(rootDirectory: p.join(support.path, 'lore_local'));
  }
}
