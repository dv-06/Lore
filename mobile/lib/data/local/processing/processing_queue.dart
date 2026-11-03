import 'dart:async';

import '../local_models.dart';
import 'document_processor.dart';
import 'extraction_types.dart';

/// Small in-process queue. It serializes work to bound memory use and
/// coalesces repeated requests for the same document.
class ProcessingQueue {
  ProcessingQueue({required this.processor});

  final DocumentProcessor processor;

  final List<String> _queue = <String>[];
  final Map<String, Completer<ProcessingOutcome>> _completers =
      <String, Completer<ProcessingOutcome>>{};
  final Map<String, CancellationSignal> _active =
      <String, CancellationSignal>{};
  bool _draining = false;

  bool isQueued(String documentId) =>
      _queue.contains(documentId) || _active.containsKey(documentId);

  Future<ProcessingOutcome> enqueue(String documentId) {
    final existing = _completers[documentId];
    if (existing != null) {
      return existing.future;
    }
    final completer = Completer<ProcessingOutcome>();
    _completers[documentId] = completer;
    _queue.add(documentId);
    unawaited(_drain());
    return completer.future;
  }

  Future<List<ProcessingOutcome>> enqueuePending({int? limit}) async {
    final ids = await processor.pendingDocumentIds(limit: limit);
    return Future.wait(ids.map(enqueue));
  }

  void cancel(String documentId) {
    final active = _active[documentId];
    if (active != null) {
      active.cancel();
      return;
    }
    if (_queue.remove(documentId)) {
      final completer = _completers.remove(documentId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(
          ProcessingOutcome(
            documentId: documentId,
            processingStatus: ProcessingStatus.pending,
            extractionStatus: ExtractionStatus.pending,
            error: 'Processing was cancelled before it started.',
            cancelled: true,
          ),
        );
      }
    }
  }

  Future<void> cancelAll() async {
    for (final id in List<String>.from(_queue)) {
      cancel(id);
    }
    for (final signal in _active.values) {
      signal.cancel();
    }
    while (_draining) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> _drain() async {
    if (_draining) {
      return;
    }
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final documentId = _queue.removeAt(0);
        final completer = _completers[documentId];
        if (completer == null || completer.isCompleted) {
          continue;
        }
        final signal = CancellationSignal();
        _active[documentId] = signal;
        try {
          final outcome = await processor.process(
            documentId,
            cancellation: signal,
          );
          if (!completer.isCompleted) {
            completer.complete(outcome);
          }
        } catch (error) {
          if (!completer.isCompleted) {
            completer.complete(
              ProcessingOutcome(
                documentId: documentId,
                processingStatus: ProcessingStatus.failed,
                extractionStatus: ExtractionStatus.failed,
                error: error.toString(),
              ),
            );
          }
        } finally {
          _active.remove(documentId);
          _completers.remove(documentId);
        }
      }
    } finally {
      _draining = false;
    }
  }
}
