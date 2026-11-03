import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'local_database.g.dart';

@TableIndex(name: 'categories_sort_idx', columns: {#sortOrder})
class Categories extends Table {
  TextColumn get name => text()();

  IntColumn get sortOrder => integer().unique()();

  @override
  Set<Column> get primaryKey => {name};
}

@TableIndex(name: 'documents_category_idx', columns: {#category, #isDeleted})
@TableIndex(name: 'documents_created_idx', columns: {#createdAt})
@TableIndex(name: 'documents_deleted_idx', columns: {#isDeleted})
class Documents extends Table {
  TextColumn get id => text()();

  TextColumn get originalFilename => text()();

  TextColumn get storedFilename => text().unique()();

  TextColumn get mediaType => text()();

  IntColumn get sizeBytes => integer()();

  TextColumn get sha256 => text().unique()();

  TextColumn get extractedText => text().withDefault(const Constant(''))();

  TextColumn get extractionStatus =>
      text().withDefault(const Constant('pending'))();

  TextColumn get extractionError => text().nullable()();

  TextColumn get extractionMethod => text().nullable()();

  TextColumn get processingStatus =>
      text().withDefault(const Constant('pending')).check(
        const CustomExpression<bool>(
          "processing_status IN ('pending', 'processing', 'completed', "
          "'partially_completed', 'failed')",
        ),
      )();

  TextColumn get processingError => text().nullable()();

  TextColumn get processingStartedAt => text().nullable()();

  TextColumn get processingCompletedAt => text().nullable()();

  IntColumn get processingAttempts =>
      integer().withDefault(const Constant(0)).check(
        const CustomExpression<bool>('processing_attempts >= 0'),
      )();

  IntColumn get pageCount => integer().nullable()();

  TextColumn get sourceModifiedAt => text().nullable()();

  TextColumn get documentTitle => text().nullable()();

  TextColumn get category => text().nullable().references(
    Categories,
    #name,
    onDelete: KeyAction.setNull,
  )();

  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

  TextColumn get tagsText => text().withDefault(const Constant(''))();

  TextColumn get documentType => text().nullable()();

  TextColumn get issuer => text().nullable()();

  TextColumn get referenceNumber => text().nullable()();

  TextColumn get documentDate => text().nullable()();

  TextColumn get classificationReasonsJson =>
      text().withDefault(const Constant('[]'))();

  RealColumn get classificationConfidence =>
      real().nullable().check(
        const CustomExpression<bool>(
          'classification_confidence IS NULL OR '
          '(classification_confidence >= 0.0 AND classification_confidence <= 1.0)',
        ),
      )();

  TextColumn get classificationVersion => text().nullable()();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  TextColumn get createdAt => text()();

  TextColumn get updatedAt => text()();

  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (size_bytes >= 0)',
    'CHECK (length(sha256) = 64)',
    "CHECK (extraction_status IN ('pending', 'processing', 'ready', 'failed', 'unsupported'))",
    'CHECK (processing_attempts >= 0)',
    'CHECK (classification_confidence IS NULL OR '
        '(classification_confidence >= 0.0 AND classification_confidence <= 1.0))',
  ];
}

@TableIndex(name: 'relationships_source_idx', columns: {#sourceDocumentId})
@TableIndex(name: 'relationships_related_idx', columns: {#relatedDocumentId})
class DocumentRelationships extends Table {
  TextColumn get id => text()();

  TextColumn get sourceDocumentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();

  TextColumn get relatedDocumentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();

  TextColumn get relationshipType => text()();

  RealColumn get score => real()();

  TextColumn get explanation => text()();

  TextColumn get evidenceJson => text().withDefault(const Constant('[]'))();

  TextColumn get calculatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (score >= 0.0 AND score <= 1.0)',
    'CHECK (source_document_id < related_document_id)',
    'UNIQUE (source_document_id, related_document_id, relationship_type)',
  ];
}

class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class SchemaMeta extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Categories,
    Documents,
    DocumentRelationships,
    AppSettings,
    SchemaMeta,
  ],
)
class LoreDatabase extends _$LoreDatabase {
  LoreDatabase(super.e);

  factory LoreDatabase.openFile(File file) {
    return LoreDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: (database) {
          database.execute('PRAGMA journal_mode = WAL');
          database.execute('PRAGMA foreign_keys = ON');
          database.execute('PRAGMA synchronous = NORMAL');
        },
      ),
    );
  }

  factory LoreDatabase.inMemory() {
    return LoreDatabase(
      NativeDatabase.memory(
        setup: (database) {
          database.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createSearchInfrastructure();
      await _seedCategories();
      await _seedMetadata();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(documents, documents.extractionMethod);
        await migrator.addColumn(documents, documents.processingStatus);
        await migrator.addColumn(documents, documents.processingError);
        await migrator.addColumn(documents, documents.processingStartedAt);
        await migrator.addColumn(documents, documents.processingCompletedAt);
        await migrator.addColumn(documents, documents.processingAttempts);
        await migrator.addColumn(documents, documents.sourceModifiedAt);
        await migrator.addColumn(documents, documents.classificationConfidence);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _syncMetadataVersion();
    },
  );

  Future<void> _createSearchInfrastructure() async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS document_search USING fts5(
        document_id UNINDEXED,
        extracted_text,
        original_filename,
        document_title,
        category,
        tags_text,
        document_type,
        issuer,
        reference_number,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS documents_search_ai
      AFTER INSERT ON documents
      WHEN new.is_deleted = 0
      BEGIN
        INSERT INTO document_search (
          rowid, document_id, extracted_text, original_filename,
          document_title, category, tags_text, document_type,
          issuer, reference_number
        ) VALUES (
          new.rowid, new.id, new.extracted_text, new.original_filename,
          new.document_title, new.category, new.tags_text, new.document_type,
          new.issuer, new.reference_number
        );
      END
    ''');

    // A single AFTER UPDATE trigger keeps the delete and re-insert ordered.
    // Separate triggers on the same event have no guaranteed firing order,
    // which can insert before the stale row is removed.
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS documents_search_au
      AFTER UPDATE ON documents
      BEGIN
        DELETE FROM document_search WHERE rowid = old.rowid;
        INSERT INTO document_search (
          rowid, document_id, extracted_text, original_filename,
          document_title, category, tags_text, document_type,
          issuer, reference_number
        )
        SELECT
          new.rowid, new.id, new.extracted_text, new.original_filename,
          new.document_title, new.category, new.tags_text, new.document_type,
          new.issuer, new.reference_number
        WHERE new.is_deleted = 0;
      END
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS documents_search_ad
      AFTER DELETE ON documents
      BEGIN
        DELETE FROM document_search WHERE rowid = old.rowid;
      END
    ''');
  }

  Future<void> _seedCategories() async {
    const names = <String>[
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
    ];

    await batch((batch) {
      for (var index = 0; index < names.length; index++) {
        batch.insert(
          categories,
          CategoriesCompanion.insert(name: names[index], sortOrder: index),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> _seedMetadata() async {
    await batch((batch) {
      batch.insert(
        schemaMeta,
        SchemaMetaCompanion.insert(
          key: 'local_schema_version',
          value: '$schemaVersion',
        ),
        mode: InsertMode.insertOrReplace,
      );
      batch.insert(
        schemaMeta,
        SchemaMetaCompanion.insert(
          key: 'classifier_version',
          value: 'rules-v1',
        ),
        mode: InsertMode.insertOrReplace,
      );
      batch.insert(
        schemaMeta,
        SchemaMetaCompanion.insert(
          key: 'fts_tokenizer',
          value: 'unicode61 remove_diacritics 2',
        ),
        mode: InsertMode.insertOrReplace,
      );
      batch.insert(
        schemaMeta,
        SchemaMetaCompanion.insert(key: 'fts_schema_version', value: '1'),
        mode: InsertMode.insertOrReplace,
      );
      batch.insert(
        appSettings,
        AppSettingsCompanion.insert(key: 'local_storage_phase', value: '3.2'),
        mode: InsertMode.insertOrReplace,
      );
      batch.insert(
        appSettings,
        AppSettingsCompanion.insert(
          key: 'processing_pipeline_version',
          value: '1',
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _syncMetadataVersion() async {
    await customStatement(
      "INSERT OR REPLACE INTO schema_meta (key, value) "
      "VALUES ('local_schema_version', ?)",
      ['$schemaVersion'],
    );
    await customStatement(
      "INSERT OR REPLACE INTO schema_meta (key, value) "
      "VALUES ('classifier_version', 'rules-v1')",
    );
    await customStatement(
      "INSERT OR REPLACE INTO app_settings (key, value) "
      "VALUES ('local_storage_phase', '3.2')",
    );
    await customStatement(
      "INSERT OR REPLACE INTO app_settings (key, value) "
      "VALUES ('processing_pipeline_version', '1')",
    );
  }
}
