import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/local/local_models.dart';
import 'package:lore_mobile/data/local/local_storage.dart';
import 'package:lore_mobile/data/local/local_storage_paths.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lore_local_storage');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'open creates app-private directories and reports diagnostics',
    () async {
      final paths = LocalStoragePaths(
        rootDirectory: '${tempDir.path}/lore_local',
      );
      final storage = await LocalStorage.open(
        paths: paths,
        idGenerator: () => 'doc-1',
      );

      try {
        expect(await Directory(paths.documentsDirectory).exists(), isTrue);
        expect(await Directory(paths.importsDirectory).exists(), isTrue);
        expect(await Directory(paths.recoveryDirectory).exists(), isTrue);

        final diagnostics = await storage.diagnostics();
        expect(diagnostics.databasePath, paths.databaseFile);
        expect(diagnostics.schemaVersion, 2);
        expect(diagnostics.sqliteVersion, isNotEmpty);
        expect(diagnostics.fts5Compiled, isTrue);
        expect(diagnostics.fts5TablePresent, isTrue);
        expect(diagnostics.fts5Usable, isTrue);
        expect(diagnostics.documentCount, 0);
        expect(diagnostics.indexedDocumentCount, 0);
      } finally {
        await storage.close();
      }
    },
  );

  test('imported documents persist and reindex across reopen', () async {
    final paths = LocalStoragePaths(
      rootDirectory: '${tempDir.path}/lore_local',
    );
    final source = File('${tempDir.path}/receipt.txt');
    await source.writeAsString(
      'Annual insurance premium receipt.',
      flush: true,
    );

    var storage = await LocalStorage.open(
      paths: paths,
      idGenerator: () => 'doc-1',
    );
    String storedPath;
    try {
      final result = await storage.imports.importFile(
        source: source,
        originalFilename: 'receipt.txt',
        mediaType: 'text/plain',
      );
      storedPath = result.file.path;
      expect(
        await File(storedPath).readAsString(),
        'Annual insurance premium receipt.',
      );

      var diagnostics = await storage.diagnostics();
      expect(diagnostics.documentCount, 1);
      expect(diagnostics.indexedDocumentCount, 1);
      expect(await storage.search.search('premium'), isEmpty);

      await storage.documents.updateExtraction(
        documentId: 'doc-1',
        extractedText: 'Annual insurance premium receipt.',
        status: ExtractionStatus.ready,
      );
      final results = await storage.search.search('premium');
      expect(results.single.documentId, 'doc-1');
    } finally {
      await storage.close();
    }

    storage = await LocalStorage.open(paths: paths);
    try {
      expect(await File(storedPath).exists(), isTrue);
      final document = await storage.documents.findById('doc-1');
      expect(document, isNotNull);
      expect(document!.extractionStatus, ExtractionStatus.ready);
      expect(
        (await storage.search.search('insurance')).single.documentId,
        'doc-1',
      );
      expect((await storage.diagnostics()).documentCount, 1);
    } finally {
      await storage.close();
    }
  });
}
