import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'local_models.dart';
import 'local_storage_paths.dart';

abstract interface class DocumentFileStore {
  Future<StagedDocumentFile> stageFile({
    required File source,
    required String documentId,
    required String originalFilename,
    required String mediaType,
    int? maxBytes,
  });

  Future<PublishedDocumentFile> publish(StagedDocumentFile staged);

  Future<void> discardStaging(StagedDocumentFile staged);

  Future<File?> resolve(String storedFilename);

  Future<List<String>> listStoredFilenames();

  Future<ReconciliationReport> reconcile({
    required Set<String> referencedStoredFilenames,
    Duration incompleteGrace = const Duration(hours: 24),
    DateTime? now,
  });
}

class IoDocumentFileStore implements DocumentFileStore {
  IoDocumentFileStore({required this.paths});

  static final RegExp _safeDocumentId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final RegExp _safeLeafName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  static final RegExp _safeExtension = RegExp(r'^[A-Za-z0-9]{1,10}$');
  static final RegExp _controlCharacters = RegExp(r'[\x00-\x1F\x7F]');

  final LocalStoragePaths paths;

  @override
  Future<StagedDocumentFile> stageFile({
    required File source,
    required String documentId,
    required String originalFilename,
    required String mediaType,
    int? maxBytes,
  }) async {
    if (!_safeDocumentId.hasMatch(documentId)) {
      throw const UnsafeStoragePathException(
        'The generated document identifier is not storage-safe.',
      );
    }

    await paths.ensureDirectories();

    final safeOriginalFilename = _metadataFilename(originalFilename);
    final storedFilename = _storedFilenameFor(documentId, safeOriginalFilename);
    final tempPath = p.join(paths.importsDirectory, '$documentId.part');
    _assertWithin(paths.importsDirectory, tempPath);

    if (await File(tempPath).exists()) {
      throw StorageCollisionException(
        'An incomplete import already exists for $documentId. '
        'Reconcile incomplete imports before retrying.',
      );
    }

    final tempFile = File(tempPath);
    RandomAccessFile? handle;
    final digestSink = _DigestSink();
    var sizeBytes = 0;

    try {
      handle = await tempFile.open(mode: FileMode.writeOnly);
      final hasher = sha256.startChunkedConversion(digestSink);

      await for (final chunk in source.openRead()) {
        sizeBytes += chunk.length;
        if (maxBytes != null && sizeBytes > maxBytes) {
          throw ImportFileTooLargeException(maxBytes);
        }
        hasher.add(chunk);
        await handle.writeFrom(chunk);
      }

      hasher.close();
      await handle.flush();
      await handle.close();
      handle = null;

      return StagedDocumentFile(
        documentId: documentId,
        originalFilename: safeOriginalFilename,
        storedFilename: storedFilename,
        mediaType: mediaType,
        tempPath: tempPath,
        sizeBytes: sizeBytes,
        sha256: digestSink.value.toString(),
      );
    } catch (_) {
      if (handle != null) {
        try {
          await handle.close();
        } on FileSystemException {
          // The original failure is more useful than a close failure.
        }
      }
      await _deleteIfExists(tempFile);
      rethrow;
    }
  }

  @override
  Future<PublishedDocumentFile> publish(StagedDocumentFile staged) async {
    final storedFilename = _validateLeafName(staged.storedFilename);
    final finalPath = p.join(paths.documentsDirectory, storedFilename);
    _assertWithin(paths.documentsDirectory, finalPath);

    final tempFile = File(staged.tempPath);
    _assertWithin(paths.importsDirectory, staged.tempPath);
    if (!await tempFile.exists()) {
      throw StagedFileMissingException(
        'The staged import file is missing: ${staged.tempPath}',
      );
    }

    final finalFile = File(finalPath);
    if (await finalFile.exists()) {
      throw StorageCollisionException(
        'A stored document already exists at $storedFilename.',
      );
    }

    final published = await tempFile.rename(finalPath);
    final publishedSize = await published.length();
    if (publishedSize != staged.sizeBytes) {
      throw LocalStorageException(
        'Published file size mismatch for $storedFilename '
        '($publishedSize != ${staged.sizeBytes}). The file was retained.',
      );
    }

    return PublishedDocumentFile(
      storedFilename: storedFilename,
      path: finalPath,
      sizeBytes: publishedSize,
      sha256: staged.sha256,
    );
  }

  @override
  Future<void> discardStaging(StagedDocumentFile staged) async {
    _assertWithin(paths.importsDirectory, staged.tempPath);
    if (!p.basename(staged.tempPath).endsWith('.part')) {
      throw const UnsafeStoragePathException(
        'Only staged .part files can be discarded.',
      );
    }
    await _deleteIfExists(File(staged.tempPath));
  }

