import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../state/documents_controller.dart';

const List<String> _supportedExtensions = [
  'pdf',
  'txt',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'tif',
  'tiff',
  'webp',
];

class ImportDocumentsScreen extends StatefulWidget {
  const ImportDocumentsScreen({super.key});

  @override
  State<ImportDocumentsScreen> createState() => _ImportDocumentsScreenState();
}

class _ImportDocumentsScreenState extends State<ImportDocumentsScreen> {
  final List<UploadCandidate> _selected = [];
  bool _picking = false;
  bool _importing = false;
  String? _pickError;
  UploadOutcome? _outcome;

  int get _totalBytes =>
      _selected.fold<int>(0, (sum, file) => sum + file.bytes.length);

  Future<void> _pickFiles() async {
    if (_picking || _importing) return;
    setState(() {
      _picking = true;
      _pickError = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Choose documents',
        type: FileType.custom,
        allowedExtensions: _supportedExtensions,
      );
      if (files.isEmpty) return;
      final keys = _selected
          .map((file) => '${file.filename}:${file.bytes.length}')
          .toSet();
      final added = <UploadCandidate>[];
      for (final file in files) {
        try {
          final bytes = await file.readAsBytes();
          final key = '${file.name}:${bytes.length}';
          if (!keys.add(key)) continue;
          added.add(UploadCandidate(filename: file.name, bytes: bytes));
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _pickError =
                '${file.name} could not be read. Choose the file again.';
          });
        }
      }
      if (added.isNotEmpty) {
        setState(() {
          _selected.addAll(added);
          _outcome = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pickError = 'The file picker could not open: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _import() async {
    if (_selected.isEmpty || _importing) return;
    setState(() {
      _importing = true;
      _pickError = null;
      _outcome = null;
    });
    final controller = context.read<DocumentsController>();
    final outcome = await controller.upload(List.of(_selected));
    if (!mounted) return;
    setState(() {
      _importing = false;
      _outcome = outcome;
      if (outcome.hasUploads) {
        final uploadedNames = outcome.uploaded
            .map((document) => document.originalFilename)
            .toSet();
        _selected.removeWhere(
          (candidate) => uploadedNames.contains(candidate.filename),
        );
      }
    });
  }

  void _remove(UploadCandidate candidate) {
    setState(() {
      _selected.remove(candidate);
      _outcome = null;
    });
  }

  void _startOver() {
    setState(() {
      _outcome = null;
      _pickError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DocumentsController>();
    final outcome = _outcome;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Import documents'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Bring your files into LORE.',
            style: LoreTypography.headlineLgMobile.copyWith(
              color: LoreColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Files are uploaded to your LORE backend for extraction and '
            'storage. The app does not keep a second copy.',
            style: LoreTypography.bodyMd.copyWith(
              color: LoreColors.secondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _PickCard(picking: _picking, enabled: !_importing, onTap: _pickFiles),
          const SizedBox(height: 14),
          _InfoNote(
            icon: Icons.info_outline,
            text:
                'Supported: PDF, TXT, PNG, JPG, GIF, BMP, TIFF, and WEBP. '
                'Categories and relationships are assigned by the backend after '
                'upload; they are not previewed in the app.',
          ),
          if (_pickError != null) ...[
            const SizedBox(height: 14),
            _NoticeCard(
              icon: Icons.error_outline,
              color: LoreColors.error,
              title: 'Could not add files',
              message: _pickError!,
            ),
          ],
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Selected files',
                  style: LoreTypography.headlineSm.copyWith(
                    color: LoreColors.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${_selected.length})',
                  style: LoreTypography.labelMd.copyWith(
                    color: LoreColors.secondary,
                  ),
                ),
                const Spacer(),
                Text(
                  formatBytes(_totalBytes),
                  style: LoreTypography.labelMd.copyWith(
                    color: LoreColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: LoreColors.surfaceContainerLowest,
                borderRadius: LoreRadius.borderLg,
                border: Border.all(color: LoreColors.structuralLine),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < _selected.length; index++) ...[
                    _SelectedFileRow(
                      candidate: _selected[index],
                      onRemove: _importing
                          ? null
                          : () => _remove(_selected[index]),
                    ),
                    if (index < _selected.length - 1)
                      const Divider(
                        height: 1,
                        color: LoreColors.surfaceContainerHigh,
                      ),
                  ],
                ],
              ),
            ),
          ],
          if (_importing) ...[
            const SizedBox(height: 24),
            _ImportProgress(
              completed: controller.uploadCompleted,
              total: controller.uploadTotal,
              filename: controller.uploadFilename,
            ),
          ],
          if (outcome != null) ...[
            const SizedBox(height: 24),
            if (outcome.hasUploads)
              _NoticeCard(
                icon: Icons.check_circle_outline,
                color: LoreColors.privacyGreen,
                title:
                    '${outcome.uploaded.length} document${outcome.uploaded.length == 1 ? '' : 's'} imported',
                message:
                    'The backend stored and indexed the uploaded files. Open a '
                    'document to review its extracted fields and connections.',
              ),
            if (outcome.hasFailures) ...[
              const SizedBox(height: 12),
              _NoticeCard(
                icon: Icons.error_outline,
                color: LoreColors.error,
                title: 'Some files were not imported',
                message: outcome.failures
                    .map((failure) => '${failure.filename}: ${failure.message}')
                    .join('\n'),
              ),
            ],
            if (outcome.hasUploads)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _startOver,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Import more files'),
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _outcome?.hasUploads == true && _selected.isEmpty
              ? FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                )
              : FilledButton.icon(
                  onPressed: _selected.isEmpty || _importing ? null : _import,
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LoreColors.onPrimary,
                          ),
                        )
                      : const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(
                    _importing
                        ? 'Importing...'
                        : 'Import ${_selected.length} document${_selected.length == 1 ? '' : 's'}',
                  ),
                ),
        ),
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  final bool picking;
  final bool enabled;
  final VoidCallback onTap;

