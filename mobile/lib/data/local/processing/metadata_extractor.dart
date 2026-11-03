import 'dart:io';

class SourceFileMetadata {
  const SourceFileMetadata({this.modifiedAt});

  /// Filesystem modification time.
  final DateTime? modifiedAt;
}

class MetadataExtractor {
  const MetadataExtractor();

  Future<SourceFileMetadata> read(File file) async {
    try {
      final stat = await file.stat();
      return SourceFileMetadata(modifiedAt: stat.modified.toUtc());
    } catch (_) {
      return const SourceFileMetadata();
    }
  }
}
