import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/document_style.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_navigation.dart';
import '../state/documents_controller.dart';
import '../widgets/shared_widgets.dart';
import 'document_viewer_screen.dart';
import 'import_documents_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  DocumentsView _view = DocumentsView.search;
  int _handledRequestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _applyNavigationRequest(DocumentsRequest? request) {
    if (request == null || request.id == _handledRequestId) return;
    _handledRequestId = request.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _view = request.view);
      final query = request.query;
      if (query != null && query.trim().isNotEmpty) {
        _searchController.text = query;
        context.read<DocumentsController>().search(query);
      } else if (_searchController.text.isNotEmpty) {
        _searchController.clear();
        context.read<DocumentsController>().clearSearch();
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context.read<DocumentsController>().search(value);
    });
  }

  void _submitSearch(String value) {
    _debounce?.cancel();
    context.read<DocumentsController>().search(value);
  }

  void _selectCategory(String? category) {
    final controller = context.read<DocumentsController>();
    controller.selectCategory(category);
    if (controller.hasActiveSearch) {
      controller.search(controller.searchQuery);
    }
  }

  void _openDocument(DocumentResponse document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentViewerScreen(document: document),
      ),
    );
  }

  Future<void> _openDocumentById(String id) async {
    final controller = context.read<DocumentsController>();
    DocumentResponse? document;
    for (final item in controller.documents) {
      if (item.id == id) {
        document = item;
        break;
      }
    }
    if (document != null) {
      _openDocument(document);
      return;
    }
    try {
      final loaded = await controller.getDocument(id);
      if (!mounted) return;
      _openDocument(loaded);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This document could not be opened.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openImport() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ImportDocumentsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigation = context.watch<AppNavigation>();
    _applyNavigationRequest(navigation.documentsRequest);
    final documents = context.watch<DocumentsController>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: LoreColors.primary,
          onRefresh: documents.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Documents',
                                  style: LoreTypography.headlineLg.copyWith(
                                    fontSize: 32,
                                    color: LoreColors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Find files or explore their connections.',
                                  style: LoreTypography.bodyMd.copyWith(
                                    color: LoreColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _openImport,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Import'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _ModeSelector(
                        view: _view,
                        onChanged: (view) => setState(() => _view = view),
                      ),
                      const SizedBox(height: 16),
                      if (_view == DocumentsView.search) ...[
                        LoreSearchField(
                          controller: _searchController,
                          hint: 'Search your documents',
                          showSubmitButton: false,
                          onChanged: _onSearchChanged,
                          onSubmit: () => _submitSearch(_searchController.text),
                        ),
                        const SizedBox(height: 14),
                        _CategoryPills(
                          controller: documents,
                          onSelected: _selectCategory,
                        ),
                        const SizedBox(height: 14),
                        _CountRow(
                          count: documents.hasActiveSearch
                              ? documents.searchResults.length
                              : documents.documentsForCategory.length,
                          searchActive: documents.hasActiveSearch,
                        ),
                      ] else ...[
                        _ConnectionsIntro(),
                        const SizedBox(height: 14),
                        _CountRow(
                          count: documents.totalDocumentCount,
                          searchActive: false,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_view == DocumentsView.search)
                ..._buildSearchSlivers(documents)
              else
                ..._buildConnectionSlivers(documents),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 32),
                sliver: SliverToBoxAdapter(child: _StorageNote()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSearchSlivers(DocumentsController documents) {
    if (documents.hasActiveSearch) {
      if (documents.isSearching && documents.searchResults.isEmpty) {
        return const [
          SliverToBoxAdapter(
            child: LoreLoadingState(message: 'Searching your documents...'),
          ),
        ];
      }
      if (documents.searchError != null) {
        return [
          SliverToBoxAdapter(
            child: LoreErrorState(
              message: documents.searchError!,
              onRetry: () => documents.search(documents.searchQuery),
            ),
          ),
        ];
      }
      if (documents.searchResults.isEmpty) {
        return [
          SliverToBoxAdapter(
            child: LoreEmptyState(
              icon: Icons.search_off,
              title: 'No matches',
              subtitle:
                  'No indexed document matched “${documents.searchQuery}”. Try '
                  'another term or category.',
            ),
          ),
        ];
      }
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final result = documents.searchResults[index];
              return _SearchResultRow(
                result: result,
                onTap: () => _openDocumentById(result.documentId),
              );
            }, childCount: documents.searchResults.length),
          ),
        ),
      ];
    }

    if (documents.isLoading && documents.documents.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: LoreLoadingState(message: 'Loading your documents...'),
        ),
      ];
    }
    if (documents.error != null && documents.documents.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: LoreErrorState(
            message: documents.error!,
            onRetry: () => documents.load(),
          ),
        ),
      ];
    }

    final visible = documents.documentsForCategory;
    if (documents.hasLoaded && visible.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: LoreEmptyState(
            title: documents.selectedCategory == null
                ? 'No documents yet'
                : 'No documents in this category',
            subtitle: documents.selectedCategory == null
                ? 'Import a PDF, text file, or image to build your archive.'
                : 'Choose another category or import a document.',
            action: FilledButton(
              onPressed: _openImport,
              child: const Text('Import documents'),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final document = visible[index];
            return _DocumentRow(
              document: document,
              subtitle:
                  '${document.categoryLabel} · ${formatDate(document.uploadedAt)}',
              onTap: () => _openDocument(document),
            );
          }, childCount: visible.length),
        ),
      ),
    ];
  }

  List<Widget> _buildConnectionSlivers(DocumentsController documents) {
    if (documents.isLoading && documents.documents.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: LoreLoadingState(message: 'Loading your documents...'),
        ),
      ];
    }
    if (documents.error != null && documents.documents.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: LoreErrorState(
            message: documents.error!,
            onRetry: () => documents.load(),
          ),
        ),
      ];
    }
    if (documents.hasLoaded && documents.documents.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: LoreEmptyState(
            title: 'No connections to explore',
            subtitle:
                'Import documents first. LORE builds connections from document '
                'metadata and extracted text on the backend.',
            action: FilledButton(
              onPressed: _openImport,
              child: const Text('Import documents'),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final document = documents.documents[index];
            return _DocumentRow(
              document: document,
              subtitle:
                  '${document.categoryLabel} · tap to inspect connections',
              onTap: () => _openDocument(document),
            );
          }, childCount: documents.documents.length),
        ),
      ),
    ];
  }
}

