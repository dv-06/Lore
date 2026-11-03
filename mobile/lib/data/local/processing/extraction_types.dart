class CancellationSignal {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const ProcessingCancelledException();
    }
  }
}

class ProcessingCancelledException implements Exception {
  const ProcessingCancelledException();

  @override
  String toString() => 'Processing was cancelled.';
}

enum ExtractionFailureKind {
  unsupportedFormat,
  unavailableCapability,
  malformedDocument,
  encoding,
  io,
}

class DocumentExtractionException implements Exception {
  const DocumentExtractionException(
    this.message, {
    this.kind = ExtractionFailureKind.malformedDocument,
  });

  final String message;
  final ExtractionFailureKind kind;

  bool get isCapabilityFailure =>
      kind == ExtractionFailureKind.unavailableCapability;

  @override
  String toString() => message;
}

class ExtractionOutcome {
  const ExtractionOutcome({
    required this.text,
    required this.method,
    this.pageCount,
    this.partial = false,
    this.warning,
  });

  final String text;
  final String method;
  final int? pageCount;
  final bool partial;
  final String? warning;

  bool get hasText => text.trim().isNotEmpty;
}
