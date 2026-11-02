import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../core/error_text.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../widgets/shared_widgets.dart';
import 'document_detail_screen.dart';

typedef PdfDocumentViewBuilder =
    Widget Function(
      BuildContext context,
      Uint8List bytes,
      PdfViewerController controller,
      PdfPageChangedCallback onPageChanged,
    );

enum ViewerKind { pdf, image, text, unsupported }

/// Shows the unchanged original file retrieved through the authenticated API.
///
/// Extracted text is never used as a fallback for a PDF or image. When the
/// original is missing or unsupported, the screen says so explicitly.
class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({
    super.key,
    required this.document,
    this.showDetailsAction = true,
    this.pdfViewBuilder,
  });

  final DocumentResponse document;
  final bool showDetailsAction;
  final PdfDocumentViewBuilder? pdfViewBuilder;

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();

  bool _loading = true;
  String? _error;
  Uint8List? _bytes;
  ViewerKind _kind = ViewerKind.unsupported;
  int _pageNumber = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _bytes = null;
    });
    try {
      final downloaded = await context.read<LoreApiClient>().downloadDocument(
        widget.document.id,
      );
      if (!mounted) return;
      setState(() {
        _bytes = Uint8List.fromList(downloaded.bytes);
        _kind = _kindFor(widget.document, downloaded);
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.isNotFound
            ? 'The original file is missing from backend storage. Extracted '
                  'text was not substituted for it.'
            : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  ViewerKind _kindFor(
    DocumentResponse document,
    DownloadedDocument downloaded,
  ) {
    final mediaType = (downloaded.mediaType ?? document.mediaType ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    final name = document.originalFilename.toLowerCase();

    if (mediaType == 'application/pdf' || name.endsWith('.pdf')) {
      return ViewerKind.pdf;
    }
    if (mediaType.startsWith('image/') ||
        const [
          '.png',
          '.jpg',
          '.jpeg',
          '.webp',
          '.gif',
          '.bmp',
          '.heic',
        ].any(name.endsWith)) {
      return ViewerKind.image;
    }
    if (mediaType.startsWith('text/') ||
        const ['.txt', '.md', '.csv', '.log', '.json'].any(name.endsWith)) {
      return ViewerKind.text;
    }
    return ViewerKind.unsupported;
  }

  void _openDetails() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentDetailScreen(documentId: widget.document.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          widget.document.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.showDetailsAction)
            IconButton(
              tooltip: 'Document details',
              onPressed: _openDetails,
              icon: const Icon(Icons.info_outline, size: 20),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoreLoadingState(message: 'Opening the original file…');
    }
    if (_error != null) {
      return LoreErrorState(message: _error!, onRetry: _load);
    }
    final bytes = _bytes;
    if (bytes == null) {
      return LoreErrorState(
        message: 'The original file could not be loaded.',
        onRetry: _load,
      );
    }

    switch (_kind) {
      case ViewerKind.pdf:
        return _buildPdf(bytes);
      case ViewerKind.image:
        return _buildImage(bytes);
      case ViewerKind.text:
        return _buildText(bytes);
      case ViewerKind.unsupported:
        return _buildUnsupported();
    }
  }

  Widget _buildPdf(Uint8List bytes) {
    final builder = widget.pdfViewBuilder;
    final viewer = builder != null
        ? builder(context, bytes, _pdfController, _onPageChanged)
        : PdfViewer.data(
            bytes,
            sourceName: widget.document.originalFilename,
            controller: _pdfController,
            params: PdfViewerParams(
              onPageChanged: _onPageChanged,
              loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                  const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                  _PdfError(message: describeError(error)),
            ),
          );

    return Column(
      children: [
        Expanded(child: viewer),
        _PdfControls(
          controller: _pdfController,
          pageNumber: _pageNumber,
          onPrevious: _goToPreviousPage,
          onNext: _goToNextPage,
        ),
      ],
    );
  }

  void _onPageChanged(int? pageNumber) {
    if (!mounted || pageNumber == null) return;
    setState(() => _pageNumber = pageNumber);
  }

  void _goToPreviousPage() {
    if (!_pdfController.isReady || _pageNumber <= 1) return;
    _pdfController.goToPage(pageNumber: _pageNumber - 1);
  }

  void _goToNextPage() {
    if (!_pdfController.isReady || _pageNumber >= _pdfController.pageCount) {
      return;
    }
    _pdfController.goToPage(pageNumber: _pageNumber + 1);
  }

  Widget _buildImage(Uint8List bytes) {
    return Container(
      color: LoreColors.surfaceContainerLow,
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 6,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return _ViewerMessage(
                icon: Icons.broken_image_outlined,
                title: 'The image could not be displayed',
                message:
                    'The stored original is present but could not be decoded. '
                    'Extracted text was not substituted.',
                onRetry: _load,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildText(Uint8List bytes) {
    String content;
    try {
      if (bytes.contains(0)) {
        throw const FormatException('binary content');
      }
      content = utf8.decode(bytes);
    } on FormatException {
      return const _ViewerMessage(
        icon: Icons.text_fields_outlined,
        title: 'The text file could not be read',
        message:
            'The original is stored unchanged, but its contents are not valid '
            'UTF-8 text.',
      );
    }
    return Container(
      color: LoreColors.surfaceContainerLowest,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ORIGINAL TEXT · READ-ONLY',
              style: LoreTypography.labelSm.copyWith(
                color: LoreColors.secondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              content,
              style: LoreTypography.bodyMd.copyWith(
                color: LoreColors.onSurface,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupported() {
    return _ViewerMessage(
      icon: Icons.insert_drive_file_outlined,
      title: 'This format cannot be displayed in the app',
      message:
          'The original ${widget.document.originalFilename} is stored unchanged '
          'on your LORE backend, but this viewer supports PDF, common image '
          'formats, and plain text. Extracted text is not shown in place of '
          'the original.',
    );
  }
}

class _PdfControls extends StatelessWidget {
  final PdfViewerController controller;
  final int pageNumber;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _PdfControls({
    required this.controller,
    required this.pageNumber,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final total = controller.isReady ? controller.pageCount : null;
    return Material(
      color: LoreColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: pageNumber > 1 ? onPrevious : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                total == null
                    ? 'Page $pageNumber'
                    : 'Page $pageNumber / $total',
                style: LoreTypography.labelMd.copyWith(
                  color: LoreColors.onSurface,
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: total != null && pageNumber < total ? onNext : null,
                icon: const Icon(Icons.chevron_right),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: controller.isReady
                    ? () => controller.zoomDown()
                    : null,
                icon: const Icon(Icons.zoom_out, size: 20),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: controller.isReady
                    ? () => controller.zoomUp()
                    : null,
                icon: const Icon(Icons.zoom_in, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfError extends StatelessWidget {
  final String message;

  const _PdfError({required this.message});

  @override
  Widget build(BuildContext context) {
    return _ViewerMessage(
      icon: Icons.picture_as_pdf_outlined,
      title: 'The PDF could not be opened',
      message:
          '$message The original file may be corrupted. Extracted text was not '
          'substituted.',
    );
  }
}

class _ViewerMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _ViewerMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: LoreColors.secondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: LoreTypography.headlineSm.copyWith(
                color: LoreColors.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: LoreTypography.bodyMd.copyWith(
                color: LoreColors.secondary,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
