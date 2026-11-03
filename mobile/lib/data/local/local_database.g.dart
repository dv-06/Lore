// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [name, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final String name;
  final int sortOrder;
  const Category({required this.name, required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(name: Value(name), sortOrder: Value(sortOrder));
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Category copyWith({String? name, int? sortOrder}) =>
      Category(name: name ?? this.name, sortOrder: sortOrder ?? this.sortOrder);
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String name,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       sortOrder = Value(sortOrder);
  static Insertable<Category> custom({
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? name,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DocumentsTable extends Documents
    with TableInfo<$DocumentsTable, Document> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalFilenameMeta = const VerificationMeta(
    'originalFilename',
  );
  @override
  late final GeneratedColumn<String> originalFilename = GeneratedColumn<String>(
    'original_filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storedFilenameMeta = const VerificationMeta(
    'storedFilename',
  );
  @override
  late final GeneratedColumn<String> storedFilename = GeneratedColumn<String>(
    'stored_filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _extractedTextMeta = const VerificationMeta(
    'extractedText',
  );
  @override
  late final GeneratedColumn<String> extractedText = GeneratedColumn<String>(
    'extracted_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _extractionStatusMeta = const VerificationMeta(
    'extractionStatus',
  );
  @override
  late final GeneratedColumn<String> extractionStatus = GeneratedColumn<String>(
    'extraction_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _extractionErrorMeta = const VerificationMeta(
    'extractionError',
  );
  @override
  late final GeneratedColumn<String> extractionError = GeneratedColumn<String>(
    'extraction_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extractionMethodMeta = const VerificationMeta(
    'extractionMethod',
  );
  @override
  late final GeneratedColumn<String> extractionMethod = GeneratedColumn<String>(
    'extraction_method',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processingStatusMeta = const VerificationMeta(
    'processingStatus',
  );
  @override
  late final GeneratedColumn<String> processingStatus = GeneratedColumn<String>(
    'processing_status',
    aliasedName,
    false,
    check: () => const CustomExpression<bool>(
      "processing_status IN ('pending', 'processing', 'completed', "
      "'partially_completed', 'failed')",
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _processingErrorMeta = const VerificationMeta(
    'processingError',
  );
  @override
  late final GeneratedColumn<String> processingError = GeneratedColumn<String>(
    'processing_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processingStartedAtMeta =
      const VerificationMeta('processingStartedAt');
  @override
  late final GeneratedColumn<String> processingStartedAt =
      GeneratedColumn<String>(
        'processing_started_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _processingCompletedAtMeta =
      const VerificationMeta('processingCompletedAt');
  @override
  late final GeneratedColumn<String> processingCompletedAt =
      GeneratedColumn<String>(
        'processing_completed_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _processingAttemptsMeta =
      const VerificationMeta('processingAttempts');
  @override
  late final GeneratedColumn<int> processingAttempts = GeneratedColumn<int>(
    'processing_attempts',
    aliasedName,
    false,
    check: () => const CustomExpression<bool>('processing_attempts >= 0'),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceModifiedAtMeta = const VerificationMeta(
    'sourceModifiedAt',
  );
  @override
  late final GeneratedColumn<String> sourceModifiedAt = GeneratedColumn<String>(
    'source_modified_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _documentTitleMeta = const VerificationMeta(
    'documentTitle',
  );
  @override
  late final GeneratedColumn<String> documentTitle = GeneratedColumn<String>(
    'document_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (name) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _tagsTextMeta = const VerificationMeta(
    'tagsText',
  );
  @override
  late final GeneratedColumn<String> tagsText = GeneratedColumn<String>(
    'tags_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _documentTypeMeta = const VerificationMeta(
    'documentType',
  );
  @override
  late final GeneratedColumn<String> documentType = GeneratedColumn<String>(
    'document_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _issuerMeta = const VerificationMeta('issuer');
  @override
  late final GeneratedColumn<String> issuer = GeneratedColumn<String>(
    'issuer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceNumberMeta = const VerificationMeta(
    'referenceNumber',
  );
  @override
  late final GeneratedColumn<String> referenceNumber = GeneratedColumn<String>(
    'reference_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _documentDateMeta = const VerificationMeta(
    'documentDate',
  );
  @override
  late final GeneratedColumn<String> documentDate = GeneratedColumn<String>(
    'document_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _classificationReasonsJsonMeta =
      const VerificationMeta('classificationReasonsJson');
  @override
  late final GeneratedColumn<String> classificationReasonsJson =
      GeneratedColumn<String>(
        'classification_reasons_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _classificationConfidenceMeta =
      const VerificationMeta('classificationConfidence');
  @override
  late final GeneratedColumn<double>
  classificationConfidence = GeneratedColumn<double>(
    'classification_confidence',
    aliasedName,
    true,
    check: () => const CustomExpression<bool>(
      'classification_confidence IS NULL OR '
      '(classification_confidence >= 0.0 AND classification_confidence <= 1.0)',
    ),
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _classificationVersionMeta =
      const VerificationMeta('classificationVersion');
  @override
  late final GeneratedColumn<String> classificationVersion =
      GeneratedColumn<String>(
        'classification_version',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    originalFilename,
    storedFilename,
    mediaType,
    sizeBytes,
    sha256,
    extractedText,
    extractionStatus,
    extractionError,
    extractionMethod,
    processingStatus,
    processingError,
    processingStartedAt,
    processingCompletedAt,
    processingAttempts,
    pageCount,
    sourceModifiedAt,
    documentTitle,
    category,
    tagsJson,
    tagsText,
    documentType,
    issuer,
    referenceNumber,
    documentDate,
    classificationReasonsJson,
    classificationConfidence,
    classificationVersion,
    isDeleted,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<Document> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('original_filename')) {
      context.handle(
        _originalFilenameMeta,
        originalFilename.isAcceptableOrUnknown(
          data['original_filename']!,
          _originalFilenameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalFilenameMeta);
    }
    if (data.containsKey('stored_filename')) {
      context.handle(
        _storedFilenameMeta,
        storedFilename.isAcceptableOrUnknown(
          data['stored_filename']!,
          _storedFilenameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_storedFilenameMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('extracted_text')) {
      context.handle(
        _extractedTextMeta,
        extractedText.isAcceptableOrUnknown(
          data['extracted_text']!,
          _extractedTextMeta,
        ),
      );
    }
    if (data.containsKey('extraction_status')) {
      context.handle(
        _extractionStatusMeta,
        extractionStatus.isAcceptableOrUnknown(
          data['extraction_status']!,
          _extractionStatusMeta,
        ),
      );
    }
    if (data.containsKey('extraction_error')) {
      context.handle(
        _extractionErrorMeta,
        extractionError.isAcceptableOrUnknown(
          data['extraction_error']!,
          _extractionErrorMeta,
        ),
      );
    }
    if (data.containsKey('extraction_method')) {
      context.handle(
        _extractionMethodMeta,
        extractionMethod.isAcceptableOrUnknown(
          data['extraction_method']!,
          _extractionMethodMeta,
        ),
      );
    }
    if (data.containsKey('processing_status')) {
      context.handle(
        _processingStatusMeta,
        processingStatus.isAcceptableOrUnknown(
          data['processing_status']!,
          _processingStatusMeta,
        ),
      );
    }
    if (data.containsKey('processing_error')) {
      context.handle(
        _processingErrorMeta,
        processingError.isAcceptableOrUnknown(
          data['processing_error']!,
          _processingErrorMeta,
        ),
      );
    }
    if (data.containsKey('processing_started_at')) {
      context.handle(
        _processingStartedAtMeta,
        processingStartedAt.isAcceptableOrUnknown(
          data['processing_started_at']!,
          _processingStartedAtMeta,
        ),
      );
    }
    if (data.containsKey('processing_completed_at')) {
      context.handle(
        _processingCompletedAtMeta,
        processingCompletedAt.isAcceptableOrUnknown(
          data['processing_completed_at']!,
          _processingCompletedAtMeta,
        ),
      );
    }
    if (data.containsKey('processing_attempts')) {
      context.handle(
        _processingAttemptsMeta,
        processingAttempts.isAcceptableOrUnknown(
          data['processing_attempts']!,
          _processingAttemptsMeta,
        ),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('source_modified_at')) {
      context.handle(
        _sourceModifiedAtMeta,
        sourceModifiedAt.isAcceptableOrUnknown(
          data['source_modified_at']!,
          _sourceModifiedAtMeta,
        ),
      );
    }
    if (data.containsKey('document_title')) {
      context.handle(
        _documentTitleMeta,
        documentTitle.isAcceptableOrUnknown(
          data['document_title']!,
          _documentTitleMeta,
        ),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('tags_text')) {
      context.handle(
        _tagsTextMeta,
        tagsText.isAcceptableOrUnknown(data['tags_text']!, _tagsTextMeta),
      );
    }
    if (data.containsKey('document_type')) {
      context.handle(
        _documentTypeMeta,
        documentType.isAcceptableOrUnknown(
          data['document_type']!,
          _documentTypeMeta,
        ),
      );
    }
    if (data.containsKey('issuer')) {
      context.handle(
        _issuerMeta,
        issuer.isAcceptableOrUnknown(data['issuer']!, _issuerMeta),
      );
    }
    if (data.containsKey('reference_number')) {
      context.handle(
        _referenceNumberMeta,
        referenceNumber.isAcceptableOrUnknown(
          data['reference_number']!,
          _referenceNumberMeta,
        ),
      );
    }
    if (data.containsKey('document_date')) {
      context.handle(
        _documentDateMeta,
        documentDate.isAcceptableOrUnknown(
          data['document_date']!,
          _documentDateMeta,
        ),
      );
    }
    if (data.containsKey('classification_reasons_json')) {
      context.handle(
        _classificationReasonsJsonMeta,
        classificationReasonsJson.isAcceptableOrUnknown(
          data['classification_reasons_json']!,
          _classificationReasonsJsonMeta,
        ),
      );
    }
    if (data.containsKey('classification_confidence')) {
      context.handle(
        _classificationConfidenceMeta,
        classificationConfidence.isAcceptableOrUnknown(
          data['classification_confidence']!,
          _classificationConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('classification_version')) {
      context.handle(
        _classificationVersionMeta,
        classificationVersion.isAcceptableOrUnknown(
          data['classification_version']!,
          _classificationVersionMeta,
        ),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Document map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Document(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      originalFilename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_filename'],
      )!,
      storedFilename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stored_filename'],
      )!,
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      extractedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extracted_text'],
      )!,
      extractionStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extraction_status'],
      )!,
      extractionError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extraction_error'],
      ),
      extractionMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extraction_method'],
      ),
      processingStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_status'],
      )!,
      processingError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_error'],
      ),
      processingStartedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_started_at'],
      ),
      processingCompletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_completed_at'],
      ),
      processingAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}processing_attempts'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      ),
      sourceModifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_modified_at'],
      ),
      documentTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_title'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      tagsText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_text'],
      )!,
      documentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_type'],
      ),
      issuer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issuer'],
      ),
      referenceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_number'],
      ),
      documentDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_date'],
      ),
      classificationReasonsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classification_reasons_json'],
      )!,
      classificationConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}classification_confidence'],
      ),
      classificationVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classification_version'],
      ),
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $DocumentsTable createAlias(String alias) {
    return $DocumentsTable(attachedDatabase, alias);
  }
}

class Document extends DataClass implements Insertable<Document> {
  final String id;
  final String originalFilename;
  final String storedFilename;
  final String mediaType;
  final int sizeBytes;
  final String sha256;
  final String extractedText;
  final String extractionStatus;
  final String? extractionError;
  final String? extractionMethod;
  final String processingStatus;
  final String? processingError;
  final String? processingStartedAt;
  final String? processingCompletedAt;
  final int processingAttempts;
  final int? pageCount;
  final String? sourceModifiedAt;
  final String? documentTitle;
  final String? category;
  final String tagsJson;
  final String tagsText;
  final String? documentType;
  final String? issuer;
  final String? referenceNumber;
  final String? documentDate;
  final String classificationReasonsJson;
  final double? classificationConfidence;
  final String? classificationVersion;
  final bool isDeleted;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  const Document({
    required this.id,
    required this.originalFilename,
    required this.storedFilename,
    required this.mediaType,
    required this.sizeBytes,
    required this.sha256,
    required this.extractedText,
    required this.extractionStatus,
    this.extractionError,
    this.extractionMethod,
    required this.processingStatus,
    this.processingError,
    this.processingStartedAt,
    this.processingCompletedAt,
    required this.processingAttempts,
    this.pageCount,
    this.sourceModifiedAt,
    this.documentTitle,
    this.category,
    required this.tagsJson,
    required this.tagsText,
    this.documentType,
    this.issuer,
    this.referenceNumber,
    this.documentDate,
    required this.classificationReasonsJson,
    this.classificationConfidence,
    this.classificationVersion,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['original_filename'] = Variable<String>(originalFilename);
    map['stored_filename'] = Variable<String>(storedFilename);
    map['media_type'] = Variable<String>(mediaType);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['sha256'] = Variable<String>(sha256);
    map['extracted_text'] = Variable<String>(extractedText);
    map['extraction_status'] = Variable<String>(extractionStatus);
    if (!nullToAbsent || extractionError != null) {
      map['extraction_error'] = Variable<String>(extractionError);
    }
    if (!nullToAbsent || extractionMethod != null) {
      map['extraction_method'] = Variable<String>(extractionMethod);
    }
    map['processing_status'] = Variable<String>(processingStatus);
    if (!nullToAbsent || processingError != null) {
      map['processing_error'] = Variable<String>(processingError);
    }
    if (!nullToAbsent || processingStartedAt != null) {
      map['processing_started_at'] = Variable<String>(processingStartedAt);
    }
    if (!nullToAbsent || processingCompletedAt != null) {
      map['processing_completed_at'] = Variable<String>(processingCompletedAt);
    }
    map['processing_attempts'] = Variable<int>(processingAttempts);
    if (!nullToAbsent || pageCount != null) {
      map['page_count'] = Variable<int>(pageCount);
    }
    if (!nullToAbsent || sourceModifiedAt != null) {
      map['source_modified_at'] = Variable<String>(sourceModifiedAt);
    }
    if (!nullToAbsent || documentTitle != null) {
      map['document_title'] = Variable<String>(documentTitle);
    }
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['tags_json'] = Variable<String>(tagsJson);
    map['tags_text'] = Variable<String>(tagsText);
    if (!nullToAbsent || documentType != null) {
      map['document_type'] = Variable<String>(documentType);
    }
    if (!nullToAbsent || issuer != null) {
      map['issuer'] = Variable<String>(issuer);
    }
    if (!nullToAbsent || referenceNumber != null) {
      map['reference_number'] = Variable<String>(referenceNumber);
    }
    if (!nullToAbsent || documentDate != null) {
      map['document_date'] = Variable<String>(documentDate);
    }
    map['classification_reasons_json'] = Variable<String>(
      classificationReasonsJson,
    );
    if (!nullToAbsent || classificationConfidence != null) {
      map['classification_confidence'] = Variable<double>(
        classificationConfidence,
      );
    }
    if (!nullToAbsent || classificationVersion != null) {
      map['classification_version'] = Variable<String>(classificationVersion);
    }
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  DocumentsCompanion toCompanion(bool nullToAbsent) {
    return DocumentsCompanion(
      id: Value(id),
      originalFilename: Value(originalFilename),
      storedFilename: Value(storedFilename),
      mediaType: Value(mediaType),
      sizeBytes: Value(sizeBytes),
      sha256: Value(sha256),
      extractedText: Value(extractedText),
      extractionStatus: Value(extractionStatus),
      extractionError: extractionError == null && nullToAbsent
          ? const Value.absent()
          : Value(extractionError),
      extractionMethod: extractionMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(extractionMethod),
      processingStatus: Value(processingStatus),
      processingError: processingError == null && nullToAbsent
          ? const Value.absent()
          : Value(processingError),
      processingStartedAt: processingStartedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(processingStartedAt),
      processingCompletedAt: processingCompletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(processingCompletedAt),
      processingAttempts: Value(processingAttempts),
      pageCount: pageCount == null && nullToAbsent
          ? const Value.absent()
          : Value(pageCount),
      sourceModifiedAt: sourceModifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceModifiedAt),
      documentTitle: documentTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(documentTitle),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      tagsJson: Value(tagsJson),
      tagsText: Value(tagsText),
      documentType: documentType == null && nullToAbsent
          ? const Value.absent()
          : Value(documentType),
      issuer: issuer == null && nullToAbsent
          ? const Value.absent()
          : Value(issuer),
      referenceNumber: referenceNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceNumber),
      documentDate: documentDate == null && nullToAbsent
          ? const Value.absent()
          : Value(documentDate),
      classificationReasonsJson: Value(classificationReasonsJson),
      classificationConfidence: classificationConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(classificationConfidence),
      classificationVersion: classificationVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(classificationVersion),
      isDeleted: Value(isDeleted),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Document.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Document(
      id: serializer.fromJson<String>(json['id']),
      originalFilename: serializer.fromJson<String>(json['originalFilename']),
      storedFilename: serializer.fromJson<String>(json['storedFilename']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      sha256: serializer.fromJson<String>(json['sha256']),
      extractedText: serializer.fromJson<String>(json['extractedText']),
      extractionStatus: serializer.fromJson<String>(json['extractionStatus']),
      extractionError: serializer.fromJson<String?>(json['extractionError']),
      extractionMethod: serializer.fromJson<String?>(json['extractionMethod']),
      processingStatus: serializer.fromJson<String>(json['processingStatus']),
      processingError: serializer.fromJson<String?>(json['processingError']),
      processingStartedAt: serializer.fromJson<String?>(
        json['processingStartedAt'],
      ),
      processingCompletedAt: serializer.fromJson<String?>(
        json['processingCompletedAt'],
      ),
      processingAttempts: serializer.fromJson<int>(json['processingAttempts']),
      pageCount: serializer.fromJson<int?>(json['pageCount']),
      sourceModifiedAt: serializer.fromJson<String?>(json['sourceModifiedAt']),
      documentTitle: serializer.fromJson<String?>(json['documentTitle']),
      category: serializer.fromJson<String?>(json['category']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      tagsText: serializer.fromJson<String>(json['tagsText']),
      documentType: serializer.fromJson<String?>(json['documentType']),
      issuer: serializer.fromJson<String?>(json['issuer']),
      referenceNumber: serializer.fromJson<String?>(json['referenceNumber']),
      documentDate: serializer.fromJson<String?>(json['documentDate']),
      classificationReasonsJson: serializer.fromJson<String>(
        json['classificationReasonsJson'],
      ),
      classificationConfidence: serializer.fromJson<double?>(
        json['classificationConfidence'],
      ),
      classificationVersion: serializer.fromJson<String?>(
        json['classificationVersion'],
      ),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'originalFilename': serializer.toJson<String>(originalFilename),
      'storedFilename': serializer.toJson<String>(storedFilename),
      'mediaType': serializer.toJson<String>(mediaType),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'sha256': serializer.toJson<String>(sha256),
      'extractedText': serializer.toJson<String>(extractedText),
      'extractionStatus': serializer.toJson<String>(extractionStatus),
      'extractionError': serializer.toJson<String?>(extractionError),
      'extractionMethod': serializer.toJson<String?>(extractionMethod),
      'processingStatus': serializer.toJson<String>(processingStatus),
      'processingError': serializer.toJson<String?>(processingError),
      'processingStartedAt': serializer.toJson<String?>(processingStartedAt),
      'processingCompletedAt': serializer.toJson<String?>(
        processingCompletedAt,
      ),
      'processingAttempts': serializer.toJson<int>(processingAttempts),
      'pageCount': serializer.toJson<int?>(pageCount),
      'sourceModifiedAt': serializer.toJson<String?>(sourceModifiedAt),
      'documentTitle': serializer.toJson<String?>(documentTitle),
      'category': serializer.toJson<String?>(category),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'tagsText': serializer.toJson<String>(tagsText),
      'documentType': serializer.toJson<String?>(documentType),
      'issuer': serializer.toJson<String?>(issuer),
      'referenceNumber': serializer.toJson<String?>(referenceNumber),
      'documentDate': serializer.toJson<String?>(documentDate),
      'classificationReasonsJson': serializer.toJson<String>(
        classificationReasonsJson,
      ),
      'classificationConfidence': serializer.toJson<double?>(
        classificationConfidence,
      ),
      'classificationVersion': serializer.toJson<String?>(
        classificationVersion,
      ),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  Document copyWith({
    String? id,
    String? originalFilename,
    String? storedFilename,
    String? mediaType,
    int? sizeBytes,
    String? sha256,
    String? extractedText,
    String? extractionStatus,
    Value<String?> extractionError = const Value.absent(),
    Value<String?> extractionMethod = const Value.absent(),
    String? processingStatus,
    Value<String?> processingError = const Value.absent(),
    Value<String?> processingStartedAt = const Value.absent(),
    Value<String?> processingCompletedAt = const Value.absent(),
    int? processingAttempts,
    Value<int?> pageCount = const Value.absent(),
    Value<String?> sourceModifiedAt = const Value.absent(),
    Value<String?> documentTitle = const Value.absent(),
    Value<String?> category = const Value.absent(),
    String? tagsJson,
    String? tagsText,
    Value<String?> documentType = const Value.absent(),
    Value<String?> issuer = const Value.absent(),
    Value<String?> referenceNumber = const Value.absent(),
    Value<String?> documentDate = const Value.absent(),
    String? classificationReasonsJson,
    Value<double?> classificationConfidence = const Value.absent(),
    Value<String?> classificationVersion = const Value.absent(),
    bool? isDeleted,
    String? createdAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => Document(
    id: id ?? this.id,
    originalFilename: originalFilename ?? this.originalFilename,
    storedFilename: storedFilename ?? this.storedFilename,
    mediaType: mediaType ?? this.mediaType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256 ?? this.sha256,
    extractedText: extractedText ?? this.extractedText,
    extractionStatus: extractionStatus ?? this.extractionStatus,
    extractionError: extractionError.present
        ? extractionError.value
        : this.extractionError,
    extractionMethod: extractionMethod.present
        ? extractionMethod.value
        : this.extractionMethod,
    processingStatus: processingStatus ?? this.processingStatus,
    processingError: processingError.present
        ? processingError.value
        : this.processingError,
    processingStartedAt: processingStartedAt.present
        ? processingStartedAt.value
        : this.processingStartedAt,
    processingCompletedAt: processingCompletedAt.present
        ? processingCompletedAt.value
        : this.processingCompletedAt,
    processingAttempts: processingAttempts ?? this.processingAttempts,
    pageCount: pageCount.present ? pageCount.value : this.pageCount,
    sourceModifiedAt: sourceModifiedAt.present
        ? sourceModifiedAt.value
        : this.sourceModifiedAt,
    documentTitle: documentTitle.present
        ? documentTitle.value
        : this.documentTitle,
    category: category.present ? category.value : this.category,
    tagsJson: tagsJson ?? this.tagsJson,
    tagsText: tagsText ?? this.tagsText,
    documentType: documentType.present ? documentType.value : this.documentType,
    issuer: issuer.present ? issuer.value : this.issuer,
    referenceNumber: referenceNumber.present
        ? referenceNumber.value
        : this.referenceNumber,
    documentDate: documentDate.present ? documentDate.value : this.documentDate,
    classificationReasonsJson:
        classificationReasonsJson ?? this.classificationReasonsJson,
    classificationConfidence: classificationConfidence.present
        ? classificationConfidence.value
        : this.classificationConfidence,
    classificationVersion: classificationVersion.present
        ? classificationVersion.value
        : this.classificationVersion,
    isDeleted: isDeleted ?? this.isDeleted,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Document copyWithCompanion(DocumentsCompanion data) {
    return Document(
      id: data.id.present ? data.id.value : this.id,
      originalFilename: data.originalFilename.present
          ? data.originalFilename.value
          : this.originalFilename,
      storedFilename: data.storedFilename.present
          ? data.storedFilename.value
          : this.storedFilename,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      extractedText: data.extractedText.present
          ? data.extractedText.value
          : this.extractedText,
      extractionStatus: data.extractionStatus.present
          ? data.extractionStatus.value
          : this.extractionStatus,
      extractionError: data.extractionError.present
          ? data.extractionError.value
          : this.extractionError,
      extractionMethod: data.extractionMethod.present
          ? data.extractionMethod.value
          : this.extractionMethod,
      processingStatus: data.processingStatus.present
          ? data.processingStatus.value
          : this.processingStatus,
      processingError: data.processingError.present
          ? data.processingError.value
          : this.processingError,
      processingStartedAt: data.processingStartedAt.present
          ? data.processingStartedAt.value
          : this.processingStartedAt,
      processingCompletedAt: data.processingCompletedAt.present
          ? data.processingCompletedAt.value
          : this.processingCompletedAt,
      processingAttempts: data.processingAttempts.present
          ? data.processingAttempts.value
          : this.processingAttempts,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      sourceModifiedAt: data.sourceModifiedAt.present
          ? data.sourceModifiedAt.value
          : this.sourceModifiedAt,
      documentTitle: data.documentTitle.present
          ? data.documentTitle.value
          : this.documentTitle,
      category: data.category.present ? data.category.value : this.category,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      tagsText: data.tagsText.present ? data.tagsText.value : this.tagsText,
      documentType: data.documentType.present
          ? data.documentType.value
          : this.documentType,
      issuer: data.issuer.present ? data.issuer.value : this.issuer,
      referenceNumber: data.referenceNumber.present
          ? data.referenceNumber.value
          : this.referenceNumber,
      documentDate: data.documentDate.present
          ? data.documentDate.value
          : this.documentDate,
      classificationReasonsJson: data.classificationReasonsJson.present
          ? data.classificationReasonsJson.value
          : this.classificationReasonsJson,
      classificationConfidence: data.classificationConfidence.present
          ? data.classificationConfidence.value
          : this.classificationConfidence,
      classificationVersion: data.classificationVersion.present
          ? data.classificationVersion.value
          : this.classificationVersion,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Document(')
          ..write('id: $id, ')
          ..write('originalFilename: $originalFilename, ')
          ..write('storedFilename: $storedFilename, ')
          ..write('mediaType: $mediaType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('extractedText: $extractedText, ')
          ..write('extractionStatus: $extractionStatus, ')
          ..write('extractionError: $extractionError, ')
          ..write('extractionMethod: $extractionMethod, ')
          ..write('processingStatus: $processingStatus, ')
          ..write('processingError: $processingError, ')
          ..write('processingStartedAt: $processingStartedAt, ')
          ..write('processingCompletedAt: $processingCompletedAt, ')
          ..write('processingAttempts: $processingAttempts, ')
          ..write('pageCount: $pageCount, ')
          ..write('sourceModifiedAt: $sourceModifiedAt, ')
          ..write('documentTitle: $documentTitle, ')
          ..write('category: $category, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('tagsText: $tagsText, ')
          ..write('documentType: $documentType, ')
          ..write('issuer: $issuer, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('documentDate: $documentDate, ')
          ..write('classificationReasonsJson: $classificationReasonsJson, ')
          ..write('classificationConfidence: $classificationConfidence, ')
          ..write('classificationVersion: $classificationVersion, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    originalFilename,
    storedFilename,
    mediaType,
    sizeBytes,
    sha256,
    extractedText,
    extractionStatus,
    extractionError,
    extractionMethod,
    processingStatus,
    processingError,
    processingStartedAt,
    processingCompletedAt,
    processingAttempts,
    pageCount,
    sourceModifiedAt,
    documentTitle,
    category,
    tagsJson,
    tagsText,
    documentType,
    issuer,
    referenceNumber,
    documentDate,
    classificationReasonsJson,
    classificationConfidence,
    classificationVersion,
    isDeleted,
    createdAt,
    updatedAt,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Document &&
          other.id == this.id &&
          other.originalFilename == this.originalFilename &&
          other.storedFilename == this.storedFilename &&
          other.mediaType == this.mediaType &&
          other.sizeBytes == this.sizeBytes &&
          other.sha256 == this.sha256 &&
          other.extractedText == this.extractedText &&
          other.extractionStatus == this.extractionStatus &&
          other.extractionError == this.extractionError &&
          other.extractionMethod == this.extractionMethod &&
          other.processingStatus == this.processingStatus &&
          other.processingError == this.processingError &&
          other.processingStartedAt == this.processingStartedAt &&
          other.processingCompletedAt == this.processingCompletedAt &&
          other.processingAttempts == this.processingAttempts &&
          other.pageCount == this.pageCount &&
          other.sourceModifiedAt == this.sourceModifiedAt &&
          other.documentTitle == this.documentTitle &&
          other.category == this.category &&
          other.tagsJson == this.tagsJson &&
          other.tagsText == this.tagsText &&
          other.documentType == this.documentType &&
          other.issuer == this.issuer &&
          other.referenceNumber == this.referenceNumber &&
          other.documentDate == this.documentDate &&
          other.classificationReasonsJson == this.classificationReasonsJson &&
          other.classificationConfidence == this.classificationConfidence &&
          other.classificationVersion == this.classificationVersion &&
          other.isDeleted == this.isDeleted &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class DocumentsCompanion extends UpdateCompanion<Document> {
  final Value<String> id;
  final Value<String> originalFilename;
  final Value<String> storedFilename;
  final Value<String> mediaType;
  final Value<int> sizeBytes;
  final Value<String> sha256;
  final Value<String> extractedText;
  final Value<String> extractionStatus;
  final Value<String?> extractionError;
  final Value<String?> extractionMethod;
  final Value<String> processingStatus;
  final Value<String?> processingError;
  final Value<String?> processingStartedAt;
  final Value<String?> processingCompletedAt;
  final Value<int> processingAttempts;
  final Value<int?> pageCount;
  final Value<String?> sourceModifiedAt;
  final Value<String?> documentTitle;
  final Value<String?> category;
  final Value<String> tagsJson;
  final Value<String> tagsText;
  final Value<String?> documentType;
  final Value<String?> issuer;
  final Value<String?> referenceNumber;
  final Value<String?> documentDate;
  final Value<String> classificationReasonsJson;
  final Value<double?> classificationConfidence;
  final Value<String?> classificationVersion;
  final Value<bool> isDeleted;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const DocumentsCompanion({
    this.id = const Value.absent(),
    this.originalFilename = const Value.absent(),
    this.storedFilename = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.extractedText = const Value.absent(),
    this.extractionStatus = const Value.absent(),
    this.extractionError = const Value.absent(),
    this.extractionMethod = const Value.absent(),
    this.processingStatus = const Value.absent(),
    this.processingError = const Value.absent(),
    this.processingStartedAt = const Value.absent(),
    this.processingCompletedAt = const Value.absent(),
    this.processingAttempts = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.sourceModifiedAt = const Value.absent(),
    this.documentTitle = const Value.absent(),
    this.category = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.tagsText = const Value.absent(),
    this.documentType = const Value.absent(),
    this.issuer = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.documentDate = const Value.absent(),
    this.classificationReasonsJson = const Value.absent(),
    this.classificationConfidence = const Value.absent(),
    this.classificationVersion = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentsCompanion.insert({
    required String id,
    required String originalFilename,
    required String storedFilename,
    required String mediaType,
    required int sizeBytes,
    required String sha256,
    this.extractedText = const Value.absent(),
    this.extractionStatus = const Value.absent(),
    this.extractionError = const Value.absent(),
    this.extractionMethod = const Value.absent(),
    this.processingStatus = const Value.absent(),
    this.processingError = const Value.absent(),
    this.processingStartedAt = const Value.absent(),
    this.processingCompletedAt = const Value.absent(),
    this.processingAttempts = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.sourceModifiedAt = const Value.absent(),
    this.documentTitle = const Value.absent(),
    this.category = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.tagsText = const Value.absent(),
    this.documentType = const Value.absent(),
    this.issuer = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.documentDate = const Value.absent(),
    this.classificationReasonsJson = const Value.absent(),
    this.classificationConfidence = const Value.absent(),
    this.classificationVersion = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       originalFilename = Value(originalFilename),
       storedFilename = Value(storedFilename),
       mediaType = Value(mediaType),
       sizeBytes = Value(sizeBytes),
       sha256 = Value(sha256),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Document> custom({
    Expression<String>? id,
    Expression<String>? originalFilename,
    Expression<String>? storedFilename,
    Expression<String>? mediaType,
    Expression<int>? sizeBytes,
    Expression<String>? sha256,
    Expression<String>? extractedText,
    Expression<String>? extractionStatus,
    Expression<String>? extractionError,
    Expression<String>? extractionMethod,
    Expression<String>? processingStatus,
    Expression<String>? processingError,
    Expression<String>? processingStartedAt,
    Expression<String>? processingCompletedAt,
    Expression<int>? processingAttempts,
    Expression<int>? pageCount,
    Expression<String>? sourceModifiedAt,
    Expression<String>? documentTitle,
    Expression<String>? category,
    Expression<String>? tagsJson,
    Expression<String>? tagsText,
    Expression<String>? documentType,
    Expression<String>? issuer,
    Expression<String>? referenceNumber,
    Expression<String>? documentDate,
    Expression<String>? classificationReasonsJson,
    Expression<double>? classificationConfidence,
    Expression<String>? classificationVersion,
    Expression<bool>? isDeleted,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (originalFilename != null) 'original_filename': originalFilename,
      if (storedFilename != null) 'stored_filename': storedFilename,
      if (mediaType != null) 'media_type': mediaType,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (sha256 != null) 'sha256': sha256,
      if (extractedText != null) 'extracted_text': extractedText,
      if (extractionStatus != null) 'extraction_status': extractionStatus,
      if (extractionError != null) 'extraction_error': extractionError,
      if (extractionMethod != null) 'extraction_method': extractionMethod,
      if (processingStatus != null) 'processing_status': processingStatus,
      if (processingError != null) 'processing_error': processingError,
      if (processingStartedAt != null)
        'processing_started_at': processingStartedAt,
      if (processingCompletedAt != null)
        'processing_completed_at': processingCompletedAt,
      if (processingAttempts != null) 'processing_attempts': processingAttempts,
      if (pageCount != null) 'page_count': pageCount,
      if (sourceModifiedAt != null) 'source_modified_at': sourceModifiedAt,
      if (documentTitle != null) 'document_title': documentTitle,
      if (category != null) 'category': category,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (tagsText != null) 'tags_text': tagsText,
      if (documentType != null) 'document_type': documentType,
      if (issuer != null) 'issuer': issuer,
      if (referenceNumber != null) 'reference_number': referenceNumber,
      if (documentDate != null) 'document_date': documentDate,
      if (classificationReasonsJson != null)
        'classification_reasons_json': classificationReasonsJson,
      if (classificationConfidence != null)
        'classification_confidence': classificationConfidence,
      if (classificationVersion != null)
        'classification_version': classificationVersion,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentsCompanion copyWith({
    Value<String>? id,
    Value<String>? originalFilename,
    Value<String>? storedFilename,
    Value<String>? mediaType,
    Value<int>? sizeBytes,
    Value<String>? sha256,
    Value<String>? extractedText,
    Value<String>? extractionStatus,
    Value<String?>? extractionError,
    Value<String?>? extractionMethod,
    Value<String>? processingStatus,
    Value<String?>? processingError,
    Value<String?>? processingStartedAt,
    Value<String?>? processingCompletedAt,
    Value<int>? processingAttempts,
    Value<int?>? pageCount,
    Value<String?>? sourceModifiedAt,
    Value<String?>? documentTitle,
    Value<String?>? category,
    Value<String>? tagsJson,
    Value<String>? tagsText,
    Value<String?>? documentType,
    Value<String?>? issuer,
    Value<String?>? referenceNumber,
    Value<String?>? documentDate,
    Value<String>? classificationReasonsJson,
    Value<double?>? classificationConfidence,
    Value<String?>? classificationVersion,
    Value<bool>? isDeleted,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return DocumentsCompanion(
      id: id ?? this.id,
      originalFilename: originalFilename ?? this.originalFilename,
      storedFilename: storedFilename ?? this.storedFilename,
      mediaType: mediaType ?? this.mediaType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      extractedText: extractedText ?? this.extractedText,
      extractionStatus: extractionStatus ?? this.extractionStatus,
      extractionError: extractionError ?? this.extractionError,
      extractionMethod: extractionMethod ?? this.extractionMethod,
      processingStatus: processingStatus ?? this.processingStatus,
      processingError: processingError ?? this.processingError,
      processingStartedAt: processingStartedAt ?? this.processingStartedAt,
      processingCompletedAt:
          processingCompletedAt ?? this.processingCompletedAt,
      processingAttempts: processingAttempts ?? this.processingAttempts,
      pageCount: pageCount ?? this.pageCount,
      sourceModifiedAt: sourceModifiedAt ?? this.sourceModifiedAt,
      documentTitle: documentTitle ?? this.documentTitle,
      category: category ?? this.category,
      tagsJson: tagsJson ?? this.tagsJson,
      tagsText: tagsText ?? this.tagsText,
      documentType: documentType ?? this.documentType,
      issuer: issuer ?? this.issuer,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      documentDate: documentDate ?? this.documentDate,
      classificationReasonsJson:
          classificationReasonsJson ?? this.classificationReasonsJson,
      classificationConfidence:
          classificationConfidence ?? this.classificationConfidence,
      classificationVersion:
          classificationVersion ?? this.classificationVersion,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (originalFilename.present) {
      map['original_filename'] = Variable<String>(originalFilename.value);
    }
    if (storedFilename.present) {
      map['stored_filename'] = Variable<String>(storedFilename.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (extractedText.present) {
      map['extracted_text'] = Variable<String>(extractedText.value);
    }
    if (extractionStatus.present) {
      map['extraction_status'] = Variable<String>(extractionStatus.value);
    }
    if (extractionError.present) {
      map['extraction_error'] = Variable<String>(extractionError.value);
    }
    if (extractionMethod.present) {
      map['extraction_method'] = Variable<String>(extractionMethod.value);
    }
    if (processingStatus.present) {
      map['processing_status'] = Variable<String>(processingStatus.value);
    }
    if (processingError.present) {
      map['processing_error'] = Variable<String>(processingError.value);
    }
    if (processingStartedAt.present) {
      map['processing_started_at'] = Variable<String>(
        processingStartedAt.value,
      );
    }
    if (processingCompletedAt.present) {
      map['processing_completed_at'] = Variable<String>(
        processingCompletedAt.value,
      );
    }
    if (processingAttempts.present) {
      map['processing_attempts'] = Variable<int>(processingAttempts.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (sourceModifiedAt.present) {
      map['source_modified_at'] = Variable<String>(sourceModifiedAt.value);
    }
    if (documentTitle.present) {
      map['document_title'] = Variable<String>(documentTitle.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (tagsText.present) {
      map['tags_text'] = Variable<String>(tagsText.value);
    }
    if (documentType.present) {
      map['document_type'] = Variable<String>(documentType.value);
    }
    if (issuer.present) {
      map['issuer'] = Variable<String>(issuer.value);
    }
    if (referenceNumber.present) {
      map['reference_number'] = Variable<String>(referenceNumber.value);
    }
    if (documentDate.present) {
      map['document_date'] = Variable<String>(documentDate.value);
    }
    if (classificationReasonsJson.present) {
      map['classification_reasons_json'] = Variable<String>(
        classificationReasonsJson.value,
      );
    }
    if (classificationConfidence.present) {
      map['classification_confidence'] = Variable<double>(
        classificationConfidence.value,
      );
    }
    if (classificationVersion.present) {
      map['classification_version'] = Variable<String>(
        classificationVersion.value,
      );
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentsCompanion(')
          ..write('id: $id, ')
          ..write('originalFilename: $originalFilename, ')
          ..write('storedFilename: $storedFilename, ')
          ..write('mediaType: $mediaType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('extractedText: $extractedText, ')
          ..write('extractionStatus: $extractionStatus, ')
          ..write('extractionError: $extractionError, ')
          ..write('extractionMethod: $extractionMethod, ')
          ..write('processingStatus: $processingStatus, ')
          ..write('processingError: $processingError, ')
          ..write('processingStartedAt: $processingStartedAt, ')
          ..write('processingCompletedAt: $processingCompletedAt, ')
          ..write('processingAttempts: $processingAttempts, ')
          ..write('pageCount: $pageCount, ')
          ..write('sourceModifiedAt: $sourceModifiedAt, ')
          ..write('documentTitle: $documentTitle, ')
          ..write('category: $category, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('tagsText: $tagsText, ')
          ..write('documentType: $documentType, ')
          ..write('issuer: $issuer, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('documentDate: $documentDate, ')
          ..write('classificationReasonsJson: $classificationReasonsJson, ')
          ..write('classificationConfidence: $classificationConfidence, ')
          ..write('classificationVersion: $classificationVersion, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DocumentRelationshipsTable extends DocumentRelationships
    with TableInfo<$DocumentRelationshipsTable, DocumentRelationship> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentRelationshipsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceDocumentIdMeta = const VerificationMeta(
    'sourceDocumentId',
  );
  @override
  late final GeneratedColumn<String> sourceDocumentId = GeneratedColumn<String>(
    'source_document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES documents (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _relatedDocumentIdMeta = const VerificationMeta(
    'relatedDocumentId',
  );
  @override
  late final GeneratedColumn<String> relatedDocumentId =
      GeneratedColumn<String>(
        'related_document_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES documents (id) ON DELETE CASCADE',
        ),
      );
  static const VerificationMeta _relationshipTypeMeta = const VerificationMeta(
    'relationshipType',
  );
  @override
  late final GeneratedColumn<String> relationshipType = GeneratedColumn<String>(
    'relationship_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _explanationMeta = const VerificationMeta(
    'explanation',
  );
  @override
  late final GeneratedColumn<String> explanation = GeneratedColumn<String>(
    'explanation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _evidenceJsonMeta = const VerificationMeta(
    'evidenceJson',
  );
  @override
  late final GeneratedColumn<String> evidenceJson = GeneratedColumn<String>(
    'evidence_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _calculatedAtMeta = const VerificationMeta(
    'calculatedAt',
  );
  @override
  late final GeneratedColumn<String> calculatedAt = GeneratedColumn<String>(
    'calculated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceDocumentId,
    relatedDocumentId,
    relationshipType,
    score,
    explanation,
    evidenceJson,
    calculatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'document_relationships';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocumentRelationship> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_document_id')) {
      context.handle(
        _sourceDocumentIdMeta,
        sourceDocumentId.isAcceptableOrUnknown(
          data['source_document_id']!,
          _sourceDocumentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceDocumentIdMeta);
    }
    if (data.containsKey('related_document_id')) {
      context.handle(
        _relatedDocumentIdMeta,
        relatedDocumentId.isAcceptableOrUnknown(
          data['related_document_id']!,
          _relatedDocumentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relatedDocumentIdMeta);
    }
    if (data.containsKey('relationship_type')) {
      context.handle(
        _relationshipTypeMeta,
        relationshipType.isAcceptableOrUnknown(
          data['relationship_type']!,
          _relationshipTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relationshipTypeMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('explanation')) {
      context.handle(
        _explanationMeta,
        explanation.isAcceptableOrUnknown(
          data['explanation']!,
          _explanationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_explanationMeta);
    }
    if (data.containsKey('evidence_json')) {
      context.handle(
        _evidenceJsonMeta,
        evidenceJson.isAcceptableOrUnknown(
          data['evidence_json']!,
          _evidenceJsonMeta,
        ),
      );
    }
    if (data.containsKey('calculated_at')) {
      context.handle(
        _calculatedAtMeta,
        calculatedAt.isAcceptableOrUnknown(
          data['calculated_at']!,
          _calculatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_calculatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DocumentRelationship map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocumentRelationship(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceDocumentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_document_id'],
      )!,
      relatedDocumentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}related_document_id'],
      )!,
      relationshipType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relationship_type'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      )!,
      explanation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}explanation'],
      )!,
      evidenceJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_json'],
      )!,
      calculatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}calculated_at'],
      )!,
    );
  }

  @override
  $DocumentRelationshipsTable createAlias(String alias) {
    return $DocumentRelationshipsTable(attachedDatabase, alias);
  }
}

class DocumentRelationship extends DataClass
    implements Insertable<DocumentRelationship> {
  final String id;
  final String sourceDocumentId;
  final String relatedDocumentId;
  final String relationshipType;
  final double score;
  final String explanation;
  final String evidenceJson;
  final String calculatedAt;
  const DocumentRelationship({
    required this.id,
    required this.sourceDocumentId,
    required this.relatedDocumentId,
    required this.relationshipType,
    required this.score,
    required this.explanation,
    required this.evidenceJson,
    required this.calculatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_document_id'] = Variable<String>(sourceDocumentId);
    map['related_document_id'] = Variable<String>(relatedDocumentId);
    map['relationship_type'] = Variable<String>(relationshipType);
    map['score'] = Variable<double>(score);
    map['explanation'] = Variable<String>(explanation);
    map['evidence_json'] = Variable<String>(evidenceJson);
    map['calculated_at'] = Variable<String>(calculatedAt);
    return map;
  }

  DocumentRelationshipsCompanion toCompanion(bool nullToAbsent) {
    return DocumentRelationshipsCompanion(
      id: Value(id),
      sourceDocumentId: Value(sourceDocumentId),
      relatedDocumentId: Value(relatedDocumentId),
      relationshipType: Value(relationshipType),
      score: Value(score),
      explanation: Value(explanation),
      evidenceJson: Value(evidenceJson),
      calculatedAt: Value(calculatedAt),
    );
  }

  factory DocumentRelationship.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocumentRelationship(
      id: serializer.fromJson<String>(json['id']),
      sourceDocumentId: serializer.fromJson<String>(json['sourceDocumentId']),
      relatedDocumentId: serializer.fromJson<String>(json['relatedDocumentId']),
      relationshipType: serializer.fromJson<String>(json['relationshipType']),
      score: serializer.fromJson<double>(json['score']),
      explanation: serializer.fromJson<String>(json['explanation']),
      evidenceJson: serializer.fromJson<String>(json['evidenceJson']),
      calculatedAt: serializer.fromJson<String>(json['calculatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceDocumentId': serializer.toJson<String>(sourceDocumentId),
      'relatedDocumentId': serializer.toJson<String>(relatedDocumentId),
      'relationshipType': serializer.toJson<String>(relationshipType),
      'score': serializer.toJson<double>(score),
      'explanation': serializer.toJson<String>(explanation),
      'evidenceJson': serializer.toJson<String>(evidenceJson),
      'calculatedAt': serializer.toJson<String>(calculatedAt),
    };
  }

  DocumentRelationship copyWith({
    String? id,
    String? sourceDocumentId,
    String? relatedDocumentId,
    String? relationshipType,
    double? score,
    String? explanation,
    String? evidenceJson,
    String? calculatedAt,
  }) => DocumentRelationship(
    id: id ?? this.id,
    sourceDocumentId: sourceDocumentId ?? this.sourceDocumentId,
    relatedDocumentId: relatedDocumentId ?? this.relatedDocumentId,
    relationshipType: relationshipType ?? this.relationshipType,
    score: score ?? this.score,
    explanation: explanation ?? this.explanation,
    evidenceJson: evidenceJson ?? this.evidenceJson,
    calculatedAt: calculatedAt ?? this.calculatedAt,
  );
  DocumentRelationship copyWithCompanion(DocumentRelationshipsCompanion data) {
    return DocumentRelationship(
      id: data.id.present ? data.id.value : this.id,
      sourceDocumentId: data.sourceDocumentId.present
          ? data.sourceDocumentId.value
          : this.sourceDocumentId,
      relatedDocumentId: data.relatedDocumentId.present
          ? data.relatedDocumentId.value
          : this.relatedDocumentId,
      relationshipType: data.relationshipType.present
          ? data.relationshipType.value
          : this.relationshipType,
      score: data.score.present ? data.score.value : this.score,
      explanation: data.explanation.present
          ? data.explanation.value
          : this.explanation,
      evidenceJson: data.evidenceJson.present
          ? data.evidenceJson.value
          : this.evidenceJson,
      calculatedAt: data.calculatedAt.present
          ? data.calculatedAt.value
          : this.calculatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocumentRelationship(')
          ..write('id: $id, ')
          ..write('sourceDocumentId: $sourceDocumentId, ')
          ..write('relatedDocumentId: $relatedDocumentId, ')
          ..write('relationshipType: $relationshipType, ')
          ..write('score: $score, ')
          ..write('explanation: $explanation, ')
          ..write('evidenceJson: $evidenceJson, ')
          ..write('calculatedAt: $calculatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceDocumentId,
    relatedDocumentId,
    relationshipType,
    score,
    explanation,
    evidenceJson,
    calculatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentRelationship &&
          other.id == this.id &&
          other.sourceDocumentId == this.sourceDocumentId &&
          other.relatedDocumentId == this.relatedDocumentId &&
          other.relationshipType == this.relationshipType &&
          other.score == this.score &&
          other.explanation == this.explanation &&
          other.evidenceJson == this.evidenceJson &&
          other.calculatedAt == this.calculatedAt);
}

class DocumentRelationshipsCompanion
    extends UpdateCompanion<DocumentRelationship> {
  final Value<String> id;
  final Value<String> sourceDocumentId;
  final Value<String> relatedDocumentId;
  final Value<String> relationshipType;
  final Value<double> score;
  final Value<String> explanation;
  final Value<String> evidenceJson;
  final Value<String> calculatedAt;
  final Value<int> rowid;
  const DocumentRelationshipsCompanion({
    this.id = const Value.absent(),
    this.sourceDocumentId = const Value.absent(),
    this.relatedDocumentId = const Value.absent(),
    this.relationshipType = const Value.absent(),
    this.score = const Value.absent(),
    this.explanation = const Value.absent(),
    this.evidenceJson = const Value.absent(),
    this.calculatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentRelationshipsCompanion.insert({
    required String id,
    required String sourceDocumentId,
    required String relatedDocumentId,
    required String relationshipType,
    required double score,
    required String explanation,
    this.evidenceJson = const Value.absent(),
    required String calculatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceDocumentId = Value(sourceDocumentId),
       relatedDocumentId = Value(relatedDocumentId),
       relationshipType = Value(relationshipType),
       score = Value(score),
       explanation = Value(explanation),
       calculatedAt = Value(calculatedAt);
  static Insertable<DocumentRelationship> custom({
    Expression<String>? id,
    Expression<String>? sourceDocumentId,
    Expression<String>? relatedDocumentId,
    Expression<String>? relationshipType,
    Expression<double>? score,
    Expression<String>? explanation,
    Expression<String>? evidenceJson,
    Expression<String>? calculatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceDocumentId != null) 'source_document_id': sourceDocumentId,
      if (relatedDocumentId != null) 'related_document_id': relatedDocumentId,
      if (relationshipType != null) 'relationship_type': relationshipType,
      if (score != null) 'score': score,
      if (explanation != null) 'explanation': explanation,
      if (evidenceJson != null) 'evidence_json': evidenceJson,
      if (calculatedAt != null) 'calculated_at': calculatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentRelationshipsCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceDocumentId,
    Value<String>? relatedDocumentId,
    Value<String>? relationshipType,
    Value<double>? score,
    Value<String>? explanation,
    Value<String>? evidenceJson,
    Value<String>? calculatedAt,
    Value<int>? rowid,
  }) {
    return DocumentRelationshipsCompanion(
      id: id ?? this.id,
      sourceDocumentId: sourceDocumentId ?? this.sourceDocumentId,
      relatedDocumentId: relatedDocumentId ?? this.relatedDocumentId,
      relationshipType: relationshipType ?? this.relationshipType,
      score: score ?? this.score,
      explanation: explanation ?? this.explanation,
      evidenceJson: evidenceJson ?? this.evidenceJson,
      calculatedAt: calculatedAt ?? this.calculatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceDocumentId.present) {
      map['source_document_id'] = Variable<String>(sourceDocumentId.value);
    }
    if (relatedDocumentId.present) {
      map['related_document_id'] = Variable<String>(relatedDocumentId.value);
    }
    if (relationshipType.present) {
      map['relationship_type'] = Variable<String>(relationshipType.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (explanation.present) {
      map['explanation'] = Variable<String>(explanation.value);
    }
    if (evidenceJson.present) {
      map['evidence_json'] = Variable<String>(evidenceJson.value);
    }
    if (calculatedAt.present) {
      map['calculated_at'] = Variable<String>(calculatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentRelationshipsCompanion(')
          ..write('id: $id, ')
          ..write('sourceDocumentId: $sourceDocumentId, ')
          ..write('relatedDocumentId: $relatedDocumentId, ')
          ..write('relationshipType: $relationshipType, ')
          ..write('score: $score, ')
          ..write('explanation: $explanation, ')
          ..write('evidenceJson: $evidenceJson, ')
          ..write('calculatedAt: $calculatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SchemaMetaTable extends SchemaMeta
    with TableInfo<$SchemaMetaTable, SchemaMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchemaMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schema_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SchemaMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SchemaMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SchemaMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SchemaMetaTable createAlias(String alias) {
    return $SchemaMetaTable(attachedDatabase, alias);
  }
}

class SchemaMetaData extends DataClass implements Insertable<SchemaMetaData> {
  final String key;
  final String value;
  const SchemaMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SchemaMetaCompanion toCompanion(bool nullToAbsent) {
    return SchemaMetaCompanion(key: Value(key), value: Value(value));
  }

  factory SchemaMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SchemaMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SchemaMetaData copyWith({String? key, String? value}) =>
      SchemaMetaData(key: key ?? this.key, value: value ?? this.value);
  SchemaMetaData copyWithCompanion(SchemaMetaCompanion data) {
    return SchemaMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SchemaMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchemaMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class SchemaMetaCompanion extends UpdateCompanion<SchemaMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SchemaMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SchemaMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SchemaMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SchemaMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SchemaMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchemaMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LoreDatabase extends GeneratedDatabase {
  _$LoreDatabase(QueryExecutor e) : super(e);
  $LoreDatabaseManager get managers => $LoreDatabaseManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $DocumentsTable documents = $DocumentsTable(this);
  late final $DocumentRelationshipsTable documentRelationships =
      $DocumentRelationshipsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $SchemaMetaTable schemaMeta = $SchemaMetaTable(this);
  late final Index categoriesSortIdx = Index(
    'categories_sort_idx',
    'CREATE INDEX categories_sort_idx ON categories (sort_order)',
  );
  late final Index documentsCategoryIdx = Index(
    'documents_category_idx',
    'CREATE INDEX documents_category_idx ON documents (category, is_deleted)',
  );
  late final Index documentsCreatedIdx = Index(
    'documents_created_idx',
    'CREATE INDEX documents_created_idx ON documents (created_at)',
  );
  late final Index documentsDeletedIdx = Index(
    'documents_deleted_idx',
    'CREATE INDEX documents_deleted_idx ON documents (is_deleted)',
  );
  late final Index relationshipsSourceIdx = Index(
    'relationships_source_idx',
    'CREATE INDEX relationships_source_idx ON document_relationships (source_document_id)',
  );
  late final Index relationshipsRelatedIdx = Index(
    'relationships_related_idx',
    'CREATE INDEX relationships_related_idx ON document_relationships (related_document_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categories,
    documents,
    documentRelationships,
    appSettings,
    schemaMeta,
    categoriesSortIdx,
    documentsCategoryIdx,
    documentsCreatedIdx,
    documentsDeletedIdx,
    relationshipsSourceIdx,
    relationshipsRelatedIdx,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('documents', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('document_relationships', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('document_relationships', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required String name,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> name,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$CategoriesTableReferences
    extends BaseReferences<_$LoreDatabase, $CategoriesTable, Category> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DocumentsTable, List<Document>>
  _documentsRefsTable(_$LoreDatabase db) => MultiTypedResultKey.fromTable(
    db.documents,
    aliasName: 'categories__name__documents__category',
  );

  $$DocumentsTableProcessedTableManager get documentsRefs {
    final manager = $$DocumentsTableTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.category.name.sqlEquals($_itemColumn<String>('name')!));

    final cache = $_typedResult.readTableOrNull(_documentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$LoreDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> documentsRefs(
    Expression<bool> Function($$DocumentsTableFilterComposer f) f,
  ) {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.name,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.category,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$LoreDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$LoreDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  Expression<T> documentsRefs<T extends Object>(
    Expression<T> Function($$DocumentsTableAnnotationComposer a) f,
  ) {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.name,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.category,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$LoreDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, $$CategoriesTableReferences),
          Category,
          PrefetchHooks Function({bool documentsRefs})
        > {
  $$CategoriesTableTableManager(_$LoreDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String name,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({documentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (documentsRefs) db.documents],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (documentsRefs)
                    await $_getPrefetchedData<
                      Category,
                      $CategoriesTable,
                      Document
                    >(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences
                          ._documentsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CategoriesTableReferences(
                            db,
                            table,
                            p0,
                          ).documentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.category == item.name),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LoreDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, $$CategoriesTableReferences),
      Category,
      PrefetchHooks Function({bool documentsRefs})
    >;
typedef $$DocumentsTableCreateCompanionBuilder =
    DocumentsCompanion Function({
      required String id,
      required String originalFilename,
      required String storedFilename,
      required String mediaType,
      required int sizeBytes,
      required String sha256,
      Value<String> extractedText,
      Value<String> extractionStatus,
      Value<String?> extractionError,
      Value<String?> extractionMethod,
      Value<String> processingStatus,
      Value<String?> processingError,
      Value<String?> processingStartedAt,
      Value<String?> processingCompletedAt,
      Value<int> processingAttempts,
      Value<int?> pageCount,
      Value<String?> sourceModifiedAt,
      Value<String?> documentTitle,
      Value<String?> category,
      Value<String> tagsJson,
      Value<String> tagsText,
      Value<String?> documentType,
      Value<String?> issuer,
      Value<String?> referenceNumber,
      Value<String?> documentDate,
      Value<String> classificationReasonsJson,
      Value<double?> classificationConfidence,
      Value<String?> classificationVersion,
      Value<bool> isDeleted,
      required String createdAt,
      required String updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });
typedef $$DocumentsTableUpdateCompanionBuilder =
    DocumentsCompanion Function({
      Value<String> id,
      Value<String> originalFilename,
      Value<String> storedFilename,
      Value<String> mediaType,
      Value<int> sizeBytes,
      Value<String> sha256,
      Value<String> extractedText,
      Value<String> extractionStatus,
      Value<String?> extractionError,
      Value<String?> extractionMethod,
      Value<String> processingStatus,
      Value<String?> processingError,
      Value<String?> processingStartedAt,
      Value<String?> processingCompletedAt,
      Value<int> processingAttempts,
      Value<int?> pageCount,
      Value<String?> sourceModifiedAt,
      Value<String?> documentTitle,
      Value<String?> category,
      Value<String> tagsJson,
      Value<String> tagsText,
      Value<String?> documentType,
      Value<String?> issuer,
      Value<String?> referenceNumber,
      Value<String?> documentDate,
      Value<String> classificationReasonsJson,
      Value<double?> classificationConfidence,
      Value<String?> classificationVersion,
      Value<bool> isDeleted,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });

final class $$DocumentsTableReferences
    extends BaseReferences<_$LoreDatabase, $DocumentsTable, Document> {
  $$DocumentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryTable(_$LoreDatabase db) =>
      db.categories.createAlias('documents__category__categories__name');

  $$CategoriesTableProcessedTableManager? get category {
    final $_column = $_itemColumn<String>('category');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.name.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DocumentsTableFilterComposer
    extends Composer<_$LoreDatabase, $DocumentsTable> {
  $$DocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalFilename => $composableBuilder(
    column: $table.originalFilename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storedFilename => $composableBuilder(
    column: $table.storedFilename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractedText => $composableBuilder(
    column: $table.extractedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractionStatus => $composableBuilder(
    column: $table.extractionStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractionError => $composableBuilder(
    column: $table.extractionError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractionMethod => $composableBuilder(
    column: $table.extractionMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processingStatus => $composableBuilder(
    column: $table.processingStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processingError => $composableBuilder(
    column: $table.processingError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processingStartedAt => $composableBuilder(
    column: $table.processingStartedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processingCompletedAt => $composableBuilder(
    column: $table.processingCompletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get processingAttempts => $composableBuilder(
    column: $table.processingAttempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceModifiedAt => $composableBuilder(
    column: $table.sourceModifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentTitle => $composableBuilder(
    column: $table.documentTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsText => $composableBuilder(
    column: $table.tagsText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentType => $composableBuilder(
    column: $table.documentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get issuer => $composableBuilder(
    column: $table.issuer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentDate => $composableBuilder(
    column: $table.documentDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get classificationReasonsJson => $composableBuilder(
    column: $table.classificationReasonsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get classificationConfidence => $composableBuilder(
    column: $table.classificationConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get classificationVersion => $composableBuilder(
    column: $table.classificationVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get category {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.category,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.name,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentsTableOrderingComposer
    extends Composer<_$LoreDatabase, $DocumentsTable> {
  $$DocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalFilename => $composableBuilder(
    column: $table.originalFilename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storedFilename => $composableBuilder(
    column: $table.storedFilename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractedText => $composableBuilder(
    column: $table.extractedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractionStatus => $composableBuilder(
    column: $table.extractionStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractionError => $composableBuilder(
    column: $table.extractionError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractionMethod => $composableBuilder(
    column: $table.extractionMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processingStatus => $composableBuilder(
    column: $table.processingStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processingError => $composableBuilder(
    column: $table.processingError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processingStartedAt => $composableBuilder(
    column: $table.processingStartedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processingCompletedAt => $composableBuilder(
    column: $table.processingCompletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get processingAttempts => $composableBuilder(
    column: $table.processingAttempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceModifiedAt => $composableBuilder(
    column: $table.sourceModifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentTitle => $composableBuilder(
    column: $table.documentTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsText => $composableBuilder(
    column: $table.tagsText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentType => $composableBuilder(
    column: $table.documentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get issuer => $composableBuilder(
    column: $table.issuer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentDate => $composableBuilder(
    column: $table.documentDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get classificationReasonsJson => $composableBuilder(
    column: $table.classificationReasonsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get classificationConfidence => $composableBuilder(
    column: $table.classificationConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get classificationVersion => $composableBuilder(
    column: $table.classificationVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get category {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.category,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.name,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentsTableAnnotationComposer
    extends Composer<_$LoreDatabase, $DocumentsTable> {
  $$DocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get originalFilename => $composableBuilder(
    column: $table.originalFilename,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storedFilename => $composableBuilder(
    column: $table.storedFilename,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get extractedText => $composableBuilder(
    column: $table.extractedText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extractionStatus => $composableBuilder(
    column: $table.extractionStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extractionError => $composableBuilder(
    column: $table.extractionError,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extractionMethod => $composableBuilder(
    column: $table.extractionMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processingStatus => $composableBuilder(
    column: $table.processingStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processingError => $composableBuilder(
    column: $table.processingError,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processingStartedAt => $composableBuilder(
    column: $table.processingStartedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processingCompletedAt => $composableBuilder(
    column: $table.processingCompletedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get processingAttempts => $composableBuilder(
    column: $table.processingAttempts,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<String> get sourceModifiedAt => $composableBuilder(
    column: $table.sourceModifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get documentTitle => $composableBuilder(
    column: $table.documentTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get tagsText =>
      $composableBuilder(column: $table.tagsText, builder: (column) => column);

  GeneratedColumn<String> get documentType => $composableBuilder(
    column: $table.documentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get issuer =>
      $composableBuilder(column: $table.issuer, builder: (column) => column);

  GeneratedColumn<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get documentDate => $composableBuilder(
    column: $table.documentDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get classificationReasonsJson => $composableBuilder(
    column: $table.classificationReasonsJson,
    builder: (column) => column,
  );

  GeneratedColumn<double> get classificationConfidence => $composableBuilder(
    column: $table.classificationConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get classificationVersion => $composableBuilder(
    column: $table.classificationVersion,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get category {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.category,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.name,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentsTableTableManager
    extends
        RootTableManager<
          _$LoreDatabase,
          $DocumentsTable,
          Document,
          $$DocumentsTableFilterComposer,
          $$DocumentsTableOrderingComposer,
          $$DocumentsTableAnnotationComposer,
          $$DocumentsTableCreateCompanionBuilder,
          $$DocumentsTableUpdateCompanionBuilder,
          (Document, $$DocumentsTableReferences),
          Document,
          PrefetchHooks Function({bool category})
        > {
  $$DocumentsTableTableManager(_$LoreDatabase db, $DocumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> originalFilename = const Value.absent(),
                Value<String> storedFilename = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String> extractedText = const Value.absent(),
                Value<String> extractionStatus = const Value.absent(),
                Value<String?> extractionError = const Value.absent(),
                Value<String?> extractionMethod = const Value.absent(),
                Value<String> processingStatus = const Value.absent(),
                Value<String?> processingError = const Value.absent(),
                Value<String?> processingStartedAt = const Value.absent(),
                Value<String?> processingCompletedAt = const Value.absent(),
                Value<int> processingAttempts = const Value.absent(),
                Value<int?> pageCount = const Value.absent(),
                Value<String?> sourceModifiedAt = const Value.absent(),
                Value<String?> documentTitle = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String> tagsText = const Value.absent(),
                Value<String?> documentType = const Value.absent(),
                Value<String?> issuer = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<String?> documentDate = const Value.absent(),
                Value<String> classificationReasonsJson = const Value.absent(),
                Value<double?> classificationConfidence = const Value.absent(),
                Value<String?> classificationVersion = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion(
                id: id,
                originalFilename: originalFilename,
                storedFilename: storedFilename,
                mediaType: mediaType,
                sizeBytes: sizeBytes,
                sha256: sha256,
                extractedText: extractedText,
                extractionStatus: extractionStatus,
                extractionError: extractionError,
                extractionMethod: extractionMethod,
                processingStatus: processingStatus,
                processingError: processingError,
                processingStartedAt: processingStartedAt,
                processingCompletedAt: processingCompletedAt,
                processingAttempts: processingAttempts,
                pageCount: pageCount,
                sourceModifiedAt: sourceModifiedAt,
                documentTitle: documentTitle,
                category: category,
                tagsJson: tagsJson,
                tagsText: tagsText,
                documentType: documentType,
                issuer: issuer,
                referenceNumber: referenceNumber,
                documentDate: documentDate,
                classificationReasonsJson: classificationReasonsJson,
                classificationConfidence: classificationConfidence,
                classificationVersion: classificationVersion,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String originalFilename,
                required String storedFilename,
                required String mediaType,
                required int sizeBytes,
                required String sha256,
                Value<String> extractedText = const Value.absent(),
                Value<String> extractionStatus = const Value.absent(),
                Value<String?> extractionError = const Value.absent(),
                Value<String?> extractionMethod = const Value.absent(),
                Value<String> processingStatus = const Value.absent(),
                Value<String?> processingError = const Value.absent(),
                Value<String?> processingStartedAt = const Value.absent(),
                Value<String?> processingCompletedAt = const Value.absent(),
                Value<int> processingAttempts = const Value.absent(),
                Value<int?> pageCount = const Value.absent(),
                Value<String?> sourceModifiedAt = const Value.absent(),
                Value<String?> documentTitle = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String> tagsText = const Value.absent(),
                Value<String?> documentType = const Value.absent(),
                Value<String?> issuer = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<String?> documentDate = const Value.absent(),
                Value<String> classificationReasonsJson = const Value.absent(),
                Value<double?> classificationConfidence = const Value.absent(),
                Value<String?> classificationVersion = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion.insert(
                id: id,
                originalFilename: originalFilename,
                storedFilename: storedFilename,
                mediaType: mediaType,
                sizeBytes: sizeBytes,
                sha256: sha256,
                extractedText: extractedText,
                extractionStatus: extractionStatus,
                extractionError: extractionError,
                extractionMethod: extractionMethod,
                processingStatus: processingStatus,
                processingError: processingError,
                processingStartedAt: processingStartedAt,
                processingCompletedAt: processingCompletedAt,
                processingAttempts: processingAttempts,
                pageCount: pageCount,
                sourceModifiedAt: sourceModifiedAt,
                documentTitle: documentTitle,
                category: category,
                tagsJson: tagsJson,
                tagsText: tagsText,
                documentType: documentType,
                issuer: issuer,
                referenceNumber: referenceNumber,
                documentDate: documentDate,
                classificationReasonsJson: classificationReasonsJson,
                classificationConfidence: classificationConfidence,
                classificationVersion: classificationVersion,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DocumentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({category = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (category) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.category,
                                referencedTable: $$DocumentsTableReferences
                                    ._categoryTable(db),
                                referencedColumn: $$DocumentsTableReferences
                                    ._categoryTable(db)
                                    .name,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$LoreDatabase,
      $DocumentsTable,
      Document,
      $$DocumentsTableFilterComposer,
      $$DocumentsTableOrderingComposer,
      $$DocumentsTableAnnotationComposer,
      $$DocumentsTableCreateCompanionBuilder,
      $$DocumentsTableUpdateCompanionBuilder,
      (Document, $$DocumentsTableReferences),
      Document,
      PrefetchHooks Function({bool category})
    >;
typedef $$DocumentRelationshipsTableCreateCompanionBuilder =
    DocumentRelationshipsCompanion Function({
      required String id,
      required String sourceDocumentId,
      required String relatedDocumentId,
      required String relationshipType,
      required double score,
      required String explanation,
      Value<String> evidenceJson,
      required String calculatedAt,
      Value<int> rowid,
    });
typedef $$DocumentRelationshipsTableUpdateCompanionBuilder =
    DocumentRelationshipsCompanion Function({
      Value<String> id,
      Value<String> sourceDocumentId,
      Value<String> relatedDocumentId,
      Value<String> relationshipType,
      Value<double> score,
      Value<String> explanation,
      Value<String> evidenceJson,
      Value<String> calculatedAt,
      Value<int> rowid,
    });

final class $$DocumentRelationshipsTableReferences
    extends
        BaseReferences<
          _$LoreDatabase,
          $DocumentRelationshipsTable,
          DocumentRelationship
        > {
  $$DocumentRelationshipsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DocumentsTable _sourceDocumentIdTable(_$LoreDatabase db) => db
      .documents
      .createAlias('document_relationships__source_document_id__documents__id');

  $$DocumentsTableProcessedTableManager get sourceDocumentId {
    final $_column = $_itemColumn<String>('source_document_id')!;

    final manager = $$DocumentsTableTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceDocumentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $DocumentsTable _relatedDocumentIdTable(_$LoreDatabase db) =>
      db.documents.createAlias(
        'document_relationships__related_document_id__documents__id',
      );

  $$DocumentsTableProcessedTableManager get relatedDocumentId {
    final $_column = $_itemColumn<String>('related_document_id')!;

    final manager = $$DocumentsTableTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_relatedDocumentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DocumentRelationshipsTableFilterComposer
    extends Composer<_$LoreDatabase, $DocumentRelationshipsTable> {
  $$DocumentRelationshipsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relationshipType => $composableBuilder(
    column: $table.relationshipType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get calculatedAt => $composableBuilder(
    column: $table.calculatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$DocumentsTableFilterComposer get sourceDocumentId {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceDocumentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DocumentsTableFilterComposer get relatedDocumentId {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.relatedDocumentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentRelationshipsTableOrderingComposer
    extends Composer<_$LoreDatabase, $DocumentRelationshipsTable> {
  $$DocumentRelationshipsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relationshipType => $composableBuilder(
    column: $table.relationshipType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get calculatedAt => $composableBuilder(
    column: $table.calculatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$DocumentsTableOrderingComposer get sourceDocumentId {
    final $$DocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceDocumentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DocumentsTableOrderingComposer get relatedDocumentId {
    final $$DocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.relatedDocumentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentRelationshipsTableAnnotationComposer
    extends Composer<_$LoreDatabase, $DocumentRelationshipsTable> {
  $$DocumentRelationshipsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get relationshipType => $composableBuilder(
    column: $table.relationshipType,
    builder: (column) => column,
  );

  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get calculatedAt => $composableBuilder(
    column: $table.calculatedAt,
    builder: (column) => column,
  );

  $$DocumentsTableAnnotationComposer get sourceDocumentId {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceDocumentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DocumentsTableAnnotationComposer get relatedDocumentId {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.relatedDocumentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentRelationshipsTableTableManager
    extends
        RootTableManager<
          _$LoreDatabase,
          $DocumentRelationshipsTable,
          DocumentRelationship,
          $$DocumentRelationshipsTableFilterComposer,
          $$DocumentRelationshipsTableOrderingComposer,
          $$DocumentRelationshipsTableAnnotationComposer,
          $$DocumentRelationshipsTableCreateCompanionBuilder,
          $$DocumentRelationshipsTableUpdateCompanionBuilder,
          (DocumentRelationship, $$DocumentRelationshipsTableReferences),
          DocumentRelationship,
          PrefetchHooks Function({
            bool sourceDocumentId,
            bool relatedDocumentId,
          })
        > {
  $$DocumentRelationshipsTableTableManager(
    _$LoreDatabase db,
    $DocumentRelationshipsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentRelationshipsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DocumentRelationshipsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DocumentRelationshipsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceDocumentId = const Value.absent(),
                Value<String> relatedDocumentId = const Value.absent(),
                Value<String> relationshipType = const Value.absent(),
                Value<double> score = const Value.absent(),
                Value<String> explanation = const Value.absent(),
                Value<String> evidenceJson = const Value.absent(),
                Value<String> calculatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentRelationshipsCompanion(
                id: id,
                sourceDocumentId: sourceDocumentId,
                relatedDocumentId: relatedDocumentId,
                relationshipType: relationshipType,
                score: score,
                explanation: explanation,
                evidenceJson: evidenceJson,
                calculatedAt: calculatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceDocumentId,
                required String relatedDocumentId,
                required String relationshipType,
                required double score,
                required String explanation,
                Value<String> evidenceJson = const Value.absent(),
                required String calculatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DocumentRelationshipsCompanion.insert(
                id: id,
                sourceDocumentId: sourceDocumentId,
                relatedDocumentId: relatedDocumentId,
                relationshipType: relationshipType,
                score: score,
                explanation: explanation,
                evidenceJson: evidenceJson,
                calculatedAt: calculatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DocumentRelationshipsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({sourceDocumentId = false, relatedDocumentId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (sourceDocumentId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sourceDocumentId,
                                    referencedTable:
                                        $$DocumentRelationshipsTableReferences
                                            ._sourceDocumentIdTable(db),
                                    referencedColumn:
                                        $$DocumentRelationshipsTableReferences
                                            ._sourceDocumentIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (relatedDocumentId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.relatedDocumentId,
                                    referencedTable:
                                        $$DocumentRelationshipsTableReferences
                                            ._relatedDocumentIdTable(db),
                                    referencedColumn:
                                        $$DocumentRelationshipsTableReferences
                                            ._relatedDocumentIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$DocumentRelationshipsTableProcessedTableManager =
    ProcessedTableManager<
      _$LoreDatabase,
      $DocumentRelationshipsTable,
      DocumentRelationship,
      $$DocumentRelationshipsTableFilterComposer,
      $$DocumentRelationshipsTableOrderingComposer,
      $$DocumentRelationshipsTableAnnotationComposer,
      $$DocumentRelationshipsTableCreateCompanionBuilder,
      $$DocumentRelationshipsTableUpdateCompanionBuilder,
      (DocumentRelationship, $$DocumentRelationshipsTableReferences),
      DocumentRelationship,
      PrefetchHooks Function({bool sourceDocumentId, bool relatedDocumentId})
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$LoreDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$LoreDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$LoreDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$LoreDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$LoreDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$LoreDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$LoreDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$LoreDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$SchemaMetaTableCreateCompanionBuilder =
    SchemaMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SchemaMetaTableUpdateCompanionBuilder =
    SchemaMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SchemaMetaTableFilterComposer
    extends Composer<_$LoreDatabase, $SchemaMetaTable> {
  $$SchemaMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SchemaMetaTableOrderingComposer
    extends Composer<_$LoreDatabase, $SchemaMetaTable> {
  $$SchemaMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SchemaMetaTableAnnotationComposer
    extends Composer<_$LoreDatabase, $SchemaMetaTable> {
  $$SchemaMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SchemaMetaTableTableManager
    extends
        RootTableManager<
          _$LoreDatabase,
          $SchemaMetaTable,
          SchemaMetaData,
          $$SchemaMetaTableFilterComposer,
          $$SchemaMetaTableOrderingComposer,
          $$SchemaMetaTableAnnotationComposer,
          $$SchemaMetaTableCreateCompanionBuilder,
          $$SchemaMetaTableUpdateCompanionBuilder,
          (
            SchemaMetaData,
            BaseReferences<_$LoreDatabase, $SchemaMetaTable, SchemaMetaData>,
          ),
          SchemaMetaData,
          PrefetchHooks Function()
        > {
  $$SchemaMetaTableTableManager(_$LoreDatabase db, $SchemaMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchemaMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchemaMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchemaMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SchemaMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SchemaMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SchemaMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$LoreDatabase,
      $SchemaMetaTable,
      SchemaMetaData,
      $$SchemaMetaTableFilterComposer,
      $$SchemaMetaTableOrderingComposer,
      $$SchemaMetaTableAnnotationComposer,
      $$SchemaMetaTableCreateCompanionBuilder,
      $$SchemaMetaTableUpdateCompanionBuilder,
      (
        SchemaMetaData,
        BaseReferences<_$LoreDatabase, $SchemaMetaTable, SchemaMetaData>,
      ),
      SchemaMetaData,
      PrefetchHooks Function()
    >;

class $LoreDatabaseManager {
  final _$LoreDatabase _db;
  $LoreDatabaseManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db, _db.documents);
  $$DocumentRelationshipsTableTableManager get documentRelationships =>
      $$DocumentRelationshipsTableTableManager(_db, _db.documentRelationships);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$SchemaMetaTableTableManager get schemaMeta =>
      $$SchemaMetaTableTableManager(_db, _db.schemaMeta);
}
