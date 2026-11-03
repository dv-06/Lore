import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/local/document_file_store.dart';
import 'package:lore_mobile/data/local/document_import_coordinator.dart';
import 'package:lore_mobile/data/local/document_repository.dart';
import 'package:lore_mobile/data/local/local_database.dart';
import 'package:lore_mobile/data/local/local_models.dart';
import 'package:lore_mobile/data/local/local_storage_paths.dart';

final List<int> _binaryBytes = List<int>.generate(512, (index) => index % 256);

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

LocalStoragePaths _paths(Directory root) =>
    LocalStoragePaths(rootDirectory: root.path);

Future<File> _writeSource(
  Directory directory,
  String name,
  List<int> bytes,
) async {
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<List<String>> _listNames(String directoryPath) async {
  final directory = Directory(directoryPath);
  if (!await directory.exists()) {
    return const <String>[];
  }
  final names = await directory
      .list()
      .where((entity) => entity is File)
      .map((entity) => entity.uri.pathSegments.last)
      .toList();
  names.sort();
  return names;
}

class _FaultyDocumentRepository implements DocumentRepository {
  _FaultyDocumentRepository(
    this.inner, {
    this.failInsert = false,
    this.failLookup = false,
  });

  final DocumentRepository inner;
  final bool failInsert;
  final bool failLookup;

  @override
  Future<void> insert(LocalDocument document) async {
    if (failInsert) {
      throw StateError('simulated metadata failure');
    }
    return inner.insert(document);
  }

  @override
  Future<LocalDocument?> findBySha256(String sha256) async {
    if (failLookup) {
      throw StateError('simulated lookup failure');
    }
    return inner.findBySha256(sha256);
  }

  @override
  Future<LocalDocument?> findById(String id) => inner.findById(id);

  @override
  Future<List<LocalDocument>> listActive({int limit = 100, int offset = 0}) =>
      inner.listActive(limit: limit, offset: offset);

  @override
  Future<List<LocalDocument>> listPending({int limit = 100}) =>
      inner.listPending(limit: limit);

  @override
  Future<void> applyProcessingUpdate({
    required String documentId,
    required ProcessingUpdate update,
    DateTime? updatedAt,
  }) => inner.applyProcessingUpdate(
    documentId: documentId,
    update: update,
    updatedAt: updatedAt,
  );

  @override
  Future<bool> tryClaimForProcessing({
    required String documentId,
    Duration staleAfter = const Duration(minutes: 15),
    DateTime? now,
  }) => inner.tryClaimForProcessing(
    documentId: documentId,
    staleAfter: staleAfter,
    now: now,
  );

  @override
  Future<int> resetStaleProcessing({
    Duration staleAfter = const Duration(minutes: 15),
    DateTime? now,
    String? message,
  }) => inner.resetStaleProcessing(
    staleAfter: staleAfter,
    now: now,
    message: message,
  );

  @override
  Future<void> updateExtraction({
    required String documentId,
    required String extractedText,
    required ExtractionStatus status,
    String? error,
    int? pageCount,
    DateTime? updatedAt,
  }) => inner.updateExtraction(
    documentId: documentId,
    extractedText: extractedText,
    status: status,
    error: error,
    pageCount: pageCount,
    updatedAt: updatedAt,
  );

  @override
  Future<void> softDelete(String documentId, {DateTime? deletedAt}) =>
      inner.softDelete(documentId, deletedAt: deletedAt);

  @override
  Future<void> hardDelete(String documentId) => inner.hardDelete(documentId);

  @override
  Future<int> countActive() => inner.countActive();

  @override
  Future<Set<String>> listStoredFilenames({bool includeDeleted = true}) =>
      inner.listStoredFilenames(includeDeleted: includeDeleted);
}

void main() {
  late Directory tempDir;
  late Directory sourceDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lore_file_store');
    sourceDir = await Directory.systemTemp.createTemp('lore_file_source');
  });

  tearDown(() async {
    for (final directory in <Directory>[tempDir, sourceDir]) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  group('staging and publishing', () {
    test('copies original bytes and computes the SHA-256 digest', () async {
      final paths = _paths(tempDir);
      final store = IoDocumentFileStore(paths: paths);
      final source = await _writeSource(sourceDir, 'Scan.PDF', _binaryBytes);

      final staged = await store.stageFile(
        source: source,
        documentId: 'doc-1',
        originalFilename: 'Scan.PDF',
        mediaType: 'application/pdf',
      );

      expect(staged.storedFilename, 'doc-1.pdf');
      expect(staged.originalFilename, 'Scan.PDF');
      expect(staged.sizeBytes, _binaryBytes.length);
      expect(staged.sha256, _sha(_binaryBytes));
      expect(staged.tempPath, endsWith('doc-1.part'));

      final tempBytes = await File(staged.tempPath).readAsBytes();
      expect(tempBytes, _binaryBytes);
      expect(await File(source.path).readAsBytes(), _binaryBytes);

      final published = await store.publish(staged);
      expect(published.storedFilename, 'doc-1.pdf');
      expect(published.sha256, staged.sha256);
      expect(await File(staged.tempPath).exists(), isFalse);
      expect(await File(published.path).readAsBytes(), _binaryBytes);
      expect(await _listNames(paths.documentsDirectory), ['doc-1.pdf']);
      expect(await _listNames(paths.importsDirectory), isEmpty);

      final resolved = await store.resolve('doc-1.pdf');
      expect(resolved, isNotNull);
      expect(await resolved!.readAsBytes(), _binaryBytes);
    });

    test(
      'rejects oversized files and removes the partial staging file',
      () async {
        final paths = _paths(tempDir);
        final store = IoDocumentFileStore(paths: paths);
        final source = await _writeSource(
          sourceDir,
          'large.bin',
          List<int>.filled(64, 1),
        );

        await expectLater(
          store.stageFile(
            source: source,
            documentId: 'doc-1',
            originalFilename: 'large.bin',
            mediaType: 'application/octet-stream',
            maxBytes: 16,
          ),
          throwsA(isA<ImportFileTooLargeException>()),
        );

        expect(await _listNames(paths.importsDirectory), isEmpty);
        expect(await _listNames(paths.documentsDirectory), isEmpty);
      },
    );

    test('a missing source fails without leaving a staging file', () async {
      final paths = _paths(tempDir);
      final store = IoDocumentFileStore(paths: paths);

      await expectLater(
        store.stageFile(
          source: File('${sourceDir.path}/does-not-exist.pdf'),
          documentId: 'doc-1',
          originalFilename: 'missing.pdf',
          mediaType: 'application/pdf',
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await _listNames(paths.importsDirectory), isEmpty);
    });

    test('rejects unsafe document identifiers before writing', () async {
      final paths = _paths(tempDir);
      final store = IoDocumentFileStore(paths: paths);
      final source = await _writeSource(
        sourceDir,
        'a.txt',
        utf8.encode('hello'),
      );

      for (final identifier in <String>[
        '../escape',
        'a/b',
        r'a\b',
        '',
        'x' * 65,
      ]) {
        await expectLater(
          store.stageFile(
            source: source,
            documentId: identifier,
            originalFilename: 'a.txt',
            mediaType: 'text/plain',
          ),
          throwsA(isA<UnsafeStoragePathException>()),
        );
      }
      expect(await _listNames(paths.importsDirectory), isEmpty);
    });

    test(
      'sanitizes metadata filenames and derives a safe stored name',
      () async {
        final paths = _paths(tempDir);
        final store = IoDocumentFileStore(paths: paths);
        final source = await _writeSource(
          sourceDir,
          'a.txt',
          utf8.encode('hello'),
        );

        final traversal = await store.stageFile(
          source: source,
          documentId: 'doc-1',
          originalFilename: r'..\..\private\Tax Return 2025.PDF',
          mediaType: 'application/pdf',
        );
        expect(traversal.originalFilename, 'Tax Return 2025.PDF');
        expect(traversal.storedFilename, 'doc-1.pdf');

        await store.discardStaging(traversal);

        final control = await store.stageFile(
          source: source,
          documentId: 'doc-2',
          originalFilename: 'bad\u0000name\u001f.txt',
          mediaType: 'text/plain',
        );
        expect(control.originalFilename, 'badname.txt');

        await store.discardStaging(control);

        final unnamed = await store.stageFile(
          source: source,
          documentId: 'doc-3',
          originalFilename: '////',
          mediaType: 'application/octet-stream',
        );
        expect(unnamed.originalFilename, 'unnamed');
        expect(unnamed.storedFilename, 'doc-3');
      },
    );

    test('publish never overwrites an existing file', () async {
      final paths = _paths(tempDir);
      final store = IoDocumentFileStore(paths: paths);
      final source = await _writeSource(sourceDir, 'a.txt', utf8.encode('new'));
      final staged = await store.stageFile(
        source: source,
        documentId: 'doc-1',
        originalFilename: 'a.txt',
        mediaType: 'text/plain',
      );
      await File(
        '${paths.documentsDirectory}/doc-1.txt',
      ).writeAsString('existing');

      await expectLater(
        store.publish(staged),
        throwsA(isA<StorageCollisionException>()),
      );
      expect(
        await File('${paths.documentsDirectory}/doc-1.txt').readAsString(),
        'existing',
      );
      expect(await File(staged.tempPath).exists(), isTrue);
    });

    test('publish rejects tampered paths and a missing staged file', () async {
      final paths = _paths(tempDir);
      final store = IoDocumentFileStore(paths: paths);
      final source = await _writeSource(
        sourceDir,
        'a.txt',
        utf8.encode('data'),
      );
      final staged = await store.stageFile(
        source: source,
        documentId: 'doc-1',
        originalFilename: 'a.txt',
        mediaType: 'text/plain',
      );

      final escapingName = StagedDocumentFile(
        documentId: staged.documentId,
        originalFilename: staged.originalFilename,
        storedFilename: '../escape.txt',
        mediaType: staged.mediaType,
        tempPath: staged.tempPath,
        sizeBytes: staged.sizeBytes,
        sha256: staged.sha256,
      );
      await expectLater(
        store.publish(escapingName),
        throwsA(isA<UnsafeStoragePathException>()),
      );

      final escapingTemp = StagedDocumentFile(
        documentId: staged.documentId,
        originalFilename: staged.originalFilename,
        storedFilename: staged.storedFilename,
        mediaType: staged.mediaType,
        tempPath: '${sourceDir.path}/doc-1.part',
        sizeBytes: staged.sizeBytes,
        sha256: staged.sha256,
      );
      await expectLater(
        store.publish(escapingTemp),
        throwsA(isA<UnsafeStoragePathException>()),
      );

      await File(staged.tempPath).delete();
      await expectLater(
        store.publish(staged),
        throwsA(isA<StagedFileMissingException>()),
      );
    });

    test(
      'discardStaging only removes staging files inside the import area',
      () async {
        final paths = _paths(tempDir);
        final store = IoDocumentFileStore(paths: paths);
        final source = await _writeSource(
          sourceDir,
          'a.txt',
          utf8.encode('data'),
        );
        final staged = await store.stageFile(
          source: source,
          documentId: 'doc-1',
          originalFilename: 'a.txt',
          mediaType: 'text/plain',
        );

        final published = StagedDocumentFile(
          documentId: staged.documentId,
          originalFilename: staged.originalFilename,
          storedFilename: 'doc-1.txt',
          mediaType: staged.mediaType,
          tempPath: '${paths.documentsDirectory}/doc-1.txt',
          sizeBytes: staged.sizeBytes,
          sha256: staged.sha256,
        );
        await File(published.tempPath).writeAsString('keep');
        await expectLater(
          store.discardStaging(published),
          throwsA(isA<UnsafeStoragePathException>()),
        );
        expect(await File(published.tempPath).exists(), isTrue);

        await store.discardStaging(staged);
        expect(await File(staged.tempPath).exists(), isFalse);
      },
    );
  });

  group('resolve and listing', () {
    test('resolve validates stored names and reports missing files', () async {
      final paths = _paths(tempDir);
      final store = IoDocumentFileStore(paths: paths);
      await paths.ensureDirectories();

      expect(await store.resolve('missing.pdf'), isNull);
      for (final name in <String>['../secret', 'a/b.txt', r'a\b.txt', '']) {
        await expectLater(
          store.resolve(name),
          throwsA(isA<UnsafeStoragePathException>()),
        );
      }

      await File('${paths.documentsDirectory}/b.txt').writeAsString('b');
      await File('${paths.documentsDirectory}/a.txt').writeAsString('a');
      expect(await store.listStoredFilenames(), ['a.txt', 'b.txt']);
    });
  });

  group('import coordinator', () {
    late LoreDatabase database;
    late DriftDocumentRepository repository;
    late IoDocumentFileStore store;
    var counter = 0;

    String nextId() => 'doc-${++counter}';

    setUp(() async {
      database = LoreDatabase.inMemory();
      await database.customSelect('SELECT 1').getSingle();
      repository = DriftDocumentRepository(database);
      store = IoDocumentFileStore(paths: _paths(tempDir));
      counter = 0;
    });

    tearDown(() async {
      await database.close();
    });

    test('imports bytes, persists metadata and detects duplicates', () async {
      final coordinator = DocumentImportCoordinator(
        documents: repository,
        fileStore: store,
        idGenerator: nextId,
        clock: () => DateTime.utc(2026, 2, 1),
      );
      final source = await _writeSource(sourceDir, 'invoice.pdf', _binaryBytes);

      final result = await coordinator.importFile(
        source: source,
        originalFilename: 'invoice.pdf',
        mediaType: 'application/pdf',
      );

      expect(result.document.id, 'doc-1');
      expect(result.document.sha256, _sha(_binaryBytes));
      expect(result.document.extractionStatus, ExtractionStatus.pending);
      expect(result.document.createdAt, DateTime.utc(2026, 2, 1));
      expect(result.file.storedFilename, 'doc-1.pdf');
      expect(await File(result.file.path).readAsBytes(), _binaryBytes);

      final stored = await repository.findById('doc-1');
      expect(stored, isNotNull);
      expect(stored!.sizeBytes, _binaryBytes.length);
      expect(await repository.countActive(), 1);

      await expectLater(
        coordinator.importFile(
          source: source,
          originalFilename: 'renamed-invoice.pdf',
          mediaType: 'application/pdf',
        ),
        throwsA(
          isA<DuplicateDocumentException>().having(
            (error) => error.existing.id,
            'existing id',
            'doc-1',
          ),
        ),
      );

      expect(await repository.countActive(), 1);
      expect(await _listNames(_paths(tempDir).documentsDirectory), [
        'doc-1.pdf',
      ]);
      expect(await _listNames(_paths(tempDir).importsDirectory), isEmpty);
    });

    test('different bytes are imported as distinct documents', () async {
      final coordinator = DocumentImportCoordinator(
        documents: repository,
        fileStore: store,
        idGenerator: nextId,
      );
      final first = await _writeSource(sourceDir, 'a.bin', [1, 2, 3]);
      final second = await _writeSource(sourceDir, 'b.bin', [4, 5, 6]);

      final firstResult = await coordinator.importFile(
        source: first,
        originalFilename: 'a.bin',
        mediaType: 'application/octet-stream',
      );
      final secondResult = await coordinator.importFile(
        source: second,
        originalFilename: 'b.bin',
        mediaType: 'application/octet-stream',
      );

      expect(firstResult.document.id, 'doc-1');
      expect(secondResult.document.id, 'doc-2');
      expect(await repository.countActive(), 2);
      expect(await _listNames(_paths(tempDir).documentsDirectory), [
        'doc-1.bin',
        'doc-2.bin',
      ]);
    });

    test('missing staged data does not create a document', () async {
      final source = await _writeSource(
        sourceDir,
        'a.txt',
        utf8.encode('data'),
      );
      final staged = await store.stageFile(
        source: source,
        documentId: 'doc-1',
        originalFilename: 'a.txt',
        mediaType: 'text/plain',
      );
      await File(staged.tempPath).delete();

      await expectLater(
        store.publish(staged),
        throwsA(isA<StagedFileMissingException>()),
      );
      expect(await repository.countActive(), 0);
    });

    test(
      'retains the published file when metadata persistence fails',
      () async {
        final faulty = _FaultyDocumentRepository(repository, failInsert: true);
        final coordinator = DocumentImportCoordinator(
          documents: faulty,
          fileStore: store,
          idGenerator: nextId,
        );
        final source = await _writeSource(
          sourceDir,
          'a.txt',
          utf8.encode('data'),
        );

        late ImportPersistenceException failure;
        try {
          await coordinator.importFile(
            source: source,
            originalFilename: 'a.txt',
            mediaType: 'text/plain',
          );
          fail('Import should have failed.');
        } on ImportPersistenceException catch (error) {
          failure = error;
        }

        expect(failure.retainedFilePath, contains('documents'));
        expect(await File(failure.retainedFilePath).exists(), isTrue);
        expect(await File(failure.retainedFilePath).readAsString(), 'data');
        expect(await repository.countActive(), 0);
        expect(await _listNames(_paths(tempDir).documentsDirectory), [
          'doc-1.txt',
        ]);
      },
    );

    test('retains the staged file when duplicate detection fails', () async {
      final faulty = _FaultyDocumentRepository(repository, failLookup: true);
      final coordinator = DocumentImportCoordinator(
        documents: faulty,
        fileStore: store,
        idGenerator: nextId,
      );
      final source = await _writeSource(
        sourceDir,
        'a.txt',
        utf8.encode('data'),
      );

      late ImportPersistenceException failure;
      try {
        await coordinator.importFile(
          source: source,
          originalFilename: 'a.txt',
          mediaType: 'text/plain',
        );
        fail('Import should have failed.');
      } on ImportPersistenceException catch (error) {
        failure = error;
      }

      expect(failure.retainedFilePath, endsWith('doc-1.part'));
      expect(await File(failure.retainedFilePath).exists(), isTrue);
      expect(await _listNames(_paths(tempDir).importsDirectory), [
        'doc-1.part',
      ]);
      expect(await _listNames(_paths(tempDir).documentsDirectory), isEmpty);
    });

    test(
      'reconcile quarantines orphans and stale incomplete imports',
      () async {
        final paths = _paths(tempDir);
        final coordinator = DocumentImportCoordinator(
          documents: repository,
          fileStore: store,
          idGenerator: nextId,
        );
        final source = await _writeSource(
          sourceDir,
          'kept.txt',
          utf8.encode('kept'),
        );
        final imported = await coordinator.importFile(
          source: source,
          originalFilename: 'kept.txt',
          mediaType: 'text/plain',
        );

        final orphan = File('${paths.documentsDirectory}/orphan.txt');
        await orphan.writeAsString('orphan bytes');
        final stale = File('${paths.importsDirectory}/stale.part');
        await stale.writeAsString('partial');
        final fresh = File('${paths.importsDirectory}/fresh.part');
        await fresh.writeAsString('partial');
        final now = DateTime.utc(2026, 3, 1);
        await stale.setLastModified(now.subtract(const Duration(hours: 48)));
        await fresh.setLastModified(now.subtract(const Duration(minutes: 5)));

        final report = await coordinator.reconcile(now: now);

        expect(report.movedOrphans, ['orphan.txt']);
        expect(report.movedIncomplete, ['stale.part']);
        expect(report.pendingIncomplete, ['fresh.part']);
        expect(report.missingReferencedFiles, isEmpty);
        expect(report.errors, isEmpty);
        expect(report.hasChanges, isTrue);

        expect(await File(imported.file.path).exists(), isTrue);
        expect(await orphan.exists(), isFalse);
        expect(await stale.exists(), isFalse);
        expect(await fresh.exists(), isTrue);
        expect(await _listNames(paths.orphanedRecoveryDirectory), [
          'orphan_orphan.txt',
        ]);
        expect(await _listNames(paths.incompleteRecoveryDirectory), [
          'incomplete_stale.part',
        ]);
      },
    );

    test(
      'reconcile reports missing referenced files without deleting records',
      () async {
        final paths = _paths(tempDir);
        final coordinator = DocumentImportCoordinator(
          documents: repository,
          fileStore: store,
          idGenerator: nextId,
        );
        await repository.insert(
          LocalDocument(
            id: 'doc-1',
            originalFilename: 'gone.txt',
            storedFilename: 'doc-1.txt',
            mediaType: 'text/plain',
            sizeBytes: 4,
            sha256: _sha(utf8.encode('gone')),
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await paths.ensureDirectories();

        final report = await coordinator.reconcile();

        expect(report.missingReferencedFiles, ['doc-1.txt']);
        expect(report.movedOrphans, isEmpty);
        expect(await repository.findById('doc-1'), isNotNull);
        expect(
          await File('${paths.documentsDirectory}/doc-1.txt').exists(),
          isFalse,
        );
      },
    );
  });
}
