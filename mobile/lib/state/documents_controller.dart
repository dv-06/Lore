import 'package:flutter/foundation.dart';

import '../core/error_text.dart';
import '../data/api_client.dart';
import '../data/models.dart';

class UploadCandidate {
  final String filename;
  final List<int> bytes;

  const UploadCandidate({required this.filename, required this.bytes});
}

class UploadFailure {
  final String filename;
  final String message;

  const UploadFailure({required this.filename, required this.message});
}

class UploadOutcome {
  final List<DocumentResponse> uploaded;
  final List<UploadFailure> failures;

  const UploadOutcome({required this.uploaded, required this.failures});

  bool get hasFailures => failures.isNotEmpty;
  bool get hasUploads => uploaded.isNotEmpty;
}

class DocumentsController extends ChangeNotifier {
  DocumentsController({required this.client});

  final LoreApiClient client;

  List<DocumentResponse> _documents = [];
  List<CategoryCount> _categories = [];
  String? _selectedCategory;
  bool _loading = false;
  bool _hasLoaded = false;
  String? _error;

  String _searchQuery = '';
  List<SearchResult> _searchResults = [];
  bool _searching = false;
  String? _searchError;
  int _searchSequence = 0;

  bool _uploading = false;
  int _uploadCompleted = 0;
  int _uploadTotal = 0;
  String? _uploadFilename;

  List<DocumentResponse> get documents => List.unmodifiable(_documents);
  List<CategoryCount> get categories => List.unmodifiable(_categories);
  String? get selectedCategory => _selectedCategory;
  bool get isLoading => _loading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  String get searchQuery => _searchQuery;
  List<SearchResult> get searchResults => List.unmodifiable(_searchResults);
  bool get isSearching => _searching;
  String? get searchError => _searchError;
  bool get hasActiveSearch => _searchQuery.isNotEmpty;

  bool get isUploading => _uploading;
  int get uploadCompleted => _uploadCompleted;
  int get uploadTotal => _uploadTotal;
  String? get uploadFilename => _uploadFilename;

  int get totalDocumentCount {
    if (_categories.isNotEmpty) {
      return _categories.fold<int>(0, (sum, item) => sum + item.documentCount);
    }
    return _documents.length;
  }

  int get totalSizeBytes =>
      _documents.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  bool get hasAllLoadedDocuments =>
      _categories.isEmpty || _documents.length >= totalDocumentCount;

  List<DocumentResponse> get documentsForCategory {
    final category = _selectedCategory;
    if (category == null) return documents;
    return _documents
        .where((document) {
          final value = document.category;
          if (category == 'Uncategorized') {
            return value == null || value == 'Uncategorized';
          }
          return value == category;
        })
        .toList(growable: false);
  }

