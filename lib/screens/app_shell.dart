import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/destination_controller.dart';
import '../models/destination.dart';
import '../services/drive_sync_service.dart';
import '../widgets/destination_form_sheet.dart';
import 'destination_detail_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  Future<void> _openDestinationForm([Destination? destination]) async {
    final editedDestination = await showDestinationFormSheet(
      context,
      initialDestination: destination,
    );

    if (!mounted || editedDestination == null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final summary = await context
          .read<DestinationController>()
          .upsertDestination(editedDestination);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_buildSaveMessage(summary, isNew: destination == null)),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Salvataggio non riuscito: $error')),
      );
    }
  }

  Future<void> _openDetail(String destinationId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DestinationDetailScreen(destinationId: destinationId),
      ),
    );
  }

  Future<void> _importFromDevice() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final summary = await context
          .read<DestinationController>()
          .importFromDevice();
      if (!mounted || summary.cancelled) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_buildImportMessage(summary))),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import non riuscito: $error')),
      );
    }
  }

  Future<void> _importSample() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final summary = await context
          .read<DestinationController>()
          .importSample();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_buildImportMessage(summary))),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Import del CSV di esempio non riuscito: $error'),
        ),
      );
    }
  }

  Future<void> _linkDriveFile() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final files = await context.read<DestinationController>().listDriveFiles();
      if (!mounted || files.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Nessun file CSV/XLSX trovato in Google Drive.'),
          ),
        );
        return;
      }

      final selectedFile = await _showDriveFilePicker(files);
      if (!mounted || selectedFile == null) {
        return;
      }

      final summary = await context
          .read<DestinationController>()
          .selectDriveFileAndSync(selectedFile);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_buildDriveSyncMessage(summary, isLink: true))),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Collegamento Drive non riuscito: $error')),
      );
    }
  }

  Future<void> _syncDriveFile() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final controller = context.read<DestinationController>();
      if (controller.driveSelectedFile == null) {
        await _linkDriveFile();
        return;
      }

      final summary = await controller.syncSelectedDriveFile();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_buildDriveSyncMessage(summary))),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Sincronizzazione Drive non riuscita: $error')),
      );
    }
  }

  Future<void> _navigate(Destination destination) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<DestinationController>().navigateToDestination(
        destination,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteDestination(Destination destination) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Eliminare destinazione?'),
              content: Text(
                'La destinazione "${destination.displayName}" verrà rimossa in modo permanente.',
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

    if (!confirmed || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<DestinationController>().deleteDestination(
        destination.id,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('"${destination.displayName}" eliminata.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Eliminazione non riuscita: $error')),
      );
    }
  }

  String _buildImportMessage(ImportSummary summary) {
    final segments = <String>[
      '${summary.totalImported} record importati da ${summary.sourceName}.',
      if (summary.added > 0) '${summary.added} aggiunti',
      if (summary.updated > 0) '${summary.updated} aggiornati',
      if (summary.geocoded > 0) '${summary.geocoded} geocodificati',
      if (summary.unresolved > 0) '${summary.unresolved} senza coordinate',
      if (summary.skippedRows > 0)
        '${summary.skippedRows} righe vuote ignorate',
    ];

    return segments.join(' ');
  }

  String _buildSaveMessage(
    SaveDestinationSummary summary, {
    required bool isNew,
  }) {
    final segments = <String>[
      isNew ? 'Destinazione aggiunta.' : 'Destinazione aggiornata.',
      if (summary.wasGeocoded) 'Coordinate trovate automaticamente.',
      if (!summary.wasGeocoded &&
          summary.stillMissingCoordinates &&
          summary.hasAddressReference)
        'Indirizzo salvato, ma coordinate non trovate.',
      if (!summary.hasAddressReference && summary.stillMissingCoordinates)
        'Aggiungi un indirizzo per mostrarla in mappa.',
    ];

    return segments.join(' ');
  }

  String _buildDriveSyncMessage(
    DriveSyncSummary summary, {
    bool isLink = false,
  }) {
    final segments = <String>[
      if (isLink) 'File Drive collegato: ${summary.file.name}.',
      if (summary.wasUpToDate)
        'Nessun aggiornamento: il file non è cambiato.',
      if (!summary.wasUpToDate && summary.importSummary != null)
        _buildImportMessage(summary.importSummary!),
      if (summary.usedCachedFile)
        'Usata la copia cache locale per completare la sincronizzazione.',
    ];

    return segments.join(' ');
  }

  Future<DriveFileReference?> _showDriveFilePicker(
    List<DriveFileReference> files,
  ) {
    return showModalBottomSheet<DriveFileReference>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    'Seleziona un file da Drive',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemBuilder: (listContext, index) {
                      final file = files[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.description_outlined),
                        ),
                        title: Text(
                          file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            file.displayFormat,
                            if (file.modifiedTime != null)
                              'Aggiornato ${_formatDateTime(file.modifiedTime!)}',
                          ].join(' • '),
                        ),
                        onTap: () => Navigator.of(sheetContext).pop(file),
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemCount: files.length,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime value) {
    final localValue = value.toLocal();
    final day = localValue.day.toString().padLeft(2, '0');
    final month = localValue.month.toString().padLeft(2, '0');
    final year = localValue.year.toString();
    final hour = localValue.hour.toString().padLeft(2, '0');
    final minute = localValue.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_currentIndex) {
      0 => HomeScreen(
        onAddDestination: _openDestinationForm,
        onEditDestination: _openDestinationForm,
        onDeleteDestination: _deleteDestination,
        onOpenDetail: _openDetail,
        onImportFromDevice: _importFromDevice,
        onImportSample: _importSample,
        onLinkDrive: _linkDriveFile,
        onSyncDrive: _syncDriveFile,
      ),
      _ => MapScreen(onOpenDetail: _openDetail, onNavigate: _navigate),
    };

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Destinazioni' : 'Mappa'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: body,
        ),
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _openDestinationForm,
              icon: const Icon(Icons.add),
              label: const Text('Nuova'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.table_rows_outlined),
            selectedIcon: Icon(Icons.table_rows),
            label: 'Tabella',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mappa',
          ),
        ],
      ),
    );
  }
}
