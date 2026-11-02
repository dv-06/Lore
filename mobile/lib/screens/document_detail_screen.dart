import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/document_style.dart';
import '../core/error_text.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/documents_controller.dart';
import '../widgets/shared_widgets.dart';
import 'document_ask_screen.dart';
import 'document_viewer_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({
    super.key,
    required this.documentId,
    this.initialDocument,
  });

  final String documentId;
  final DocumentResponse? initialDocument;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final GlobalKey _relatedKey = GlobalKey();
  DocumentResponse? _document;
  List<RelationshipSuggestion> _related = const [];
  bool _relatedLoading = true;
  String? _error;
  String? _relatedError;
  String? _actionName;
  bool _showAllDetails = false;

  @override
  void initState() {
    super.initState();
    _document = widget.initialDocument;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final controller = context.read<DocumentsController>();
    setState(() {
      _error = null;
      _relatedLoading = true;
      _relatedError = null;
    });

    try {
      final document = await controller.getDocument(widget.documentId);
      if (!mounted) return;
      setState(() => _document = document);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_document == null) _error = describeError(error);
      });
    }

    try {
      final related = await controller.getRelatedDocuments(widget.documentId);
      if (!mounted) return;
      setState(() {
        _related = related.items;
        _relatedLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _relatedError = describeError(error);
        _relatedLoading = false;
      });
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _runDocumentAction(
    String key,
    Future<DocumentResponse> Function() action,
    String successMessage,
  ) async {
    if (_actionName != null) return;
    setState(() => _actionName = key);
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        _document = updated;
        _actionName = null;
      });
      _showSnack(successMessage);
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionName = null);
      _showSnack(describeError(error));
    }
  }

  Future<void> _retryExtraction() {
    final controller = context.read<DocumentsController>();
    return _runDocumentAction(
      'retry',
      () => controller.retryExtraction(widget.documentId),
      'Extraction retried.',
    );
  }

  Future<void> _classify() {
    final controller = context.read<DocumentsController>();
    return _runDocumentAction(
      'classify',
      () => controller.classifyDocument(widget.documentId),
      'Classification updated.',
    );
  }

  Future<void> _recalculateRelated() async {
    if (_actionName != null) return;
    setState(() {
      _actionName = 'related';
      _relatedLoading = true;
      _relatedError = null;
    });
    try {
      final response = await context
          .read<DocumentsController>()
          .recalculateRelatedDocuments(widget.documentId);
      if (!mounted) return;
      setState(() {
        _related = response.items;
        _relatedLoading = false;
        _actionName = null;
      });
      _showSnack(
        'Connections recalculated: ${response.items.length} related document${response.items.length == 1 ? '' : 's'}.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _relatedError = describeError(error);
        _relatedLoading = false;
        _actionName = null;
      });
      _showSnack(describeError(error));
    }
  }

  Future<void> _editOrganization() async {
    final document = _document;
    if (document == null || _actionName != null) return;
    final controller = context.read<DocumentsController>();
    final categories = <String>{
      'Finance',
      'Education',
      'Health',
      'Identity',
      'Home',
      'Appliances',
      'Insurance',
      'Travel',
      'Work',
      'Legal',
      'Uncategorized',
      for (final item in controller.categories) item.category,
      if (document.category != null) document.category!,
    }.toList()..sort();
    var selectedCategory = document.category ?? 'Uncategorized';
    final tagsController = TextEditingController(
      text: document.tags.join(', '),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Review document organization'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CATEGORY',
                      style: LoreTypography.labelSm.copyWith(
                        color: LoreColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in categories)
                          ChoiceChip(
                            label: Text(category),
                            selected: selectedCategory == category,
                            onSelected: (_) => setDialogState(
                              () => selectedCategory = category,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'TAGS',
                      style: LoreTypography.labelSm.copyWith(
                        color: LoreColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tagsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Comma-separated, up to 20 tags',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    final rawTags = tagsController.text;
    tagsController.dispose();
    if (saved != true || !mounted) return;

    final tags = rawTags
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .take(20)
        .toList();
    setState(() => _actionName = 'organization');
    try {
      final updated = await controller.updateOrganization(
        document.id,
        category: selectedCategory,
        tags: tags,
      );
      if (!mounted) return;
      setState(() {
        _document = updated;
        _actionName = null;
      });
      _showSnack('Document organization updated.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionName = null);
      _showSnack(describeError(error));
    }
  }

  Future<void> _deleteDocument() async {
    if (_document == null || _actionName != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this document?'),
        content: const Text(
          'This removes the document, its extracted text, and its connections '
          'from the LORE backend. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = context.read<DocumentsController>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _actionName = 'delete');
    try {
      await controller.deleteDocument(widget.documentId);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Document deleted from the LORE backend.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionName = null);
      _showSnack(describeError(error));
    }
  }

  void _scrollToRelated() {
    final relatedContext = _relatedKey.currentContext;
    if (relatedContext == null) return;
    Scrollable.ensureVisible(
      relatedContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }

  void _openRelated(RelationshipSuggestion relationship) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DocumentDetailScreen(documentId: relationship.relatedDocument.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Document details'),
      ),
      body: document == null ? _buildPlaceholder() : _buildBody(document),
    );
  }

  Widget _buildPlaceholder() {
    if (_error != null) {
      return LoreErrorState(message: _error!, onRetry: _load);
    }
    return const LoreLoadingState(message: 'Loading document details...');
  }

  Widget _buildBody(DocumentResponse document) {
    return RefreshIndicator(
      color: LoreColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '${document.categoryLabel.toUpperCase()} · ADDED ${formatDate(document.uploadedAt).toUpperCase()}',
            style: LoreTypography.labelMd.copyWith(
              color: LoreColors.secondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            document.displayName,
            style: LoreTypography.headlineLgMobile.copyWith(
              color: LoreColors.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          _FileSummary(document: document),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocumentViewerScreen(
                    document: document,
                    showDetailsAction: false,
                  ),
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 17),
              label: const Text('Open original'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DocumentAskScreen(document: document),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 17),
                  label: const Text('Ask LORE'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scrollToRelated,
                  icon: const Icon(Icons.hub_outlined, size: 17),
                  label: const Text('Connections'),
                ),
              ),
            ],
          ),
          if (document.hasProcessingFailure) ...[
            const SizedBox(height: 14),
            _ProcessingWarning(
              message:
                  document.processingError ??
                  'This document could not be fully processed.',
              onRetry: _actionName == null ? _retryExtraction : null,
            ),
          ],
          const SizedBox(height: 24),
          const _SectionHeader(
            title: 'Information found',
            subtitle: 'Fields extracted and stored by your LORE backend.',
          ),
          const SizedBox(height: 8),
          _buildInformationCard(document),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _showAllDetails = !_showAllDetails),
              icon: Icon(
                _showAllDetails ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                _showAllDetails ? 'Hide details' : 'Show all details',
              ),
            ),
          ),
          if (_showAllDetails) ...[
            const SizedBox(height: 8),
            const _SectionHeader(
              title: 'File information',
              subtitle: 'Technical details from backend storage.',
            ),
            const SizedBox(height: 8),
            _buildFileDetailsCard(document),
            const SizedBox(height: 18),
            const _SectionHeader(
              title: 'Classification detail',
              subtitle:
                  'Rule-based category signals, not a confidence guarantee.',
            ),
            const SizedBox(height: 8),
            _buildClassificationCard(document),
          ],
          const SizedBox(height: 24),
          const _SectionHeader(
            title: 'Organization',
            subtitle: 'Adjust the category and tags stored by the backend.',
          ),
          const SizedBox(height: 8),
          _buildOrganizationCard(document),
          const SizedBox(height: 24),
          const _SectionHeader(
            title: 'Document processing',
            subtitle: 'Actions run on the LORE backend.',
          ),
          const SizedBox(height: 8),
          _buildActionsCard(document),
          const SizedBox(height: 24),
          KeyedSubtree(
            key: _relatedKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  title: 'Related documents',
                  subtitle: _related.isEmpty || _relatedLoading
                      ? 'Backend-calculated connections.'
                      : '${_related.length} backend-calculated connection${_related.length == 1 ? '' : 's'}. Scores are heuristic.',
                  trailing: IconButton(
                    onPressed: _actionName == null && !_relatedLoading
                        ? _recalculateRelated
                        : null,
                    icon: _relatedLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    tooltip: 'Recalculate connections',
                  ),
                ),
                const SizedBox(height: 8),
                _buildRelatedCard(),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Center(
            child: TextButton.icon(
              onPressed: _actionName == null ? _deleteDocument : null,
              style: TextButton.styleFrom(foregroundColor: LoreColors.error),
              icon: _actionName == 'delete'
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LoreColors.error,
                      ),
                    )
                  : const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete document'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationCard(DocumentResponse document) {
    final rows = <Widget>[];
    void add(String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      if (rows.isNotEmpty) rows.add(const Divider(height: 1));
      rows.add(_DetailRow(label: label, value: value));
    }

    add('Category', document.categoryLabel);
    add('Classification', percentLabel(document.classificationConfidence));
    add(
      'Document date',
      document.documentDate == null ? null : formatDate(document.documentDate),
    );
    add('Document type', document.documentType);
    add('Issuer', document.issuer);
    add('Reference', document.referenceNumber);
    add('Tags', document.tags.isEmpty ? null : document.tags.join(', '));
    add('Extraction', extractionStatusLabel(document.extractionStatus));

    if (rows.isEmpty) {
      return const _Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'No structured fields were extracted from this document yet.',
            style: TextStyle(color: LoreColors.secondary),
          ),
        ),
      );
    }
    return _Card(child: Column(children: rows));
  }

  Widget _buildFileDetailsCard(DocumentResponse document) {
    return _Card(
      child: Column(
        children: [
          _DetailRow(
            label: 'Original filename',
            value: document.originalFilename,
          ),
          const Divider(height: 1),
          _DetailRow(
            label: 'Media type',
            value: document.mediaType ?? 'Unknown',
          ),
          const Divider(height: 1),
          _DetailRow(label: 'Size', value: document.formattedSize),
          const Divider(height: 1),
          _DetailRow(label: 'Uploaded', value: formatDate(document.uploadedAt)),
          const Divider(height: 1),
          _DetailRow(label: 'Processing', value: document.processingStatus),
          const Divider(height: 1),
          _DetailRow(label: 'Document ID', value: document.id),
          if (document.sha256 != null) ...[
            const Divider(height: 1),
            _DetailRow(label: 'SHA-256', value: document.sha256!),
          ],
        ],
      ),
    );
  }

  Widget _buildClassificationCard(DocumentResponse document) {
    return _Card(
      child: Column(
        children: [
          _DetailRow(
            label: 'Method',
            value: document.classificationMethod ?? 'Not recorded',
          ),
          const Divider(height: 1),
          _DetailRow(
            label: 'Score',
            value: percentLabel(document.classificationConfidence),
          ),
          if (document.classificationReasons.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REASONS',
                    style: LoreTypography.labelSm.copyWith(
                      color: LoreColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final reason in document.classificationReasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('· '),
                          Expanded(
                            child: Text(
                              reason,
                              style: LoreTypography.bodySm.copyWith(
                                color: LoreColors.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrganizationCard(DocumentResponse document) {
    return _Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    'Tags',
                    style: LoreTypography.bodySm.copyWith(
                      color: LoreColors.secondary,
                    ),
                  ),
                ),
                Expanded(
                  child: document.tags.isEmpty
                      ? Text(
                          'No tags',
                          style: LoreTypography.bodySm.copyWith(
                            color: LoreColors.secondary,
                          ),
                        )
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in document.tags)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: LoreColors.surfaceContainer,
                                  borderRadius: LoreRadius.borderSm,
                                  border: Border.all(
                                    color: LoreColors.structuralLine,
                                  ),
                                ),
                                child: Text(
                                  tag,
                                  style: LoreTypography.labelSm.copyWith(
                                    color: LoreColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 2,
            ),
            leading: const Icon(
              Icons.edit_outlined,
              size: 20,
              color: LoreColors.secondary,
            ),
            title: Text(
              'Review category & tags',
              style: LoreTypography.bodyMd.copyWith(
                color: LoreColors.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              'Changes are saved to the backend only.',
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.secondary,
              ),
            ),
            trailing: _actionName == 'organization'
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: LoreColors.secondary,
                  ),
            onTap: _actionName == null ? _editOrganization : null,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(DocumentResponse document) {
    return _Card(
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.restart_alt,
            title: 'Retry extraction',
            subtitle: extractionStatusLabel(document.extractionStatus),
            busy: _actionName == 'retry',
            onTap: _actionName == null ? _retryExtraction : null,
          ),
          const Divider(height: 1),
          _ActionRow(
            icon: Icons.category_outlined,
            title: 'Reclassify document',
            subtitle: 'Re-run backend category detection',
            busy: _actionName == 'classify',
            onTap: _actionName == null ? _classify : null,
          ),
          const Divider(height: 1),
          _ActionRow(
            icon: Icons.hub_outlined,
            title: 'Recalculate connections',
            subtitle: 'Refresh related-document links',
            busy: _actionName == 'related',
            onTap: _actionName == null ? _recalculateRelated : null,
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedCard() {
    if (_relatedLoading) {
      return const _Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text(
                'Looking for connections...',
                style: TextStyle(color: LoreColors.secondary),
              ),
            ],
          ),
        ),
      );
    }
    if (_relatedError != null) {
      return _Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _relatedError!,
                style: LoreTypography.bodySm.copyWith(
                  color: LoreColors.error,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _actionName == null ? _recalculateRelated : null,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_related.isEmpty) {
      return _Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No related documents detected yet. LORE compares document '
                'metadata and extracted text on the backend.',
                style: LoreTypography.bodySm.copyWith(
                  color: LoreColors.secondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _actionName == null ? _recalculateRelated : null,
                child: const Text('Recalculate connections'),
              ),
            ],
          ),
        ),
      );
    }

    return _Card(
      child: Column(
        children: [
          for (var index = 0; index < _related.length; index++) ...[
            _RelatedRow(
              relationship: _related[index],
              onTap: () => _openRelated(_related[index]),
            ),
            if (index < _related.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainerLowest,
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: LoreColors.structuralLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: LoreTypography.headlineSm.copyWith(
                  color: LoreColors.onSurface,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: LoreTypography.bodySm.copyWith(
                    color: LoreColors.secondary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _FileSummary extends StatelessWidget {
  final DocumentResponse document;

  const _FileSummary({required this.document});

  @override
  Widget build(BuildContext context) {
    final color = document.hasProcessingFailure
        ? LoreColors.error
        : document.hasExtractedText
        ? LoreColors.privacyGreen
        : LoreColors.secondary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainerLowest,
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: LoreColors.structuralLine),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: LoreColors.surfaceContainerLow,
              borderRadius: LoreRadius.borderLg,
            ),
            child: Icon(
              iconForDocument(document),
              size: 22,
              color: LoreColors.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.originalFilename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LoreTypography.bodyMd.copyWith(
                    color: LoreColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${documentKindLabel(document)} · ${document.formattedSize}',
                  style: LoreTypography.bodySm.copyWith(
                    color: LoreColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: LoreRadius.borderSm,
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Text(
              extractionStatusLabel(document.extractionStatus),
              style: LoreTypography.labelSm.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.onSurface,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(icon, size: 20, color: LoreColors.secondary),
      title: Text(
        title,
        style: LoreTypography.bodyMd.copyWith(
          color: LoreColors.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: LoreTypography.bodySm.copyWith(color: LoreColors.secondary),
      ),
      trailing: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(
              Icons.chevron_right,
              size: 18,
              color: LoreColors.secondary,
            ),
      onTap: onTap,
    );
  }
}

class _RelatedRow extends StatelessWidget {
  final RelationshipSuggestion relationship;
  final VoidCallback onTap;

  const _RelatedRow({required this.relationship, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final related = relationship.relatedDocument;
    final percent = (relationship.score * 100).round();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: LoreColors.surfaceContainerLow,
                borderRadius: LoreRadius.borderLg,
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 18,
                color: LoreColors.secondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    related.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LoreTypography.bodyMd.copyWith(
                      color: LoreColors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${related.category ?? 'Uncategorized'} · ${relationship.relationshipType.replaceAll('_', ' ')}',
                    style: LoreTypography.labelMd.copyWith(
                      color: LoreColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    relationship.explanation,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LoreTypography.bodySm.copyWith(
                      color: LoreColors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  if (relationship.evidence.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      relationship.evidence.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LoreTypography.labelSm.copyWith(
                        color: LoreColors.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: LoreColors.surfaceContainer,
                    borderRadius: LoreRadius.borderSm,
                  ),
                  child: Text(
                    '$percent%',
                    style: LoreTypography.labelSm.copyWith(
                      color: LoreColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: LoreColors.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessingWarning extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ProcessingWarning({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoreColors.errorContainer.withValues(alpha: 0.55),
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: LoreColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            size: 18,
            color: LoreColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Processing issue',
                  style: LoreTypography.bodySm.copyWith(
                    color: LoreColors.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: LoreTypography.bodySm.copyWith(
                    color: LoreColors.onErrorContainer,
                    height: 1.45,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: LoreColors.onErrorContainer,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                    ),
                    child: const Text('Retry extraction'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
