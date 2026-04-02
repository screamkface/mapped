import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/destination_controller.dart';
import '../models/destination.dart';
import '../widgets/destination_form_sheet.dart';

class DestinationDetailScreen extends StatelessWidget {
  const DestinationDetailScreen({super.key, required this.destinationId});

  final String destinationId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DestinationController>();
    final destination = controller.findById(destinationId);

    if (destination == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dettaglio')),
        body: const Center(child: Text('Destinazione non disponibile.')),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(destination.displayName),
        actions: <Widget>[
          IconButton(
            tooltip: 'Modifica',
            onPressed: () => _editDestination(context, destination),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Elimina',
            onPressed: () => _deleteDestination(context, destination),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    destination.displayName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      Chip(label: Text(destination.status.label)),
                      if (destination.category.isNotEmpty)
                        Chip(label: Text(destination.category)),
                      if (destination.dueDate != null)
                        Chip(label: Text('Scadenza ${_formatDate(destination.dueDate)}')),
                      if (destination.tags.isNotEmpty)
                        ...destination.tags.map((tag) => Chip(label: Text(tag))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    destination.fullAddress.isNotEmpty
                        ? destination.fullAddress
                        : 'Indirizzo non disponibile',
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _navigate(context, destination),
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Naviga'),
                  ),
                ],
              ),
            ),
          ),
          if (destination.hasAttachments) ...<Widget>[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Allegati',
              subtitle: '${destination.attachmentPaths.length} immagini salvate',
              children: <Widget>[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: destination.attachmentPaths
                      .map(
                        (path) => InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _openPhotoViewer(
                            context,
                            title: destination.displayName,
                            photoPath: path,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox(
                              width: 108,
                              height: 108,
                              child: Image.file(
                                File(path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Dati principali',
            children: <Widget>[
              _DetailRow(label: 'ID', value: destination.id),
              _DetailRow(label: 'Nome', value: destination.displayName),
              _DetailRow(
                label: 'Indirizzo',
                value: destination.address.isNotEmpty
                    ? destination.address
                    : 'Non disponibile',
              ),
              _DetailRow(
                label: 'Città',
                value: destination.city.isNotEmpty
                    ? destination.city
                    : 'Non disponibile',
              ),
              _DetailRow(
                label: 'CAP',
                value: destination.postalCode.isNotEmpty
                    ? destination.postalCode
                    : 'Non disponibile',
              ),
              _DetailRow(
                label: 'Telefono',
                value: destination.phone.isNotEmpty
                    ? destination.phone
                    : 'Non disponibile',
              ),
              _DetailRow(
                label: 'Categoria',
                value: destination.category.isNotEmpty
                    ? destination.category
                    : 'Non disponibile',
              ),
              _DetailRow(
                label: 'Tag',
                value: destination.tags.isNotEmpty
                    ? destination.tags.join(', ')
                    : 'Nessun tag',
              ),
              _DetailRow(
                label: 'Scadenza',
                value: _formatDate(destination.dueDate),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Coordinate e note',
            children: <Widget>[
              _DetailRow(
                label: 'Latitudine',
                value: destination.latitude?.toString() ?? 'Non disponibile',
              ),
              _DetailRow(
                label: 'Longitudine',
                value: destination.longitude?.toString() ?? 'Non disponibile',
              ),
              _DetailRow(
                label: 'Mappa',
                value: destination.hasCoordinates
                    ? 'Marker disponibile'
                    : 'Coordinate mancanti',
              ),
              _DetailRow(
                label: 'Note',
                value: destination.notes.isNotEmpty
                    ? destination.notes
                    : 'Nessuna nota',
              ),
            ],
          ),
          if (destination.hasChecklist) ...<Widget>[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Checklist',
              children: destination.checklistItems
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            item.isDone
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: item.isDone
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item.label)),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (destination.hasCustomFields) ...<Widget>[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Campi personalizzati',
              children: destination.sortedCustomFields
                  .map(
                    (entry) => _DetailRow(label: entry.key, value: entry.value),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editDestination(
    BuildContext context,
    Destination destination,
  ) async {
    final editedDestination = await showDestinationFormSheet(
      context,
      initialDestination: destination,
    );
    if (editedDestination == null || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final summary = await context
          .read<DestinationController>()
          .upsertDestination(editedDestination);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            summary.wasGeocoded
                ? 'Destinazione aggiornata. Coordinate trovate automaticamente.'
                : summary.stillMissingCoordinates
                ? 'Destinazione aggiornata. Coordinate non disponibili.'
                : 'Destinazione aggiornata.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Salvataggio non riuscito: $error')),
      );
    }
  }

  Future<void> _deleteDestination(
    BuildContext context,
    Destination destination,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Eliminare destinazione?'),
              content: Text(
                'La destinazione "${destination.displayName}" verrà rimossa.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Elimina'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    await context.read<DestinationController>().deleteDestination(
      destination.id,
    );

    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text('"${destination.displayName}" eliminata.')),
    );
  }

  Future<void> _navigate(BuildContext context, Destination destination) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<DestinationController>().navigateToDestination(
        destination,
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openPhotoViewer(
    BuildContext context, {
    required String title,
    required String photoPath,
  }) async {
    if (photoPath.trim().isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PhotoViewerScreen(title: title, photoPath: photoPath),
      ),
    );
  }

  static String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Non disponibile';
    }

    final localValue = value.toLocal();
    final day = localValue.day.toString().padLeft(2, '0');
    final month = localValue.month.toString().padLeft(2, '0');
    final year = localValue.year.toString();
    return '$day/$month/$year';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 380;
    final content = isCompact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(value),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 104,
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(child: Text(value)),
            ],
          );

    return Padding(padding: const EdgeInsets.only(bottom: 12), child: content);
  }
}

class _PhotoViewerScreen extends StatelessWidget {
  const _PhotoViewerScreen({required this.title, required this.photoPath});

  final String title;
  final String photoPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: InteractiveViewer(
        minScale: 0.9,
        maxScale: 4,
        child: Center(
          child: Image.file(
            File(photoPath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Immagine non disponibile.'),
              );
            },
          ),
        ),
      ),
    );
  }
}
