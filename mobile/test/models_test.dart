import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/models.dart';

Map<String, dynamic> _documentJson({
  Object? title = 'Warranty policy',
  int sizeBytes = 2048,
  String extractionStatus = 'extracted',
  String processingStatus = 'completed',
  String? category = 'Finance',
}) {
  return {
    'id': 'doc-1',
    'original_filename': 'warranty.pdf',
    'media_type': 'application/pdf',
    'size_bytes': sizeBytes,
    'sha256': 'a' * 64,
    'extraction_status': extractionStatus,
    'processing_status': processingStatus,
    'processing_error': null,
    'uploaded_at': '2026-10-20T10:00:00Z',
    'category': category,
    'classification_confidence': 0.82,
    'classification_reasons': ['filename contains invoice'],
    'classification_method': 'keywords',
    'document_title': title,
    'document_date': '2026-01-01',
    'document_type': 'Warranty',
    'issuer': 'Acme',
    'reference_number': 'W-123',
    'tags': ['appliance'],
  };
}

Map<String, dynamic> _evidenceJson() {
  return {
    'document_id': 'doc-1',
    'filename': 'warranty.pdf',
    'title': 'Warranty policy',
    'location': 'Page 1',
    'snippet': 'The warranty ends on 1 March 2027.',
    'score': 0.91,
    'reason': 'Direct match for warranty period.',
  };
}

