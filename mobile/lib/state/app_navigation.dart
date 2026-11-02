import 'package:flutter/foundation.dart';

enum DocumentsView { search, connections }

class DocumentsRequest {
  final int id;
  final DocumentsView view;
  final String? query;

  const DocumentsRequest({required this.id, required this.view, this.query});
}

class AppNavigation extends ChangeNotifier {
  int _index = 0;
  int _requestSequence = 0;
  DocumentsRequest? _documentsRequest;

  int get index => _index;
  DocumentsRequest? get documentsRequest => _documentsRequest;

  void goToTab(int index) {
    if (index == _index) return;
    _index = index;
    notifyListeners();
  }

  void openDocuments({
    DocumentsView view = DocumentsView.search,
    String? query,
  }) {
    _index = 1;
    _documentsRequest = DocumentsRequest(
      id: ++_requestSequence,
      view: view,
      query: query,
    );
    notifyListeners();
  }

  void openAsk() {
    _index = 2;
    notifyListeners();
  }

  void openSettings() {
    _index = 3;
    notifyListeners();
  }

  void reset() {
    _index = 0;
    _documentsRequest = null;
    notifyListeners();
  }
}