class _ModeSelector extends StatelessWidget {
  final DocumentsView view;
  final ValueChanged<DocumentsView> onChanged;

  const _ModeSelector({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainer,
        borderRadius: LoreRadius.borderFull,
        border: Border.all(color: LoreColors.structuralLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: 'Search',
              selected: view == DocumentsView.search,
              onTap: () => onChanged(DocumentsView.search),
            ),
          ),
          Expanded(
            child: _ModeButton(
              label: 'Connections',
              selected: view == DocumentsView.connections,
              onTap: () => onChanged(DocumentsView.connections),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? LoreColors.surfaceContainerLowest
              : Colors.transparent,
          borderRadius: LoreRadius.borderFull,
          border: Border.all(
            color: selected ? LoreColors.structuralLine : Colors.transparent,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: LoreTypography.labelMd.copyWith(
            color: selected ? LoreColors.onSurface : LoreColors.secondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _CategoryPills extends StatelessWidget {
  final DocumentsController controller;
  final ValueChanged<String?> onSelected;

  const _CategoryPills({required this.controller, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedCategory;
    final categories = controller.categories
        .where((item) => item.documentCount > 0 || item.category == selected)
        .toList();

    return SizedBox(
      height: 32,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _CategoryPill(
              label: 'All',
              selected: selected == null,
              onTap: () => onSelected(null),
            ),
            for (final category in categories) ...[
              const SizedBox(width: 18),
              _CategoryPill(
                label: category.category,
                selected: selected == category.category,
                onTap: () => onSelected(category.category),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: LoreTypography.labelMd.copyWith(
                color: selected ? LoreColors.onSurface : LoreColors.secondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 2,
              width: selected ? 18 : 0,
              color: LoreColors.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  final int count;
  final bool searchActive;

  const _CountRow({required this.count, required this.searchActive});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            searchActive
                ? '$count result${count == 1 ? '' : 's'}'
                : '$count document${count == 1 ? '' : 's'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LoreTypography.labelMd.copyWith(
              color: LoreColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            'Sort: Recently added',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: LoreTypography.labelMd.copyWith(color: LoreColors.secondary),
          ),
        ),
      ],
    );
  }
}

class _ConnectionsIntro extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainerLow,
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: LoreColors.structuralLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hub_outlined, size: 20, color: LoreColors.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Connections are calculated by your LORE backend. Open a document '
              'to see the related files it has detected and the evidence behind '
              'each connection.',
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.secondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  final DocumentResponse document;
  final String subtitle;
  final VoidCallback onTap;

  const _DocumentRow({
    required this.document,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: LoreRadius.borderLg,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: LoreColors.surfaceContainerLowest,
            borderRadius: LoreRadius.borderLg,
            border: Border.all(color: LoreColors.structuralLine),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: LoreColors.surfaceContainerLow,
                  borderRadius: LoreRadius.borderLg,
                ),
                child: Icon(
                  iconForDocument(document),
                  size: 18,
                  color: LoreColors.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LoreTypography.bodyMd.copyWith(
                        color: LoreColors.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LoreColors.surfaceContainer,
                  borderRadius: LoreRadius.borderSm,
                  border: Border.all(color: LoreColors.structuralLine),
                ),
                child: Text(
                  documentKindLabel(document).toUpperCase(),
                  style: LoreTypography.labelSm.copyWith(
                    color: LoreColors.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: LoreColors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const _SearchResultRow({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final matched = result.matchingFields.isNotEmpty
        ? 'Matched: ${result.matchingFields.join(', ')}'
        : (result.category ?? 'Document');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: LoreRadius.borderLg,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: LoreColors.surfaceContainerLowest,
            borderRadius: LoreRadius.borderLg,
            border: Border.all(color: LoreColors.structuralLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.search, size: 17, color: LoreColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LoreTypography.bodyMd.copyWith(
                        color: LoreColors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: LoreColors.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                result.snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: LoreTypography.bodySm.copyWith(
                  color: LoreColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                matched,
                style: LoreTypography.labelSm.copyWith(
                  color: LoreColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.lock_outline,
          size: 16,
          color: LoreColors.privacyGreen,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Documents are stored by your LORE backend. The app keeps no local '
            'copy of their contents.',
            style: LoreTypography.bodySm.copyWith(
              color: LoreColors.secondary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
