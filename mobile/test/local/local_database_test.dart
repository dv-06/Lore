import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/local/document_repository.dart';
import 'package:lore_mobile/data/local/local_database.dart';
import 'package:lore_mobile/data/local/local_models.dart';
import 'package:lore_mobile/data/local/local_search_repository.dart';
import 'package:lore_mobile/data/local/relationship_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const _shaA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// The Phase 3.1 schema, reproduced so the upgrade path is exercised against
/// a real version-1 file rather than a freshly created version-2 database.
const _schemaVersion1Ddl = <String>[
  'CREATE TABLE categories ('
      'name TEXT NOT NULL, '
      'sort_order INTEGER NOT NULL UNIQUE, '
      'PRIMARY KEY (name))',
  'CREATE TABLE documents ('
      'id TEXT NOT NULL, '
      'original_filename TEXT NOT NULL, '
      'stored_filename TEXT NOT NULL UNIQUE, '
      'media_type TEXT NOT NULL, '
      'size_bytes INTEGER NOT NULL, '
      'sha256 TEXT NOT NULL UNIQUE, '
      "extracted_text TEXT NOT NULL DEFAULT '', "
      "extraction_status TEXT NOT NULL DEFAULT 'pending', "
      'extraction_error TEXT NULL, '
      'page_count INTEGER NULL, '
      'document_title TEXT NULL, '
      'category TEXT NULL REFERENCES categories (name) ON DELETE SET NULL, '
      "tags_json TEXT NOT NULL DEFAULT '[]', "
      "tags_text TEXT NOT NULL DEFAULT '', "
      'document_type TEXT NULL, '
      'issuer TEXT NULL, '
      'reference_number TEXT NULL, '
      'document_date TEXT NULL, '
      "classification_reasons_json TEXT NOT NULL DEFAULT '[]', "
      'classification_version TEXT NULL, '
      'is_deleted INTEGER NOT NULL DEFAULT 0, '
      'created_at TEXT NOT NULL, '
      'updated_at TEXT NOT NULL, '
      'deleted_at TEXT NULL, '
      'PRIMARY KEY (id), '
      'CHECK (size_bytes >= 0), '
      'CHECK (length(sha256) = 64), '
      'CHECK (extraction_status IN '
      "('pending', 'processing', 'ready', 'failed', 'unsupported')))",
  'CREATE TABLE document_relationships ('
      'id TEXT NOT NULL, '
      'source_document_id TEXT NOT NULL REFERENCES documents (id) '
      'ON DELETE CASCADE, '
      'related_document_id TEXT NOT NULL REFERENCES documents (id) '
      'ON DELETE CASCADE, '
      'relationship_type TEXT NOT NULL, '
      'score REAL NOT NULL, '
      'explanation TEXT NOT NULL, '
      "evidence_json TEXT NOT NULL DEFAULT '[]', "
      'calculated_at TEXT NOT NULL, '
      'PRIMARY KEY (id), '
      'CHECK (score >= 0.0 AND score <= 1.0), '
      'CHECK (source_document_id < related_document_id), '
      'UNIQUE (source_document_id, related_document_id, relationship_type))',
  'CREATE TABLE app_settings ('
      'key TEXT NOT NULL, '
      'value TEXT NOT NULL, '
      'PRIMARY KEY (key))',
  'CREATE TABLE schema_meta ('
      'key TEXT NOT NULL, '
      'value TEXT NOT NULL, '
      'PRIMARY KEY (key))',
  'CREATE INDEX categories_sort_idx ON categories (sort_order)',
  'CREATE INDEX documents_category_idx ON documents (category, is_deleted)',
  'CREATE INDEX documents_created_idx ON documents (created_at)',
  'CREATE INDEX documents_deleted_idx ON documents (is_deleted)',
  'CREATE INDEX relationships_source_idx '
      'ON document_relationships (source_document_id)',
  'CREATE INDEX relationships_related_idx '
      'ON document_relationships (related_document_id)',
  'CREATE VIRTUAL TABLE document_search USING fts5('
      'document_id UNINDEXED, extracted_text, original_filename, '
      'document_title, category, tags_text, document_type, issuer, '
      'reference_number, tokenize = \'unicode61 remove_diacritics 2\')',
  'CREATE TRIGGER documents_search_ai AFTER INSERT ON documents '
      'WHEN new.is_deleted = 0 BEGIN '
      'INSERT INTO document_search (rowid, document_id, extracted_text, '
      'original_filename, document_title, category, tags_text, document_type, '
      'issuer, reference_number) VALUES (new.rowid, new.id, '
      'new.extracted_text, new.original_filename, new.document_title, '
      'new.category, new.tags_text, new.document_type, new.issuer, '
      'new.reference_number); END',
  'CREATE TRIGGER documents_search_au AFTER UPDATE ON documents BEGIN '
      'DELETE FROM document_search WHERE rowid = old.rowid; '
      'INSERT INTO document_search (rowid, document_id, extracted_text, '
      'original_filename, document_title, category, tags_text, document_type, '
      'issuer, reference_number) SELECT new.rowid, new.id, '
      'new.extracted_text, new.original_filename, new.document_title, '
      'new.category, new.tags_text, new.document_type, new.issuer, '
      'new.reference_number WHERE new.is_deleted = 0; END',
  'CREATE TRIGGER documents_search_ad AFTER DELETE ON documents BEGIN '
      'DELETE FROM document_search WHERE rowid = old.rowid; END',
  "INSERT INTO schema_meta (key, value) VALUES "
      "('local_schema_version', '1'), "
      "('fts_tokenizer', 'unicode61 remove_diacritics 2'), "
      "('fts_schema_version', '1')",
  "INSERT INTO app_settings (key, value) VALUES "
      "('local_storage_phase', '3.1')",
  "INSERT INTO categories (name, sort_order) VALUES "
      "('Finance', 0), ('Education', 1), ('Health', 2), ('Identity', 3), "
      "('Home', 4), ('Appliances', 5), ('Insurance', 6), ('Travel', 7), "
      "('Work', 8), ('Legal', 9), ('Uncategorized', 10)",
];