  const _PickCard({
    required this.picking,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: LoreRadius.borderLg,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: LoreColors.surfaceContainerLow,
          borderRadius: LoreRadius.borderLg,
          border: Border.all(color: LoreColors.structuralLine),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: LoreColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: LoreColors.structuralLine),
              ),
              child: picking
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.upload_file_outlined,
                      size: 24,
                      color: LoreColors.primary,
                    ),
            ),
            const SizedBox(height: 14),
            Text(
              picking ? 'Opening the file picker...' : 'Choose files',
              style: LoreTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
                color: LoreColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select one or more documents from this device.',
              textAlign: TextAlign.center,
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedFileRow extends StatelessWidget {
  final UploadCandidate candidate;
  final VoidCallback? onRemove;

  const _SelectedFileRow({required this.candidate, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: LoreColors.surfaceContainerLow,
              borderRadius: LoreRadius.borderMd,
            ),
            child: const Icon(
              Icons.insert_drive_file_outlined,
              size: 17,
              color: LoreColors.secondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LoreTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w500,
                    color: LoreColors.onSurface,
                  ),
                ),
                Text(
                  formatBytes(candidate.bytes.length),
                  style: LoreTypography.labelSm.copyWith(
                    color: LoreColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove file',
          ),
        ],
      ),
    );
  }
}

class _ImportProgress extends StatelessWidget {
  final int completed;
  final int total;
  final String? filename;

  const _ImportProgress({
    required this.completed,
    required this.total,
    this.filename,
  });

  @override
  Widget build(BuildContext context) {
    final value = total == 0 ? null : completed / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainerLowest,
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: LoreColors.structuralLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            filename == null
                ? 'Uploading to the LORE backend...'
                : 'Uploading $filename',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LoreTypography.bodySm.copyWith(
              color: LoreColors.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              color: LoreColors.primary,
              backgroundColor: LoreColors.surfaceContainerHigh,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$completed of $total processed',
            style: LoreTypography.labelSm.copyWith(color: LoreColors.secondary),
          ),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: LoreColors.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
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

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: LoreTypography.bodySm.copyWith(
                    color: LoreColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: LoreTypography.bodySm.copyWith(
                    color: LoreColors.secondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
