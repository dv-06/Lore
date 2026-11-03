import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/local/processing/document_classifier.dart';

void main() {
  final fixtures = (jsonDecode(
    File(
      'test/local/fixtures/classifier_parity.json',
    ).readAsStringSync(),
  ) as List<dynamic>)
      .cast<Map<String, dynamic>>();

  test('Dart rules-v1 matches every Python parity fixture', () {
    const classifier = DocumentClassifier();
    expect(fixtures, isNotEmpty);

    for (final fixture in fixtures) {
      final expected = fixture['expected'] as Map<String, dynamic>;
      final result = classifier.classify(
        filename: fixture['filename'] as String,
        extractedText: fixture['text'] as String,
        existingTags: (fixture['existing_tags'] as List<dynamic>)
            .cast<String>(),
      );

      final name = fixture['name'] as String;
      expect(result.category, expected['category'], reason: name);
      expect(
        result.confidence,
        closeTo(expected['confidence'] as num, 1e-12),
        reason: name,
      );
      expect(result.reasons, expected['reasons'], reason: name);
      expect(result.method, expected['method'], reason: name);
      expect(
        result.documentTitle,
        expected['document_title'],
        reason: name,
      );
      expect(result.documentType, expected['document_type'], reason: name);
      expect(
        result.documentDate == null ? null : dateOnlyIso8601(result.documentDate!),
        expected['document_date'],
        reason: name,
      );
      expect(result.issuer, expected['issuer'], reason: name);
      expect(
        result.referenceNumber,
        expected['reference_number'],
        reason: name,
      );
      expect(result.tags, expected['tags'], reason: name);
    }
  });

  test('all 11 categories are represented in the fixtures', () {
    final categories = fixtures
        .map((fixture) => (fixture['expected'] as Map)['category'])
        .toSet();
    expect(categories, containsAll(classifierCategories));
  });

  test('insufficient evidence stays Uncategorized', () {
    const classifier = DocumentClassifier();
    final result = classifier.classify(
      filename: 'scratch.txt',
      extractedText: 'Nothing in this note resembles a document type.',
    );
    expect(result.category, 'Uncategorized');
    expect(result.confidence, 0);
    expect(result.reasons, ['No category-specific indicators were found']);
  });
}