LocalDocument _document({
  required String id,
  required String sha256,
  String filename = 'fixture.pdf',
  String mediaType = 'application/pdf',
  String extractedText = '',
  String? title,
  String? category,
  bool isDeleted = false,
  DateTime? createdAt,
}) {
  final timestamp = (createdAt ?? DateTime.utc(2026, 1, 1)).toUtc();
  return LocalDocument(
    id: id,
    originalFilename: filename,
    storedFilename: '$id.pdf',
    mediaType: mediaType,
    sizeBytes: 10,
    sha256: sha256,
    extractedText: extractedText,
    documentTitle: title,
    category: category,
    isDeleted: isDeleted,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Future<LoreDatabase> _openDatabase() async {
  final database = LoreDatabase.inMemory();
  await database.customSelect('SELECT 1').getSingle();
  return database;
}

Future<int> _ftsRowCount(LoreDatabase database) async {
  final row = await database
      .customSelect('SELECT count(*) AS c FROM document_search')
      .getSingle();
  return row.read<int>('c');
}

void main() {
  late LoreDatabase database;
  late DriftDocumentRepository documents;
  late DriftLocalSearchRepository search;
  late DriftRelationshipRepository relationships;

  setUp(() async {
    database = await _openDatabase();
    documents = DriftDocumentRepository(database);
    search = DriftLocalSearchRepository(database);
    relationships = DriftRelationshipRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('initialization', () {
    test('creates schema version 2 and seeds categories/metadata', () async {
      expect(database.schemaVersion, 2);

      final categories = await (database.select(
        database.categories,
      )..orderBy([(table) => OrderingTerm.asc(table.sortOrder)])).get();
      expect(categories.map((row) => row.name), [
        'Finance',
        'Education',
        'Health',
        'Identity',
        'Home',
        'Appliances',
        'Insurance',
        'Travel',
        'Work',
        'Legal',
        'Uncategorized',
      ]);

      final meta = await database.select(database.schemaMeta).get();
      final byKey = {for (final row in meta) row.key: row.value};
      expect(byKey['local_schema_version'], '2');
      expect(byKey['fts_tokenizer'], 'unicode61 remove_diacritics 2');
      expect(byKey['fts_schema_version'], '1');

      final settings = await database.select(database.appSettings).get();
      final settingsByKey = {for (final row in settings) row.key: row.value};
      expect(settingsByKey['local_storage_phase'], '3.2');
      expect(settingsByKey['processing_pipeline_version'], '1');
    });

    test('FTS5 is compiled and the search table and triggers exist', () async {
      final compiled = await database
          .customSelect(
            "SELECT sqlite_compileoption_used('ENABLE_FTS5') AS enabled",
          )
          .getSingle();
      expect(compiled.read<int>('enabled'), isNot(0));

      final objects = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE name IN ('document_search', 'documents_search_ai', "
            "'documents_search_au', 'documents_search_ad')",
          )
          .get();
      expect(objects.map((row) => row.read<String>('name')).toSet(), {
        'document_search',
        'documents_search_ai',
        'documents_search_au',
        'documents_search_ad',
      });
    });
  });

  group('schema persistence', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lore_db_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'reopening a database preserves data and metadata',
      () async {
        final file = File('${tempDir.path}/lore.sqlite');
        var first = LoreDatabase.openFile(file);
        await first.customSelect('SELECT 1').getSingle();
        await DriftDocumentRepository(
          first,
        ).insert(_document(id: 'doc-1', sha256: _shaA));
        final beforeMeta =
            await (first.select(first.schemaMeta)
                  ..where((table) => table.key.equals('local_schema_version')))
                .getSingle();
        await first.close();

        final second = LoreDatabase.openFile(file);
        await second.customSelect('SELECT 1').getSingle();
        final afterMeta =
            await (second.select(second.schemaMeta)
                  ..where((table) => table.key.equals('local_schema_version')))
                .getSingle();
        final count = await DriftDocumentRepository(second).countActive();
        final categories = await second.select(second.categories).get();
        await second.close();

        expect(first.schemaVersion, second.schemaVersion);
        expect(beforeMeta.value, '2');
        expect(afterMeta.value, '2');
        expect(count, 1);
        expect(categories, hasLength(11));
      },
    );

    test('upgrading a version 1 database adds processing columns', () async {
      final file = File('${tempDir.path}/lore.sqlite');
      final raw = sqlite.sqlite3.open(file.path);
      try {
        for (final statement in _schemaVersion1Ddl) {
          raw.execute(statement);
        }
        raw.execute('PRAGMA user_version = 1');
        raw.execute(
          "INSERT INTO documents ("
          'id, original_filename, stored_filename, media_type, size_bytes, '
          'sha256, extracted_text, extraction_status, created_at, updated_at'
          ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'doc-1',
            'invoice.pdf',
            'doc-1.pdf',
            'application/pdf',
            10,
            _shaA,
            'Existing searchable text',
            'ready',
            '2026-01-01T00:00:00.000Z',
            '2026-01-01T00:00:00.000Z',
          ],
        );
      } finally {
        raw.close();
      }

      final database = LoreDatabase.openFile(file);
      addTearDown(database.close);
      final document = await DriftDocumentRepository(database).findById('doc-1');
      final columns = await database
          .customSelect('PRAGMA table_info(documents)')
          .get();
      final columnNames = columns.map((row) => row.read<String>('name'));
      final search = DriftLocalSearchRepository(database);
      final settings = await database.select(database.appSettings).get();

      expect(database.schemaVersion, 2);
      expect(columnNames, containsAll(<String>[
        'extraction_method',
        'processing_status',
        'processing_error',
        'processing_started_at',
        'processing_completed_at',
        'processing_attempts',
        'source_modified_at',
        'classification_confidence',
      ]));
      expect(document, isNotNull);
      expect(document!.extractedText, 'Existing searchable text');
      expect(document.extractionStatus, ExtractionStatus.ready);
      expect(document.processingStatus, ProcessingStatus.pending);
      expect(document.processingAttempts, 0);
      expect(document.extractionMethod, isNull);
      expect(document.classificationConfidence, isNull);
      expect((await search.search('searchable')).single.documentId, 'doc-1');
      expect(
        {for (final row in settings) row.key: row.value}['local_storage_phase'],
        '3.2',
      );
      expect(
        {for (final row in settings) row.key: row.value}['processing_pipeline_version'],
        '1',
      );
    });
  });

  group('document metadata CRUD', () {
    test('inserts, finds, lists, updates and deletes a document', () async {
      final createdAt = DateTime.utc(2026, 1, 1, 12);
      final document = _document(
        id: 'doc-1',
        sha256: _shaA,
        filename: 'invoice.pdf',
        extractedText: 'Electricity invoice for January.',
        category: 'Finance',
        createdAt: createdAt,
      );

      await documents.insert(document);

      final byId = await documents.findById('doc-1');
      expect(byId, isNotNull);
      expect(byId!.originalFilename, 'invoice.pdf');
      expect(byId.category, 'Finance');
      expect(byId.createdAt, createdAt);
      expect(byId.extractionStatus, ExtractionStatus.pending);

      final byHash = await documents.findBySha256(_shaA);
      expect(byHash?.id, 'doc-1');
      expect(await documents.findBySha256(_shaB), isNull);

      final active = await documents.listActive();
      expect(active.map((item) => item.id), ['doc-1']);
      expect(await documents.countActive(), 1);

      final updatedAt = DateTime.utc(2026, 1, 2);
      await documents.updateExtraction(
        documentId: 'doc-1',
        extractedText: 'Updated electricity invoice text.',
        status: ExtractionStatus.ready,
        pageCount: 2,
        updatedAt: updatedAt,
      );
      final updated = await documents.findById('doc-1');
      expect(updated!.extractionStatus, ExtractionStatus.ready);
      expect(updated.extractedText, contains('Updated'));
      expect(updated.pageCount, 2);
      expect(updated.updatedAt, updatedAt);
      expect(updated.extractionError, isNull);

      await documents.softDelete('doc-1', deletedAt: DateTime.utc(2026, 1, 3));
      final softDeleted = await documents.findById('doc-1');
      expect(softDeleted!.isDeleted, isTrue);
      expect(softDeleted.deletedAt, DateTime.utc(2026, 1, 3));
      expect(await documents.countActive(), 0);
      expect(await documents.listActive(), isEmpty);
      expect(await documents.listStoredFilenames(), {'doc-1.pdf'});

      await documents.hardDelete('doc-1');
      expect(await documents.findById('doc-1'), isNull);
    });

    test('updating a missing document fails', () async {
      await expectLater(
        documents.updateExtraction(
          documentId: 'missing',
          extractedText: 'x',
          status: ExtractionStatus.ready,
        ),
        throwsA(isA<LocalStorageException>()),
      );
      await expectLater(
        documents.softDelete('missing'),
        throwsA(isA<LocalStorageException>()),
      );
    });

    test('rejects duplicate identifiers, stored names and hashes', () async {
      await documents.insert(_document(id: 'doc-1', sha256: _shaA));

      await expectLater(
        documents.insert(_document(id: 'doc-1', sha256: _shaB)),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        documents.insert(_document(id: 'doc-2', sha256: _shaA)),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('foreign-key integrity', () {
    test('rejects unknown categories and relationship endpoints', () async {
      await expectLater(
        database
            .into(database.documents)
            .insert(
              DocumentsCompanion.insert(
                id: 'doc-1',
                originalFilename: 'a.pdf',
                storedFilename: 'doc-1.pdf',
                mediaType: 'application/pdf',
                sizeBytes: 1,
                sha256: _shaA,
                category: const Value('NotACategory'),
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            ),
        throwsA(isA<Exception>()),
      );

      await documents.insert(_document(id: 'doc-1', sha256: _shaA));
      await documents.insert(_document(id: 'doc-2', sha256: _shaB));

      await expectLater(
        relationships.upsert(
          LocalRelationship(
            id: 'rel-1',
            sourceDocumentId: 'doc-1',
            relatedDocumentId: 'missing',
            relationshipType: 'same-issuer',
            score: 0.5,
            explanation: 'test',
            calculatedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
        throwsA(isA<Exception>()),
      );

      await expectLater(
        relationships.upsert(
          LocalRelationship(
            id: 'rel-1',
            sourceDocumentId: 'doc-2',
            relatedDocumentId: 'doc-1',
            relationshipType: 'same-issuer',
            score: 0.5,
            explanation: 'test',
            calculatedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('deleting a category nulls the document category', () async {
      await database
          .into(database.categories)
          .insert(CategoriesCompanion.insert(name: 'Temporary', sortOrder: 99));
      await documents.insert(
        _document(id: 'doc-1', sha256: _shaA, category: 'Temporary'),
      );

      await (database.delete(
        database.categories,
      )..where((table) => table.name.equals('Temporary'))).go();

      expect((await documents.findById('doc-1'))!.category, isNull);
    });

    test('deleting a document cascades relationships', () async {
      await documents.insert(_document(id: 'doc-1', sha256: _shaA));
      await documents.insert(_document(id: 'doc-2', sha256: _shaB));
      await relationships.upsert(
        LocalRelationship(
          id: 'rel-1',
          sourceDocumentId: 'doc-1',
          relatedDocumentId: 'doc-2',
          relationshipType: 'same-issuer',
          score: 0.75,
          explanation: 'shared issuer',
          calculatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(await relationships.count(), 1);

      await documents.hardDelete('doc-1');
      expect(await relationships.count(), 0);
    });
  });

  group('relationship repository', () {
    test('upserts and lists relationships for either endpoint', () async {
      await documents.insert(_document(id: 'doc-1', sha256: _shaA));
      await documents.insert(_document(id: 'doc-2', sha256: _shaB));

      final relationship = LocalRelationship(
        id: 'rel-1',
        sourceDocumentId: 'doc-1',
        relatedDocumentId: 'doc-2',
        relationshipType: 'same-issuer',
        score: 0.4,
        explanation: 'shared issuer',
        calculatedAt: DateTime.utc(2026, 1, 1),
      );
      await relationships.upsert(relationship);
      await relationships.upsert(
        LocalRelationship(
          id: 'rel-1',
          sourceDocumentId: 'doc-1',
          relatedDocumentId: 'doc-2',
          relationshipType: 'same-issuer',
          score: 0.9,
          explanation: 'shared issuer and reference',
          calculatedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      final fromSource = await relationships.listForDocument('doc-1');
      final fromRelated = await relationships.listForDocument('doc-2');
      expect(fromSource, hasLength(1));
      expect(fromSource.single.score, closeTo(0.9, 1e-9));
      expect(fromRelated, hasLength(1));
      expect(fromRelated.single.explanation, contains('reference'));
    });
  });

  group('FTS5 synchronization', () {
    test('insert, update, soft delete and hard delete stay in sync', () async {
      await documents.insert(
        _document(
          id: 'doc-1',
          sha256: _shaA,
          filename: 'electricity-invoice.pdf',
          extractedText: 'Electricity meter reading 98765.',
          title: 'January electricity',
          category: 'Finance',
        ),
      );
      await documents.insert(
        _document(
          id: 'doc-2',
          sha256: _shaB,
          filename: 'passport.pdf',
          extractedText: 'Republic passport identity document.',
          category: 'Identity',
        ),
      );

      expect(await _ftsRowCount(database), 2);
      expect(await search.indexedDocumentCount(), 2);

      final results = await search.search('electricity');
      expect(results, hasLength(1));
      expect(results.single.documentId, 'doc-1');
      expect(
        results.single.snippet,
        matches(RegExp(r'\[electricity\]', caseSensitive: false)),
      );

      final prefix = await search.search('invoi');
      expect(prefix.map((row) => row.documentId), ['doc-1']);

      final titleOnly = await search.search('January');
      expect(titleOnly.map((row) => row.documentId), ['doc-1']);

      await documents.updateExtraction(
        documentId: 'doc-1',
        extractedText: 'Water bill for February 2026.',
        status: ExtractionStatus.ready,
      );
      expect(await _ftsRowCount(database), 2);
      expect(await search.search('meter'), isEmpty);
      expect(await search.search('98765'), isEmpty);
      expect((await search.search('water')).map((row) => row.documentId), [
        'doc-1',
      ]);

      await documents.softDelete('doc-1');
      expect(await _ftsRowCount(database), 1);
      expect(await search.search('water'), isEmpty);
      expect(await search.indexedDocumentCount(), 1);

      await documents.hardDelete('doc-2');
      expect(await _ftsRowCount(database), 0);
      expect(await search.indexedDocumentCount(), 0);
    });

    test('documents inserted as deleted are not indexed', () async {
      await documents.insert(
        _document(
          id: 'doc-1',
          sha256: _shaA,
          extractedText: 'hidden text',
          isDeleted: true,
        ),
      );
      expect(await _ftsRowCount(database), 0);
      expect(await search.search('hidden'), isEmpty);
    });

    test('rebuildIndex restores only active documents', () async {
      await documents.insert(
        _document(id: 'doc-1', sha256: _shaA, extractedText: 'alpha'),
      );
      await documents.insert(
        _document(id: 'doc-2', sha256: _shaB, extractedText: 'beta'),
      );
      await documents.softDelete('doc-2');
      await database.customStatement('DELETE FROM document_search');
      expect(await _ftsRowCount(database), 0);

      final rebuilt = await search.rebuildIndex();
      expect(rebuilt, 1);
      expect(await _ftsRowCount(database), 1);
      expect((await search.search('alpha')).single.documentId, 'doc-1');
      expect(await search.search('beta'), isEmpty);
    });

    test('queries are validated and sanitized', () async {
      expect(await search.search(''), isEmpty);
      expect(await search.search('   '), isEmpty);
      expect(await search.search('!!! ...'), isEmpty);
      expect(() => search.search('word ' * 13), throwsA(isA<ArgumentError>()));
      expect(() => search.search('a' * 257), throwsA(isA<ArgumentError>()));
      expect(() => search.search('ok', limit: 0), throwsArgumentError);
      expect(() => search.search('ok', limit: 101), throwsArgumentError);
    });

    test(
      'search excludes soft-deleted rows even if the index is stale',
      () async {
        await documents.insert(
          _document(id: 'doc-1', sha256: _shaA, extractedText: 'stale term'),
        );
        await documents.softDelete('doc-1');
        // Reinsert a stale index row directly to prove the join guard holds.
        await database.customStatement('''
        INSERT INTO document_search (
          rowid, document_id, extracted_text, original_filename
        )
        SELECT rowid, id, extracted_text, original_filename
        FROM documents WHERE id = 'doc-1'
      ''');

        expect(await search.search('stale'), isEmpty);
      },
    );
  });

  group('transaction rollback', () {
    test('rolls back document and FTS rows when a transaction fails', () async {
      await expectLater(
        database.transaction(() async {
          await documents.insert(_document(id: 'doc-1', sha256: _shaA));
          await database.customStatement('''
            INSERT INTO document_relationships (
              id, source_document_id, related_document_id, relationship_type,
              score, explanation, evidence_json, calculated_at
            ) VALUES (
              'rel-1', 'doc-1', 'missing', 'same-issuer',
              0.5, 'test', '[]', '2026-01-01T00:00:00.000Z'
            )
          ''');
        }),
        throwsA(isA<Exception>()),
      );

      expect(await documents.findById('doc-1'), isNull);
      expect(await _ftsRowCount(database), 0);
      expect(await relationships.count(), 0);
    });
  });
}
