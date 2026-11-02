/// Data models matching the LORE backend Pydantic schemas exactly.
library;

class DocumentResponse {
  final String id;
  final String originalFilename;
  final String? mediaType;
  final int sizeBytes;
  final String? sha256;
  final String extractionStatus;
  final String processingStatus;
  final String? processingError;
  final DateTime uploadedAt;
  final String? category;
  final double? classificationConfidence;
  final List<String> classificationReasons;
  final String? classificationMethod;
  final String? documentTitle;
  final DateTime? documentDate;
  final String? documentType;
  final String? issuer;
  final String? referenceNumber;
  final List<String> tags;

  const DocumentResponse({
    required this.id,
    required this.originalFilename,
    this.mediaType,
    required this.sizeBytes,
    this.sha256,
    required this.extractionStatus,
    required this.processingStatus,
    this.processingError,
    required this.uploadedAt,
    this.category,
    this.classificationConfidence,
    this.classificationReasons = const [],
    this.classificationMethod,
    this.documentTitle,
    this.documentDate,
    this.documentType,
    this.issuer,
    this.referenceNumber,
    this.tags = const [],
  });

  factory DocumentResponse.fromJson(Map<String, dynamic> json) {
    return DocumentResponse(
      id: json['id'] as String,
      originalFilename: json['original_filename'] as String,
      mediaType: json['media_type'] as String?,
      sizeBytes: json['size_bytes'] as int,
      sha256: json['sha256'] as String?,
      extractionStatus: json['extraction_status'] as String,
      processingStatus: json['processing_status'] as String,
      processingError: json['processing_error'] as String?,
      uploadedAt: DateTime.parse(json['uploaded_at'] as String),
      category: json['category'] as String?,
      classificationConfidence: (json['classification_confidence'] as num?)
          ?.toDouble(),
      classificationReasons:
          (json['classification_reasons'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      classificationMethod: json['classification_method'] as String?,
      documentTitle: json['document_title'] as String?,
      documentDate: json['document_date'] != null
          ? DateTime.tryParse(json['document_date'] as String)
          : null,
      documentType: json['document_type'] as String?,
      issuer: json['issuer'] as String?,
      referenceNumber: json['reference_number'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
    );
  }

  /// Display name: title or filename.
  String get displayName => documentTitle ?? originalFilename;

  /// Formatted file size.
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get categoryLabel => category ?? 'Uncategorized';

  bool get hasProcessingFailure =>
      extractionStatus == 'failed' || processingStatus == 'failed';

  bool get hasExtractedText => extractionStatus == 'extracted';
}

class DocumentListResponse {
  final List<DocumentResponse> items;
  final int limit;
  final int offset;

  const DocumentListResponse({
    required this.items,
    required this.limit,
    required this.offset,
  });

  factory DocumentListResponse.fromJson(Map<String, dynamic> json) {
    return DocumentListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => DocumentResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
      limit: json['limit'] as int,
      offset: json['offset'] as int,
    );
  }
}

class CategoryCount {
  final String category;
  final int documentCount;

  const CategoryCount({required this.category, required this.documentCount});

  factory CategoryCount.fromJson(Map<String, dynamic> json) {
    return CategoryCount(
      category: json['category'] as String,
      documentCount: json['document_count'] as int,
    );
  }
}

class CategoriesResponse {
  final List<CategoryCount> items;

  const CategoriesResponse({required this.items});

  factory CategoriesResponse.fromJson(Map<String, dynamic> json) {
    return CategoriesResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => CategoryCount.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SearchResult {
  final String documentId;
  final String filename;
  final String? title;
  final String? category;
  final String snippet;
  final List<String> matchingFields;
  final double score;
  final String? documentType;

  const SearchResult({
    required this.documentId,
    required this.filename,
    this.title,
    this.category,
    required this.snippet,
    this.matchingFields = const [],
    required this.score,
    this.documentType,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      documentId: json['document_id'] as String,
      filename: json['filename'] as String,
      title: json['title'] as String?,
      category: json['category'] as String?,
      snippet: json['snippet'] as String,
      matchingFields:
          (json['matching_fields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      score: (json['score'] as num).toDouble(),
      documentType: json['document_type'] as String?,
    );
  }

  String get displayName => title ?? filename;
}

class SearchResponse {
  final String query;
  final List<SearchResult> items;
  final int limit;
  final int offset;

  const SearchResponse({
    required this.query,
    required this.items,
    required this.limit,
    required this.offset,
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    return SearchResponse(
      query: json['query'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      limit: json['limit'] as int,
      offset: json['offset'] as int,
    );
  }
}

class AskEvidence {
  final String documentId;
  final String filename;
  final String? title;
  final String? location;
  final String snippet;
  final double score;
  final String reason;

  const AskEvidence({
    required this.documentId,
    required this.filename,
    this.title,
    this.location,
    required this.snippet,
    required this.score,
    required this.reason,
  });

  factory AskEvidence.fromJson(Map<String, dynamic> json) {
    return AskEvidence(
      documentId: json['document_id'] as String,
      filename: json['filename'] as String,
      title: json['title'] as String?,
      location: json['location'] as String?,
      snippet: json['snippet'] as String,
      score: (json['score'] as num).toDouble(),
      reason: json['reason'] as String,
    );
  }

  String get displayName => title ?? filename;

  Map<String, dynamic> toJson() => {
    'document_id': documentId,
    'filename': filename,
    'title': title,
    'location': location,
    'snippet': snippet,
    'score': score,
    'reason': reason,
  };
}

class AskResponse {
  final String question;
  final String answer;
  final String provider;
  final bool sufficientEvidence;
  final List<AskEvidence> evidence;
  final List<String> warnings;

  const AskResponse({
    required this.question,
    required this.answer,
    required this.provider,
    required this.sufficientEvidence,
    this.evidence = const [],
    this.warnings = const [],
  });

  factory AskResponse.fromJson(Map<String, dynamic> json) {
    return AskResponse(
      question: json['question'] as String,
      answer: json['answer'] as String,
      provider: json['provider'] as String,
      sufficientEvidence: json['sufficient_evidence'] as bool,
      evidence:
          (json['evidence'] as List<dynamic>?)
              ?.map((e) => AskEvidence.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      warnings:
          (json['warnings'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }
}

class AskProviderStatus {
  final bool available;
  final String? reason;

  const AskProviderStatus({required this.available, this.reason});

  factory AskProviderStatus.fromJson(Map<String, dynamic> json) {
    return AskProviderStatus(
      available: json['available'] as bool,
      reason: json['reason'] as String?,
    );
  }
}

class AskStatusResponse {
  final Map<String, AskProviderStatus> providers;
  final String selectedProvider;
  final bool available;
  final String mode;
  final bool localModelReady;
  final bool externalProviderConfigured;

  const AskStatusResponse({
    required this.providers,
    required this.selectedProvider,
    required this.available,
    this.mode = 'private',
    this.localModelReady = false,
    this.externalProviderConfigured = false,
  });

  factory AskStatusResponse.fromJson(Map<String, dynamic> json) {
    final providersMap = <String, AskProviderStatus>{};
    final rawProviders = json['providers'] as Map<String, dynamic>;
    for (final entry in rawProviders.entries) {
      providersMap[entry.key] = AskProviderStatus.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return AskStatusResponse(
      providers: providersMap,
      selectedProvider: json['selected_provider'] as String,
      available: json['available'] as bool,
      mode: json['mode'] as String? ?? 'private',
      localModelReady: json['local_model_ready'] as bool? ?? false,
      externalProviderConfigured:
          json['external_provider_configured'] as bool? ?? false,
    );
  }
}

class AskModeResponse {
  final String mode;
  final String selectedProvider;
  final bool available;

  const AskModeResponse({
    required this.mode,
    required this.selectedProvider,
    required this.available,
  });

  factory AskModeResponse.fromJson(Map<String, dynamic> json) {
    return AskModeResponse(
      mode: json['mode'] as String? ?? 'private',
      selectedProvider: json['selected_provider'] as String? ?? 'extractive',
      available: json['available'] as bool? ?? false,
    );
  }
}

class AssistedPrepareResponse {
  final String requestId;
  final String provider;
  final String question;
  final List<AskEvidence> proposedExcerpts;
  final String payloadHash;
  final String expiresAt;
  final String status;

  const AssistedPrepareResponse({
    required this.requestId,
    required this.provider,
    required this.question,
    this.proposedExcerpts = const [],
    required this.payloadHash,
    required this.expiresAt,
    this.status = 'prepared',
  });

  factory AssistedPrepareResponse.fromJson(Map<String, dynamic> json) {
    return AssistedPrepareResponse(
      requestId: json['request_id'] as String,
      provider: json['provider'] as String? ?? 'external',
      question: json['question'] as String,
      proposedExcerpts:
          (json['proposed_excerpts'] as List<dynamic>?)
              ?.map((e) => AskEvidence.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      payloadHash: json['payload_hash'] as String? ?? '',
      expiresAt: json['expires_at'] as String? ?? '',
      status: json['status'] as String? ?? 'prepared',
    );
  }
}

class AssistedConfirmationResult {
  final bool approved;
  final String requestId;
  final String? provider;
  final String? answer;
  final String status;

  const AssistedConfirmationResult({
    required this.approved,
    required this.requestId,
    this.provider,
    this.answer,
    required this.status,
  });

  factory AssistedConfirmationResult.fromJson(Map<String, dynamic> json) {
    return AssistedConfirmationResult(
      approved: json['approved'] as bool? ?? false,
      requestId: json['request_id'] as String? ?? '',
      provider: json['provider'] as String?,
      answer: json['answer'] as String?,
      status: json['status'] as String? ?? 'unknown',
    );
  }
}

class SearchRebuildResponse {
  final int indexedDocuments;

  const SearchRebuildResponse({required this.indexedDocuments});

  factory SearchRebuildResponse.fromJson(Map<String, dynamic> json) {
    return SearchRebuildResponse(
      indexedDocuments: (json['indexed_documents'] as num?)?.toInt() ?? 0,
    );
  }
}

class RelationshipRebuildResponse {
  final int processedDocuments;
  final int relationshipsCreated;

  const RelationshipRebuildResponse({
    required this.processedDocuments,
    required this.relationshipsCreated,
  });

  factory RelationshipRebuildResponse.fromJson(Map<String, dynamic> json) {
    return RelationshipRebuildResponse(
      processedDocuments: (json['processed_documents'] as num?)?.toInt() ?? 0,
      relationshipsCreated:
          (json['relationships_created'] as num?)?.toInt() ?? 0,
    );
  }
}

class RelatedDocument {
  final String id;
  final String filename;
  final String? title;
  final String? category;
  final String? documentType;

  const RelatedDocument({
    required this.id,
    required this.filename,
    this.title,
    this.category,
    this.documentType,
  });

  factory RelatedDocument.fromJson(Map<String, dynamic> json) {
    return RelatedDocument(
      id: json['id'] as String,
      filename: json['filename'] as String,
      title: json['title'] as String?,
      category: json['category'] as String?,
      documentType: json['document_type'] as String?,
    );
  }

  String get displayName => title ?? filename;
}

class RelationshipSuggestion {
  final String id;
  final String relationshipType;
  final double score;
  final String explanation;
  final List<String> evidence;
  final DateTime calculatedAt;
  final RelatedDocument relatedDocument;

  const RelationshipSuggestion({
    required this.id,
    required this.relationshipType,
    required this.score,
    required this.explanation,
    this.evidence = const [],
    required this.calculatedAt,
    required this.relatedDocument,
  });

  factory RelationshipSuggestion.fromJson(Map<String, dynamic> json) {
    return RelationshipSuggestion(
      id: json['id'] as String,
      relationshipType: json['relationship_type'] as String,
      score: (json['score'] as num).toDouble(),
      explanation: json['explanation'] as String,
      evidence:
          (json['evidence'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      calculatedAt: DateTime.parse(json['calculated_at'] as String),
      relatedDocument: RelatedDocument.fromJson(
        json['related_document'] as Map<String, dynamic>,
      ),
    );
  }
}

class RelatedDocumentsResponse {
  final String documentId;
  final List<RelationshipSuggestion> items;

  const RelatedDocumentsResponse({
    required this.documentId,
    required this.items,
  });

  factory RelatedDocumentsResponse.fromJson(Map<String, dynamic> json) {
    return RelatedDocumentsResponse(
      documentId: json['document_id'] as String,
      items: (json['items'] as List<dynamic>)
          .map(
            (e) => RelationshipSuggestion.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class SystemStatusResponse {
  final String status;
  final String database;

  const SystemStatusResponse({required this.status, required this.database});

  factory SystemStatusResponse.fromJson(Map<String, dynamic> json) {
    return SystemStatusResponse(
      status: json['status'] as String,
      database: json['database'] as String,
    );
  }

  bool get isHealthy => status == 'ok' && database == 'ok';
}

class AuthStatusResponse {
  final bool paired;
  final bool pairingRequired;
  final int activeSessions;
  final DateTime? pairingExpiresAt;

  const AuthStatusResponse({
    required this.paired,
    required this.pairingRequired,
    required this.activeSessions,
    this.pairingExpiresAt,
  });

  factory AuthStatusResponse.fromJson(Map<String, dynamic> json) {
    return AuthStatusResponse(
      paired: json['paired'] as bool,
      pairingRequired: json['pairing_required'] as bool,
      activeSessions: json['active_sessions'] as int,
      pairingExpiresAt: json['pairing_expires_at'] != null
          ? DateTime.tryParse(json['pairing_expires_at'] as String)
          : null,
    );
  }
}

class AuthPairResponse {
  final String token;
  final DateTime createdAt;
  final DateTime expiresAt;

  const AuthPairResponse({
    required this.token,
    required this.createdAt,
    required this.expiresAt,
  });

  factory AuthPairResponse.fromJson(Map<String, dynamic> json) {
    return AuthPairResponse(
      token: json['token'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class AuthSessionResponse {
  final bool authenticated;
  final DateTime createdAt;
  final DateTime expiresAt;

  const AuthSessionResponse({
    required this.authenticated,
    required this.createdAt,
    required this.expiresAt,
  });

  factory AuthSessionResponse.fromJson(Map<String, dynamic> json) {
    return AuthSessionResponse(
      authenticated: json['authenticated'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class DownloadedDocument {
  final List<int> bytes;
  final String? mediaType;

  const DownloadedDocument({required this.bytes, this.mediaType});
}