void main() {
  group('DocumentResponse', () {
    test('parses the backend document shape', () {
      final document = DocumentResponse.fromJson(_documentJson());

      expect(document.id, 'doc-1');
      expect(document.originalFilename, 'warranty.pdf');
      expect(document.mediaType, 'application/pdf');
      expect(document.sizeBytes, 2048);
      expect(document.category, 'Finance');
      expect(document.classificationConfidence, 0.82);
      expect(document.classificationReasons, ['filename contains invoice']);
      expect(document.documentTitle, 'Warranty policy');
      expect(document.documentDate, DateTime(2026, 1, 1));
      expect(document.tags, ['appliance']);
      expect(document.uploadedAt, DateTime.utc(2026, 10, 20, 10));
    });

    test('falls back to the filename when no title was extracted', () {
      final document = DocumentResponse.fromJson(_documentJson(title: null));

      expect(document.displayName, 'warranty.pdf');
    });

    test('formats sizes and reports missing categories', () {
      expect(
        DocumentResponse.fromJson(
          _documentJson(sizeBytes: 512, category: null),
        ).formattedSize,
        '512 B',
      );
      expect(
        DocumentResponse.fromJson(
          _documentJson(sizeBytes: 2048, category: null),
        ).formattedSize,
        '2.0 KB',
      );
      expect(
        DocumentResponse.fromJson(
          _documentJson(sizeBytes: 3 * 1024 * 1024, category: null),
        ).formattedSize,
        '3.0 MB',
      );
      expect(
        DocumentResponse.fromJson(_documentJson(category: null)).categoryLabel,
        'Uncategorized',
      );
    });

    test('reports processing failures and extracted text', () {
      final failed = DocumentResponse.fromJson(
        _documentJson(extractionStatus: 'failed'),
      );
      final processed = DocumentResponse.fromJson(_documentJson());

      expect(failed.hasProcessingFailure, isTrue);
      expect(processed.hasProcessingFailure, isFalse);
      expect(processed.hasExtractedText, isTrue);
    });
  });

  group('Ask payloads', () {
    test('parses an extractive answer with evidence and warnings', () {
      final response = AskResponse.fromJson({
        'question': 'When does the warranty expire?',
        'answer': 'The warranty ends on 1 March 2027.',
        'provider': 'extractive',
        'sufficient_evidence': true,
        'evidence': [_evidenceJson()],
        'warnings': ['Answer selected from indexed text.'],
      });

      expect(response.provider, 'extractive');
      expect(response.sufficientEvidence, isTrue);
      expect(response.evidence.single.documentId, 'doc-1');
      expect(response.evidence.single.location, 'Page 1');
      expect(response.evidence.single.score, 0.91);
      expect(response.warnings.single, contains('indexed text'));
    });

    test('evidence round-trips through the confirmation payload', () {
      final evidence = AskEvidence.fromJson(_evidenceJson());
      final restored = AskEvidence.fromJson(evidence.toJson());

      expect(restored.documentId, evidence.documentId);
      expect(restored.displayName, 'Warranty policy');
      expect(restored.snippet, evidence.snippet);
      expect(restored.reason, evidence.reason);
    });

    test('parses a prepared assisted request without an answer', () {
      final prepared = AssistedPrepareResponse.fromJson({
        'request_id': 'req-1',
        'provider': 'external',
        'question': 'What does the policy cover?',
        'proposed_excerpts': [_evidenceJson()],
        'payload_hash': 'hash-1',
        'expires_at': '2026-10-27T12:00:00Z',
        'status': 'prepared',
      });

      expect(prepared.requestId, 'req-1');
      expect(prepared.provider, 'external');
      expect(prepared.proposedExcerpts, hasLength(1));
      expect(prepared.proposedExcerpts.single.location, 'Page 1');
      expect(prepared.status, 'prepared');
    });

    test('parses confirmation results', () {
      final result = AssistedConfirmationResult.fromJson({
        'approved': true,
        'request_id': 'req-1',
        'provider': 'external',
        'answer': 'External answer.',
        'status': 'confirmed',
      });

      expect(result.approved, isTrue);
      expect(result.provider, 'external');
      expect(result.answer, 'External answer.');
    });
  });

  group('AskStatusResponse', () {
    test('parses provider availability and privacy flags', () {
      final status = AskStatusResponse.fromJson({
        'providers': {
          'extractive': {'available': true, 'reason': null},
          'local-llm': {'available': false, 'reason': 'Ollama not running'},
          'external': {'available': false, 'reason': 'Not configured'},
        },
        'selected_provider': 'extractive',
        'available': true,
        'mode': 'private',
        'local_model_ready': false,
        'external_provider_configured': false,
      });

      expect(status.mode, 'private');
      expect(status.selectedProvider, 'extractive');
      expect(status.available, isTrue);
      expect(status.providers['extractive']?.available, isTrue);
      expect(status.providers['local-llm']?.reason, 'Ollama not running');
      expect(status.externalProviderConfigured, isFalse);
    });

    test('defaults to private mode when optional fields are missing', () {
      final status = AskStatusResponse.fromJson({
        'providers': {
          'extractive': {'available': true},
        },
        'selected_provider': 'extractive',
        'available': true,
      });

      expect(status.mode, 'private');
      expect(status.localModelReady, isFalse);
      expect(status.externalProviderConfigured, isFalse);
    });
  });

  group('Related documents', () {
    test('parses relationship suggestions and their evidence', () {
      final response = RelatedDocumentsResponse.fromJson({
        'document_id': 'doc-1',
        'items': [
          {
            'id': 'rel-1',
            'relationship_type': 'same_category',
            'score': 0.7,
            'explanation': 'Both are appliance documents.',
            'evidence': ['category: Appliances'],
            'calculated_at': '2026-10-20T10:00:00Z',
            'related_document': {
              'id': 'doc-2',
              'filename': 'fridge.pdf',
              'title': null,
              'category': 'Appliances',
              'document_type': 'Manual',
            },
          },
        ],
      });

      final suggestion = response.items.single;
      expect(response.documentId, 'doc-1');
      expect(suggestion.relationshipType, 'same_category');
      expect(suggestion.evidence.single, 'category: Appliances');
      expect(suggestion.relatedDocument.displayName, 'fridge.pdf');
      expect(suggestion.relatedDocument.id, 'doc-2');
    });
  });

  group('SystemStatusResponse', () {
    test('reports healthy only when API and database are ok', () {
      final healthy = SystemStatusResponse.fromJson({
        'status': 'ok',
        'database': 'ok',
      });
      final degraded = SystemStatusResponse.fromJson({
        'status': 'ok',
        'database': 'error',
      });

      expect(healthy.isHealthy, isTrue);
      expect(degraded.isHealthy, isFalse);
    });
  });
}