  @override
  Future<File?> resolve(String storedFilename) async {
    final safeName = _validateLeafName(storedFilename);
    final path = p.join(paths.documentsDirectory, safeName);
    _assertWithin(paths.documentsDirectory, path);
    final file = File(path);
    return await file.exists() ? file : null;
  }

  @override
  Future<List<String>> listStoredFilenames() async {
    final directory = Directory(paths.documentsDirectory);
    if (!await directory.exists()) {
      return const <String>[];
    }
    final names = await directory
        .list()
        .where((entity) => entity is File)
        .map((entity) => p.basename(entity.path))
        .toList();
    names.sort();
    return names;
  }

  @override
  Future<ReconciliationReport> reconcile({
    required Set<String> referencedStoredFilenames,
    Duration incompleteGrace = const Duration(hours: 24),
    DateTime? now,
  }) async {
    await paths.ensureDirectories();
    final currentTime = (now ?? DateTime.now()).toUtc();
    final stored = await listStoredFilenames();
    final storedSet = stored.toSet();
    final movedOrphans = <String>[];
    final movedIncomplete = <String>[];
    final pendingIncomplete = <String>[];
    final missingReferenced = <String>[];
    final errors = <String>[];

    final orphanNames =
        stored
            .where((name) => !referencedStoredFilenames.contains(name))
            .toList()
          ..sort();
    for (final name in orphanNames) {
      try {
        final source = File(p.join(paths.documentsDirectory, name));
        await _moveToRecovery(
          source,
          paths.orphanedRecoveryDirectory,
          'orphan',
        );
        movedOrphans.add(name);
      } on FileSystemException catch (error) {
        errors.add('$name: ${error.message}');
      }
    }

    final stagingFiles = await _listStagingFiles();
    for (final file in stagingFiles) {
      final name = p.basename(file.path);
      try {
        final stat = await file.stat();
        final age = currentTime.difference(stat.modified.toUtc());
        if (age < incompleteGrace) {
          pendingIncomplete.add(name);
          continue;
        }
        await _moveToRecovery(
          file,
          paths.incompleteRecoveryDirectory,
          'incomplete',
        );
        movedIncomplete.add(name);
      } on FileSystemException catch (error) {
        errors.add('$name: ${error.message}');
      }
    }

    for (final name in referencedStoredFilenames) {
      if (!storedSet.contains(name)) {
        missingReferenced.add(name);
      }
    }
    missingReferenced.sort();

    return ReconciliationReport(
      movedOrphans: movedOrphans,
      movedIncomplete: movedIncomplete,
      pendingIncomplete: pendingIncomplete,
      missingReferencedFiles: missingReferenced,
      errors: errors,
    );
  }

  Future<List<File>> _listStagingFiles() async {
    final directory = Directory(paths.importsDirectory);
    if (!await directory.exists()) {
      return const <File>[];
    }
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.part'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<void> _moveToRecovery(
    File source,
    String recoveryDirectory,
    String prefix,
  ) async {
    await Directory(recoveryDirectory).create(recursive: true);
    final baseName = p.basename(source.path);
    var destination = File(p.join(recoveryDirectory, '${prefix}_$baseName'));
    var counter = 1;
    while (await destination.exists()) {
      destination = File(
        p.join(recoveryDirectory, '${prefix}_${counter}_$baseName'),
      );
      counter++;
    }
    await source.rename(destination.path);
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A stale temp file is reconciled later; never fail the original action.
    }
  }

  String _metadataFilename(String input) {
    final normalized = input.replaceAll('\\', '/');
    final base = p.basename(normalized);
    final cleaned = base
        .replaceAll(RegExp(r'[/\\]'), '')
        .replaceAll(_controlCharacters, '')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'unnamed';
    }
    return cleaned;
  }

  String _storedFilenameFor(String documentId, String originalFilename) {
    final extension = p.extension(originalFilename);
    if (extension.length > 1) {
      final candidate = extension.substring(1);
      if (_safeExtension.hasMatch(candidate)) {
        return '$documentId.${candidate.toLowerCase()}';
      }
    }
    return documentId;
  }

  String _validateLeafName(String value) {
    if (!_safeLeafName.hasMatch(value) ||
        value == '.' ||
        value == '..' ||
        p.basename(value) != value) {
      throw UnsafeStoragePathException(
        'The stored filename is not a safe leaf name: $value',
      );
    }
    return value;
  }

  void _assertWithin(String root, String candidate) {
    final normalizedRoot = p.normalize(p.absolute(root));
    final normalizedCandidate = p.normalize(p.absolute(candidate));
    if (normalizedCandidate != normalizedRoot &&
        !p.isWithin(normalizedRoot, normalizedCandidate)) {
      throw UnsafeStoragePathException(
        'Path escapes its managed storage directory: $candidate',
      );
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final result = _value;
    if (result == null) {
      throw StateError('The SHA-256 digest was not produced.');
    }
    return result;
  }

  @override
  void add(Digest data) {
    _value = data;
  }

  @override
  void close() {}
}
