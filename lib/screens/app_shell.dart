import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/destination_controller.dart';
import '../models/app_preferences.dart';
import '../models/destination.dart';
import '../services/drive_sync_service.dart';
import '../services/import_service.dart';
import '../widgets/destination_form_sheet.dart';
import 'destination_detail_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';

enum _HomeMenuAction {
  exportCsv,
  exportXlsx,
  exportBackup,
  restoreBackup,
  projectSettings,
}

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
      final controller = context.read<DestinationController>();
      final draft = await controller.pickImportDraft();
      if (!mounted || draft == null) {
        return;
      }

      if (draft.headers.isEmpty || draft.headerIndex == -1) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Il file selezionato non contiene intestazioni valide.'),
          ),
        );
        return;
      }

      final config = await _showImportMappingSheet(draft);
      if (!mounted || config == null) {
        return;
      }

      final summary = await controller.importDraft(draft, config);
      if (!mounted) {
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

  Future<void> _configureColumns() async {
    final controller = context.read<DestinationController>();
    final selectedColumns = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VisibleColumnsSheet(
        availableColumns: controller.availableColumnIds,
        initialColumns: controller.visibleColumnIds,
        columnLabelFor: controller.columnLabelFor,
      ),
    );

    if (!mounted || selectedColumns == null) {
      return;
    }

    await controller.setVisibleColumns(selectedColumns);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Colonne tabella aggiornate.')),
    );
  }

  Future<void> _saveCurrentFilter() async {
    final nameController = TextEditingController();
    final filterName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Salva filtro'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome filtro',
              hintText: 'Es. Cantieri urgenti',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(nameController.text.trim()),
              child: const Text('Salva'),
            ),
          ],
        );
      },
    );
    nameController.dispose();

    if (!mounted || filterName == null || filterName.trim().isEmpty) {
      return;
    }

    await context.read<DestinationController>().saveCurrentFilter(filterName);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Filtro "$filterName" salvato.')),
    );
  }

  Future<void> _openProjectSettings() async {
    final controller = context.read<DestinationController>();
    final result = await showDialog<_ProjectSettingsResult>(
      context: context,
      builder: (_) => _ProjectSettingsDialog(
        initialProjectName: controller.projectName,
        initialProjectColorValue: controller.projectColorValue,
        initialMarkerColorMode: controller.markerColorMode,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    await controller.updateProjectSettings(
      projectName: result.projectName,
      projectColorValue: result.projectColorValue,
      markerColorMode: result.markerColorMode,
    );

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impostazioni progetto aggiornate.')),
    );
  }

  Future<void> _exportCsv() async {
    await _runExportAction(
      action: () => context.read<DestinationController>().exportCsv(),
      successMessage: 'CSV esportato correttamente.',
      cancelledMessage: 'Esportazione CSV annullata.',
      failurePrefix: 'Esportazione CSV non riuscita',
    );
  }

  Future<void> _exportXlsx() async {
    await _runExportAction(
      action: () => context.read<DestinationController>().exportXlsx(),
      successMessage: 'XLSX esportato correttamente.',
      cancelledMessage: 'Esportazione XLSX annullata.',
      failurePrefix: 'Esportazione XLSX non riuscita',
    );
  }

  Future<void> _exportBackup() async {
    await _runExportAction(
      action: () => context.read<DestinationController>().exportBackup(),
      successMessage: 'Backup JSON salvato.',
      cancelledMessage: 'Esportazione backup annullata.',
      failurePrefix: 'Esportazione backup non riuscita',
    );
  }

  Future<void> _restoreBackup() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Ripristinare backup?'),
              content: const Text(
                'Il ripristino sostituisce i dati attuali dell’app con quelli del backup selezionato.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Continua'),
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
      final summary = await context
          .read<DestinationController>()
          .restoreFromBackup();
      if (!mounted || summary == null) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Backup ripristinato: ${summary.restoredDestinations} record caricati in ${summary.restoredProjectName}.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Ripristino backup non riuscito: $error')),
      );
    }
  }

  Future<void> _runExportAction({
    required Future<String?> Function() action,
    required String successMessage,
    required String cancelledMessage,
    required String failurePrefix,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await action();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(path == null ? cancelledMessage : successMessage)),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('$failurePrefix: $error')),
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

  Future<ImportMappingConfig?> _showImportMappingSheet(ImportDraft draft) {
    return showModalBottomSheet<ImportMappingConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ImportMappingSheet(draft: draft),
    );
  }

  Future<void> _handleHomeMenuAction(_HomeMenuAction action) async {
    switch (action) {
      case _HomeMenuAction.exportCsv:
        await _exportCsv();
      case _HomeMenuAction.exportXlsx:
        await _exportXlsx();
      case _HomeMenuAction.exportBackup:
        await _exportBackup();
      case _HomeMenuAction.restoreBackup:
        await _restoreBackup();
      case _HomeMenuAction.projectSettings:
        await _openProjectSettings();
    }
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
    final controller = context.watch<DestinationController>();
    final tabLabel = _currentIndex == 0 ? 'Destinazioni' : 'Mappa';
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
        onConfigureColumns: _configureColumns,
        onSaveFilter: _saveCurrentFilter,
      ),
      _ => MapScreen(onOpenDetail: _openDetail, onNavigate: _navigate),
    };

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text('${controller.projectName} • $tabLabel'),
        actions: _currentIndex == 0
            ? <Widget>[
                PopupMenuButton<_HomeMenuAction>(
                  onSelected: _handleHomeMenuAction,
                  itemBuilder: (context) => const <PopupMenuEntry<_HomeMenuAction>>[
                    PopupMenuItem(
                      value: _HomeMenuAction.exportCsv,
                      child: Text('Esporta CSV'),
                    ),
                    PopupMenuItem(
                      value: _HomeMenuAction.exportXlsx,
                      child: Text('Esporta XLSX'),
                    ),
                    PopupMenuItem(
                      value: _HomeMenuAction.exportBackup,
                      child: Text('Backup JSON'),
                    ),
                    PopupMenuItem(
                      value: _HomeMenuAction.restoreBackup,
                      child: Text('Ripristina backup'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _HomeMenuAction.projectSettings,
                      child: Text('Impostazioni progetto'),
                    ),
                  ],
                ),
              ]
            : <Widget>[
                IconButton(
                  tooltip: 'Impostazioni progetto',
                  onPressed: _openProjectSettings,
                  icon: const Icon(Icons.tune_outlined),
                ),
              ],
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

class _ImportMappingSheet extends StatefulWidget {
  const _ImportMappingSheet({required this.draft});

  final ImportDraft draft;

  @override
  State<_ImportMappingSheet> createState() => _ImportMappingSheetState();
}

class _ImportMappingSheetState extends State<_ImportMappingSheet> {
  late final Map<ImportTarget, String?> _mapping;
  bool _importUnmappedColumnsAsCustomFields = true;

  @override
  void initState() {
    super.initState();
    _mapping = Map<ImportTarget, String?>.from(widget.draft.suggestedMapping);
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Mapping colonne',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.draft.sourceName,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: <Widget>[
                Text(
                  'Controlla il mapping automatico e correggilo solo se serve. Le colonne non mappate possono essere importate come campi personalizzati.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _PreviewTable(draft: widget.draft),
                const SizedBox(height: 16),
                ...ImportTarget.values.map((target) {
                  final selectedHeader = widget.draft.headers.contains(
                    _mapping[target],
                  )
                      ? _mapping[target]
                      : null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String?>(
                      initialValue: selectedHeader,
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Ignora colonna'),
                        ),
                        ...widget.draft.headers.map(
                          (header) => DropdownMenuItem<String?>(
                            value: header,
                            child: Text(header),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _mapping[target] = value;
                        });
                      },
                      decoration: InputDecoration(labelText: target.label),
                    ),
                  );
                }),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _importUnmappedColumnsAsCustomFields,
                  title: const Text('Importa colonne non mappate come campi custom'),
                  onChanged: (value) {
                    setState(() {
                      _importUnmappedColumnsAsCustomFields = value;
                    });
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Annulla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          ImportMappingConfig(
                            mapping: _mapping,
                            importUnmappedColumnsAsCustomFields:
                                _importUnmappedColumnsAsCustomFields,
                          ),
                        );
                      },
                      icon: const Icon(Icons.upload_outlined),
                      label: const Text('Importa'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.draft});

  final ImportDraft draft;

  @override
  Widget build(BuildContext context) {
    final previewRows = draft.previewRows;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Anteprima',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                columns: draft.headers
                    .map((header) => DataColumn(label: Text(header)))
                    .toList(growable: false),
                rows: previewRows.map((row) {
                  return DataRow(
                    cells: draft.headers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final value = index < row.length ? row[index] : '';
                      return DataCell(
                        SizedBox(
                          width: 140,
                          child: Text(
                            value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  );
                }).toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibleColumnsSheet extends StatefulWidget {
  const _VisibleColumnsSheet({
    required this.availableColumns,
    required this.initialColumns,
    required this.columnLabelFor,
  });

  final List<String> availableColumns;
  final List<String> initialColumns;
  final String Function(String columnId) columnLabelFor;

  @override
  State<_VisibleColumnsSheet> createState() => _VisibleColumnsSheetState();
}

class _VisibleColumnsSheetState extends State<_VisibleColumnsSheet> {
  late final List<String> _selectedColumns;

  @override
  void initState() {
    super.initState();
    _selectedColumns = <String>[...widget.initialColumns];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Colonne visibili',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text('${_selectedColumns.length} attive'),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: widget.availableColumns.map((columnId) {
                  final isSelected = _selectedColumns.contains(columnId);
                  return CheckboxListTile(
                    value: isSelected,
                    title: Text(widget.columnLabelFor(columnId)),
                    subtitle: columnId.startsWith('custom:')
                        ? const Text('Campo personalizzato importato')
                        : null,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          if (!_selectedColumns.contains(columnId)) {
                            _selectedColumns.add(columnId);
                          }
                          return;
                        }

                        if (_selectedColumns.length == 1) {
                          return;
                        }
                        _selectedColumns.remove(columnId);
                      });
                    },
                  );
                }).toList(growable: false),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Annulla'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (_selectedColumns.isEmpty) {
                            return;
                          }

                          final orderedColumns = widget.availableColumns
                              .where(_selectedColumns.contains)
                              .toList(growable: false);
                          Navigator.of(context).pop(orderedColumns);
                        },
                        child: const Text('Applica'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectSettingsResult {
  const _ProjectSettingsResult({
    required this.projectName,
    required this.projectColorValue,
    required this.markerColorMode,
  });

  final String projectName;
  final int projectColorValue;
  final MarkerColorMode markerColorMode;
}

class _ProjectSettingsDialog extends StatefulWidget {
  const _ProjectSettingsDialog({
    required this.initialProjectName,
    required this.initialProjectColorValue,
    required this.initialMarkerColorMode,
  });

  final String initialProjectName;
  final int initialProjectColorValue;
  final MarkerColorMode initialMarkerColorMode;

  @override
  State<_ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<_ProjectSettingsDialog> {
  static const List<int> _colorOptions = <int>[
    0xFF146C5B,
    0xFF0E7490,
    0xFFB45309,
    0xFFBE123C,
    0xFF4F46E5,
    0xFF3F3F46,
  ];

  late final TextEditingController _projectNameController;
  late int _projectColorValue;
  late MarkerColorMode _markerColorMode;

  @override
  void initState() {
    super.initState();
    _projectNameController = TextEditingController(
      text: widget.initialProjectName,
    );
    _projectColorValue = widget.initialProjectColorValue;
    _markerColorMode = widget.initialMarkerColorMode;
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Impostazioni progetto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _projectNameController,
              decoration: const InputDecoration(labelText: 'Nome progetto'),
            ),
            const SizedBox(height: 16),
            Text(
              'Colore tema',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _colorOptions.map((colorValue) {
                final isSelected = _projectColorValue == colorValue;
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    setState(() {
                      _projectColorValue = colorValue;
                    });
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Color(colorValue),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<MarkerColorMode>(
              initialValue: _markerColorMode,
              items: MarkerColorMode.values
                  .map(
                    (mode) => DropdownMenuItem<MarkerColorMode>(
                      value: mode,
                      child: Text(mode.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _markerColorMode = value;
                });
              },
              decoration: const InputDecoration(labelText: 'Colori marker'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _ProjectSettingsResult(
                projectName: _projectNameController.text.trim(),
                projectColorValue: _projectColorValue,
                markerColorMode: _markerColorMode,
              ),
            );
          },
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
