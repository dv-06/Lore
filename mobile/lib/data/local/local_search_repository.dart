import 'package:drift/drift.dart';

import 'local_database.dart';
import 'local_models.dart';

abstract interface class LocalSearchRepository {
  Future<List<LocalSearchResult>> search(String query, {int limit = 50});

  Future<int> indexedDocumentCount();

  Future<int> rebuildIndex();
}

class DriftLocalSearchRepository implements LocalSearchRepository {
  DriftLocalSearchRepository(this._database);

  static const maxQueryLength = 256;
  static const maxQueryTerms = 12;
  static const maxResults = 100;

  static final RegExp _termPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  final LoreDatabase _database;

  @override
  Future<List<LocalSearchResult>> search(String query, {int limit = 50}) async {
    if (limit < 1 || limit > maxResults) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Search limit must be between 1 and $maxResults.',
      );
    }

    final terms = _terms(query);
    if (terms.isEmpty) {
      return const <LocalSearchResult>[];
    }

    final match = terms
        .map((term) => '"${term.replaceAll('"', '""')}"*')
        .join(' AND ');

    final rows = await _database
        .customSelect(
          '''
          SELECT
            d.id AS id,
            d.original_filename AS original_filename,
            d.document_title AS document_title,
            d.category AS category,
            snippet(document_search, 1, '[', ']', '…', 24) AS snippet,
            bm25(document_search, 0.0, 2.5, 1.5, 0.8, 1.0, 1.2, 1.4, 2.5, 3.0) AS rank
          FROM document_search
          JOIN documents d ON d.rowid = document_search.rowid
          WHERE document_search MATCH ?
            AND d.is_deleted = 0
          ORDER BY rank ASC
          LIMIT ?
          ''',
          variables: [Variable<String>(match), Variable<int>(limit)],
        )
        .get();

    return rows
        .map(
          (row) => LocalSearchResult(
            documentId: row.read<String>('id'),
            filename: row.read<String>('original_filename'),
            title: row.read<String?>('document_title'),
            category: row.read<String?>('category'),
            snippet: row.read<String?>('snippet'),
            rank: row.read<double>('rank'),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<int> indexedDocumentCount() async {
    final row = await _database
        .customSelect('SELECT count(*) AS indexed_count FROM document_search')
        .getSingle();
    return row.read<int>('indexed_count');
  }

  @override
  Future<int> rebuildIndex() {
    return _database.transaction(() async {
      await _database.customStatement('DELETE FROM document_search');
      await _database.customStatement('''
        INSERT INTO document_search (
          rowid, document_id, extracted_text, original_filename,
          document_title, category, tags_text, document_type,
          issuer, reference_number
        )
        SELECT
          rowid, id, extracted_text, original_filename,
          document_title, category, tags_text, document_type,
          issuer, reference_number
        FROM documents
        WHERE is_deleted = 0
      ''');
      return indexedDocumentCount();
    });
  }

  List<String> _terms(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }
    if (trimmed.length > maxQueryLength) {
      throw ArgumentError.value(
        query,
        'query',
        'Search queries are limited to $maxQueryLength characters.',
      );
    }

    final terms = _termPattern
        .allMatches(trimmed)
        .map((match) => match.group(0)!)
        .toList(growable: false);
    if (terms.length > maxQueryTerms) {
      throw ArgumentError.value(
        query,
        'query',
        'Search queries are limited to $maxQueryTerms terms.',
      );
    }
    return terms;
  }
}
