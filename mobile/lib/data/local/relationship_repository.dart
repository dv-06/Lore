import 'package:drift/drift.dart';

import 'local_database.dart';
import 'local_models.dart';

abstract interface class RelationshipRepository {
  Future<void> upsert(LocalRelationship relationship);

  Future<List<LocalRelationship>> listForDocument(String documentId);

  Future<int> count();
}

class DriftRelationshipRepository implements RelationshipRepository {
  DriftRelationshipRepository(this._database);

  final LoreDatabase _database;

  @override
  Future<void> upsert(LocalRelationship relationship) {
    return _database
        .into(_database.documentRelationships)
        .insertOnConflictUpdate(
          DocumentRelationshipsCompanion.insert(
            id: relationship.id,
            sourceDocumentId: relationship.sourceDocumentId,
            relatedDocumentId: relationship.relatedDocumentId,
            relationshipType: relationship.relationshipType,
            score: relationship.score,
            explanation: relationship.explanation,
            evidenceJson: Value(relationship.evidenceJson),
            calculatedAt: relationship.calculatedAt.toUtc().toIso8601String(),
          ),
        );
  }

  @override
  Future<List<LocalRelationship>> listForDocument(String documentId) async {
    final rows =
        await (_database.select(_database.documentRelationships)
              ..where(
                (table) =>
                    table.sourceDocumentId.equals(documentId) |
                    table.relatedDocumentId.equals(documentId),
              )
              ..orderBy([
                (table) => OrderingTerm.desc(table.score),
                (table) => OrderingTerm.asc(table.id),
              ]))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<int> count() async {
    final count = _database.documentRelationships.id.count();
    final query = _database.selectOnly(_database.documentRelationships)
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  LocalRelationship _toDomain(DocumentRelationship row) {
    return LocalRelationship(
      id: row.id,
      sourceDocumentId: row.sourceDocumentId,
      relatedDocumentId: row.relatedDocumentId,
      relationshipType: row.relationshipType,
      score: row.score,
      explanation: row.explanation,
      evidenceJson: row.evidenceJson,
      calculatedAt: DateTime.parse(row.calculatedAt).toUtc(),
    );
  }
}