  List<DocumentResponse> get recentDocuments =>
      _documents.take(3).toList(growable: false);

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_hasLoaded && !force) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object>([
        _fetchAllDocuments(),
        client.listCategories(),
      ]);
      _documents = results[0] as List<DocumentResponse>;
      _categories = (results[1] as CategoriesResponse).items;
      _hasLoaded = true;
    } catch (error) {
      _error = describeError(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await load(force: true);
    if (_searchQuery.isNotEmpty) {
      await search(_searchQuery);
    }
  }

  Future<List<DocumentResponse>> _fetchAllDocuments() async {
    const pageSize = 100;
    const maximumDocuments = 1000;
    final documents = <DocumentResponse>[];
    var offset = 0;
    while (offset < maximumDocuments) {
      final page = await client.listDocuments(limit: pageSize, offset: offset);
      documents.addAll(page.items);
      if (page.items.length < pageSize) break;
      offset += pageSize;
    }
    return documents;
  }

  void selectCategory(String? category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    notifyListeners();
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    _searchQuery = trimmed;
    final requestId = ++_searchSequence;
    if (trimmed.isEmpty) {
      _searchResults = [];
      _searchError = null;
      _searching = false;
      notifyListeners();
      return;
    }
    _searching = true;
    _searchError = null;
    notifyListeners();
    try {
      final response = await client.search(
        trimmed,
        limit: 50,
        category: _selectedCategory,
      );
      if (requestId == _searchSequence) {
        _searchResults = response.items;
      }
    } catch (error) {
      if (requestId == _searchSequence) {
        _searchError = describeError(error);
        _searchResults = [];
      }
    } finally {
      if (requestId == _searchSequence) {
        _searching = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    _searchSequence++;
    _searchQuery = '';
    _searchResults = [];
    _searchError = null;
    _searching = false;
    notifyListeners();
  }

  Future<UploadOutcome> upload(List<UploadCandidate> files) async {
    if (files.isEmpty) {
      return const UploadOutcome(uploaded: [], failures: []);
    }
    _uploading = true;
    _uploadCompleted = 0;
    _uploadTotal = files.length;
    _uploadFilename = null;
    notifyListeners();

    final uploaded = <DocumentResponse>[];
    final failures = <UploadFailure>[];
    for (final file in files) {
      _uploadFilename = file.filename;
      notifyListeners();
      try {
        uploaded.add(
          await client.uploadDocument(
            filename: file.filename,
            bytes: file.bytes,
          ),
        );
      } catch (error) {
        failures.add(
          UploadFailure(filename: file.filename, message: describeError(error)),
        );
      }
      _uploadCompleted++;
      notifyListeners();
    }

    _uploading = false;
    _uploadFilename = null;
    if (uploaded.isNotEmpty) {
      await load(force: true);
    }
    notifyListeners();
    return UploadOutcome(uploaded: uploaded, failures: failures);
  }

  Future<void> deleteDocument(String id) async {
    await client.deleteDocument(id);
    _documents.removeWhere((document) => document.id == id);
    _searchResults.removeWhere((result) => result.documentId == id);
    notifyListeners();
    await load(force: true);
  }

  Future<DocumentResponse> getDocument(String id) async {
    return client.getDocument(id);
  }

  Future<DocumentResponse> updateOrganization(
    String id, {
    String? category,
    List<String>? tags,
  }) async {
    final updated = await client.updateOrganization(
      id,
      category: category,
      tags: tags,
    );
    _replaceDocument(updated);
    await _reloadCategories();
    return updated;
  }

  Future<DocumentResponse> retryExtraction(String id) async {
    final updated = await client.retryExtraction(id);
    _replaceDocument(updated);
    return updated;
  }

  Future<DocumentResponse> classifyDocument(String id) async {
    final updated = await client.classifyDocument(id);
    _replaceDocument(updated);
    await _reloadCategories();
    await load(force: true);
    return updated;
  }

  Future<RelatedDocumentsResponse> getRelatedDocuments(
    String id, {
    int limit = 20,
  }) {
    return client.getRelatedDocuments(id, limit: limit);
  }

  Future<RelatedDocumentsResponse> recalculateRelatedDocuments(String id) {
    return client.recalculateRelatedDocuments(id);
  }

  Future<SearchRebuildResponse> rebuildSearchIndex() {
    return client.rebuildSearchIndex();
  }

  Future<RelationshipRebuildResponse> rebuildRelationships() {
    return client.rebuildRelationships();
  }

  void _replaceDocument(DocumentResponse updated) {
    final index = _documents.indexWhere(
      (document) => document.id == updated.id,
    );
    if (index >= 0) {
      _documents[index] = updated;
      notifyListeners();
    }
  }

  Future<void> _reloadCategories() async {
    try {
      _categories = (await client.listCategories()).items;
      notifyListeners();
    } catch (_) {
      // Category counts are non-critical; the next refresh will retry.
    }
  }

  /// Drops every cached document and search result on lock or sign-out.
  void reset() {
    _documents = [];
    _categories = [];
    _selectedCategory = null;
    _loading = false;
    _hasLoaded = false;
    _error = null;
    _searchSequence++;
    _searchQuery = '';
    _searchResults = [];
    _searching = false;
    _searchError = null;
    _uploading = false;
    _uploadCompleted = 0;
    _uploadTotal = 0;
    _uploadFilename = null;
    notifyListeners();
  }
}
