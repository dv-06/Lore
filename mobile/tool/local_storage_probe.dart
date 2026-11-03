import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:lore_mobile/data/local/local_models.dart';
import 'package:lore_mobile/data/local/local_storage.dart';
import 'package:lore_mobile/data/local/local_storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  final List<_Check> _checks = <_Check>[];
  bool _running = true;
  String _reportPath = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _expect(String name, bool condition, [String detail = '']) {
    _checks.add(_Check(name: name, passed: condition, detail: detail));
    setState(() {});
  }

  Future<void> _run() async {
    final support = await getApplicationSupportDirectory();
    final paths = LocalStoragePaths(
      rootDirectory: p.join(support.path, 'lore_probe_run'),
    );
    if (await Directory(paths.rootDirectory).exists()) {
      await Directory(paths.rootDirectory).delete(recursive: true);
    }

    var storage = await LocalStorage.open(
      paths: paths,
      idGenerator: _nextId,
      clock: () => DateTime.utc(2026, 4, 1),
    );
    try {
      final diagnostics = await storage.diagnostics();
      _expect(
        'Android release uses SQLite with FTS5 compiled',
        diagnostics.fts5Compiled,
        'sqlite ${diagnostics.sqliteVersion}',
      );
      _expect(
        'FTS5 virtual table exists after migration',
        diagnostics.fts5TablePresent && diagnostics.fts5Usable,
      );
      _expect('Schema version is 1', diagnostics.schemaVersion == 1);
      _expect(
        'Fresh database starts empty',
        diagnostics.documentCount == 0 &&
            diagnostics.indexedDocumentCount == 0,
      );

      final sourceBytes = List<int>.generate(1024, (index) => index % 256);
      final source = File(p.join(support.path, 'probe_source.bin'));
      await source.writeAsBytes(sourceBytes, flush: true);
      final expectedSha = sha256.convert(sourceBytes).toString();

      final first = await storage.imports.importFile(
        source: source,
        originalFilename: 'probe_source.bin',
        mediaType: 'application/octet-stream',
      );
      final storedBytes = await File(first.file.path).readAsBytes();
      _expect(
        'Imported file preserves original bytes',
        _sameBytes(storedBytes, sourceBytes),
        '${storedBytes.length} bytes',
      );
      _expect(
        'Imported file SHA-256 matches source',
        first.document.sha256 == expectedSha,
      );

      var duplicateRejected = false;
      try {
        await storage.imports.importFile(
          source: source,
          originalFilename: 'duplicate.bin',
          mediaType: 'application/octet-stream',
        );
      } on DuplicateDocumentException {
        duplicateRejected = true;
      }
      _expect('Duplicate content is rejected', duplicateRejected);
      _expect(
        'Duplicate leaves a single document',
        await storage.documents.countActive() == 1,
      );

      final secondBytes = List<int>.generate(256, (index) => 255 - index);
      final secondSource = File(p.join(support.path, 'probe_second.bin'));
      await secondSource.writeAsBytes(secondBytes, flush: true);
      final second = await storage.imports.importFile(
        source: secondSource,
        originalFilename: 'probe_second.bin',
        mediaType: 'application/octet-stream',
      );

      await storage.documents.updateExtraction(
        documentId: first.document.id,
        extractedText:
            'Quarterly insurance premium statement and policy QIP-4471.',
        status: ExtractionStatus.ready,
        pageCount: 2,
      );
      await storage.documents.updateExtraction(
        documentId: second.document.id,
        extractedText: 'Vehicle registration certificate for KA-01.',
        status: ExtractionStatus.ready,
      );

      final premium = await storage.search.search('premium');
      _expect(
        'FTS5 MATCH finds indexed extracted text',
        premium.length == 1 && premium.single.documentId == first.document.id,
      );
      final prefix = await storage.search.search('insur');
      _expect(
        'FTS5 prefix search works in release mode',
        prefix.length == 1 && prefix.single.documentId == first.document.id,
      );
      _expect(
        'FTS5 returns a highlighted snippet',
        (premium.single.snippet ?? '').toLowerCase().contains('[premium]'),
        premium.single.snippet ?? '',
      );

      await storage.documents.softDelete(second.document.id);
      _expect(
        'Soft delete removes the document from search',
        (await storage.search.search('registration')).isEmpty,
      );
      _expect(
        'Soft delete removes the FTS row',
        await storage.search.indexedDocumentCount() == 1,
      );

      await storage.documents.hardDelete(second.document.id);
      _expect(
        'Hard delete keeps the index consistent',
        await storage.search.indexedDocumentCount() == 1 &&
            await storage.documents.countActive() == 1,
      );

      var rolledBack = false;
      try {
        await storage.database.transaction(() async {
          await storage.documents.insert(
            LocalDocument(
              id: 'rollback-probe',
              originalFilename: 'rollback.bin',
              storedFilename: 'rollback-probe.bin',
              mediaType: 'application/octet-stream',
              sizeBytes: 1,
              sha256: 'd' * 64,
              extractedText: 'rollback marker text',
              createdAt: DateTime.utc(2026, 4, 1),
              updatedAt: DateTime.utc(2026, 4, 1),
            ),
          );
          await storage.database.customStatement('''
            INSERT INTO document_relationships (
              id, source_document_id, related_document_id, relationship_type,
              score, explanation, evidence_json, calculated_at
            ) VALUES (
              'rollback-rel', 'rollback-probe', 'missing', 'same-issuer',
              0.5, 'probe', '[]', '2026-04-01T00:00:00.000Z'
            )
          ''');
        });
      } on Exception {
        rolledBack = true;
      }
      _expect(
        'Failed transaction rolls back metadata and FTS rows',
        rolledBack &&
            await storage.documents.findById('rollback-probe') == null &&
            (await storage.search.search('rollback')).isEmpty,
      );

      final orphan = File(p.join(paths.documentsDirectory, 'orphan-probe.bin'));
      await orphan.writeAsBytes([9, 9, 9], flush: true);
      final reconciliation = await storage.imports.reconcile(
        now: DateTime.utc(2026, 4, 2),
      );
      _expect(
        'Reconciliation quarantines orphaned files without deleting them',
        reconciliation.movedOrphans.contains('orphan-probe.bin') &&
            await File(
              p.join(
                paths.orphanedRecoveryDirectory,
                'orphan_orphan-probe.bin',
              ),
            ).exists(),
      );

      await storage.close();
      storage = await LocalStorage.open(paths: paths);
      final reopened = await storage.documents.findById(first.document.id);
      _expect(
        'Database and files survive an app-process reopen',
        reopened != null &&
            await File(first.file.path).exists() &&
            (await storage.search.search('premium')).length == 1,
      );
      final finalDiagnostics = await storage.diagnostics();
      _expect(
        'Reopened diagnostics remain healthy',
        finalDiagnostics.fts5Usable &&
            finalDiagnostics.documentCount == 1 &&
            finalDiagnostics.indexedDocumentCount == 1,
      );
    } catch (error, stackTrace) {
      _expect('Probe completed without an unexpected exception', false, '$error');
      _checks.add(
        _Check(
          name: 'Stack trace',
          passed: false,
          detail: '$stackTrace',
        ),
      );
    } finally {
      try {
        await storage.close();
      } on Object {
        // The probe still reports what it observed.
      }
      _running = false;
      setState(() {});
      await _writeReport();
    }
  }

  Future<void> _writeReport() async {
    final passed = _checks.where((check) => check.passed).length;
    final buffer = StringBuffer()
      ..writeln('LORE Phase 3.1 local storage probe')
      ..writeln('release build, Android device')
      ..writeln('checks: $passed passed, ${_checks.length - passed} failed');
    for (final check in _checks) {
      buffer.writeln('${check.passed ? 'PASS' : 'FAIL'} ${check.name}');
      if (check.detail.isNotEmpty) {
        buffer.writeln('  ${check.detail}');
      }
    }
    final text = buffer.toString();
    debugPrint(text);
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final report = File(p.join(external.path, 'local_storage_probe.txt'));
        await report.writeAsString(text, flush: true);
        _reportPath = report.path;
        setState(() {});
      }
    } on Object catch (error) {
      _reportPath = 'report unavailable: $error';
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final passed = _checks.where((check) => check.passed).length;
    final failed = _checks.length - passed;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('LORE local storage probe')),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              _running
                  ? 'Running release-mode checks...'
                  : 'Checks: $passed passed, $failed failed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_reportPath.isNotEmpty)
              Text('Report: $_reportPath', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 8),
            for (final check in _checks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${check.passed ? 'PASS' : 'FAIL'}  ${check.name}'
                  '${check.detail.isEmpty ? '' : '\n    ${check.detail}'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: check.passed
                        ? const Color(0xFF1B5E20)
                        : const Color(0xFFB71C1C),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Check {
  const _Check({
    required this.name,
    required this.passed,
    this.detail = '',
  });

  final String name;
  final bool passed;
  final String detail;
}

var _id = 0;

String _nextId() => 'probe-doc-${++_id}';

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
