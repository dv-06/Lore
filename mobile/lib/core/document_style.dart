import 'package:flutter/material.dart';

import '../data/models.dart';

IconData iconForDocument(DocumentResponse document) {
  final mediaType = document.mediaType ?? '';
  if (mediaType.startsWith('image/')) return Icons.image_outlined;
  if (mediaType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mediaType == 'text/plain') return Icons.article_outlined;
  return Icons.description_outlined;
}

String documentKindLabel(DocumentResponse document) {
  final documentType = document.documentType?.trim();
  if (documentType != null && documentType.isNotEmpty) return documentType;

  final mediaType = document.mediaType ?? '';
  if (mediaType == 'application/pdf') return 'PDF';
  if (mediaType == 'text/plain') return 'Text';
  if (mediaType.startsWith('image/')) return 'Image';

  final dot = document.originalFilename.lastIndexOf('.');
  if (dot >= 0 && dot < document.originalFilename.length - 1) {
    return document.originalFilename.substring(dot + 1).toUpperCase();
  }
  return 'Document';
}

String extractionStatusLabel(String status) {
  switch (status) {
    case 'extracted':
      return 'Text extracted';
    case 'failed':
      return 'Extraction failed';
    case 'not_requested':
      return 'Text extraction not requested';
    case 'pending':
    case 'processing':
      return 'Extraction in progress';
    default:
      return status;
  }
}
