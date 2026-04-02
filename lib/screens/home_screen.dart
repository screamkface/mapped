import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/destination_controller.dart';
import '../models/app_preferences.dart';
import '../models/destination.dart';
import '../services/drive_sync_service.dart';
import '../widgets/destination_data_table.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onAddDestination,
    required this.onEditDestination,
    required this.onDeleteDestination,
    required this.onOpenDetail,
    required this.onImportFromDevice,
    required this.onImportSample,
    required this.onLinkDrive,
    required this.onSyncDrive,
    required this.onConfigureColumns,
    required this.onSaveFilter,
  });

  final Future<void> Function() onAddDestination;
  final Future<void> Function(Destination destination) onEditDestination;
  final Future<void> Function(Destination destination) onDeleteDestination;
  final Future<void> Function(String destinationId) onOpenDetail;
  final Future<void> Function() onImportFromDevice;
  final Future<void> Function() onImportSample;
  final Future<void> Function() onLinkDrive;
  final Future<void> Function() onSyncDrive;
  final Future<void> Function() onConfigureColumns;
  final Future<void> Function() onSaveFilter;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DestinationController>();
    final destinations = controller.visibleDestinations;
    final categories = controller.knownCategories;
    final tags = controller.knownTags;
    final selectedCategory = categories.contains(controller.categoryFilter)
        ? controller.categoryFilter
        : '';
    final selectedTag = tags.contains(controller.tagFilter)
        ? controller.tagFilter
        : '';

    if (_searchController.text != controller.searchQuery) {
      _searchController.value = TextEditingValue(
        text: controller.searchQuery,
        selection: TextSelection.collapsed(
          offset: controller.searchQuery.length,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final tableHeight = (availableHeight * 0.48).clamp(280.0, 560.0);

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 96),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _SummaryCard(controller: controller),
                const SizedBox(height: 12),
                _DriveSyncCard(
                  isConfigured: controller.isDriveConfigured,
                  isBusy: controller.isDriveBusy,
                  selectedFile: controller.driveSelectedFile,
                  accountEmail: controller.driveAccountEmail,
                  lastSyncAt: controller.driveLastSyncAt,
                  onLinkDrive: widget.onLinkDrive,
                  onSyncDrive: widget.onSyncDrive,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: widget.onImportFromDevice,
                              icon: const Icon(Icons.upload_file_outlined),
                              label: const Text('Importa CSV/XLSX'),
                            ),
                            TextButton.icon(
                              onPressed: widget.onImportSample,
                              icon: const Icon(Icons.description_outlined),
                              label: const Text('Carica esempio'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: widget.onConfigureColumns,
                              icon: const Icon(Icons.view_column_outlined),
                              label: const Text('Colonne'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: widget.onSaveFilter,
                              icon: const Icon(Icons.bookmark_add_outlined),
                              label: const Text('Salva filtro'),
                            ),
                            FilledButton.icon(
                              onPressed: widget.onAddDestination,
                              icon: const Icon(Icons.add),
                              label: const Text('Nuova riga'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Cerca per nome, indirizzo, categoria o campi custom',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: controller.searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      controller.updateSearchQuery('');
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                          onChanged: controller.updateSearchQuery,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: DestinationStatusFilter.values
                              .map((filter) {
                                final isSelected =
                                    controller.statusFilter == filter;
                                return ChoiceChip(
                                  label: Text(filter.label),
                                  selected: isSelected,
                                  onSelected: (_) =>
                                      controller.updateStatusFilter(filter),
                                );
                              })
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveFilterRow(
                          categoryValue: selectedCategory,
                          tagValue: selectedTag,
                          categories: categories,
                          tags: tags,
                          onCategoryChanged: (value) =>
                              controller.updateCategoryFilter(value ?? ''),
                          onTagChanged: (value) =>
                              controller.updateTagFilter(value ?? ''),
                        ),
                        const SizedBox(height: 12),
                        _SortRow(controller: controller),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            if (controller.savedFilters.isNotEmpty)
                              ...controller.savedFilters.map(
                                (filter) => InputChip(
                                  label: Text(filter.name),
                                  onPressed: () {
                                    controller.applySavedFilter(filter);
                                    _searchController.value = TextEditingValue(
                                      text: controller.searchQuery,
                                      selection: TextSelection.collapsed(
                                        offset: controller.searchQuery.length,
                                      ),
                                    );
                                  },
                                  onDeleted: () {
                                    controller.deleteSavedFilter(filter.id);
                                  },
                                ),
                              ),
                            if (controller.savedFilters.isEmpty)
                              Text(
                                'Nessun filtro salvato. Salva le combinazioni che usi più spesso.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        if (controller.searchQuery.isNotEmpty ||
                            controller.statusFilter !=
                                DestinationStatusFilter.all ||
                            controller.categoryFilter.isNotEmpty ||
                            controller.tagFilter.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                controller.clearFilters();
                              },
                              icon: const Icon(Icons.filter_alt_off_outlined),
                              label: const Text('Azzera filtri'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: tableHeight,
                  child: destinations.isEmpty
                      ? const _EmptyState()
                      : DestinationDataTable(
                          destinations: destinations,
                          selectedDestinationId:
                              controller.selectedDestinationId,
                          visibleColumnIds: controller.visibleColumnIds,
                          currentSortField: controller.sortField,
                          sortAscending: controller.sortAscending,
                          columnLabelFor: controller.columnLabelFor,
                          sortFieldForColumn: controller.sortFieldForColumn,
                          onSortColumn: controller.sortByColumn,
                          onRowTap: (destination) async {
                            controller.selectDestination(destination.id);
                            await widget.onOpenDetail(destination.id);
                          },
                          onEdit: (destination) async {
                            controller.selectDestination(destination.id);
                            await widget.onEditDestination(destination);
                          },
                          onDelete: widget.onDeleteDestination,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.controller});

  final DestinationController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCount = controller.visibleDestinations.length;
    final mappedCount = controller.mappableDestinations.length;
    final missingCount = controller.missingCoordinatesCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 480
                ? 2
                : 1;
            const spacing = 12.0;
            final tileWidth =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: <Widget>[
                SizedBox(
                  width: tileWidth,
                  child: _MetricTile(
                    label: 'Record visibili',
                    value: '$visibleCount',
                    color: theme.colorScheme.primaryContainer,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _MetricTile(
                    label: 'In mappa',
                    value: '$mappedCount',
                    color: const Color(0xFFDDF4E8),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _MetricTile(
                    label: 'Senza coord.',
                    value: '$missingCount',
                    color: const Color(0xFFFFE8CC),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _ResponsiveFilterRow extends StatelessWidget {
  const _ResponsiveFilterRow({
    required this.categoryValue,
    required this.tagValue,
    required this.categories,
    required this.tags,
    required this.onCategoryChanged,
    required this.onTagChanged,
  });

  final String categoryValue;
  final String tagValue;
  final List<String> categories;
  final List<String> tags;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onTagChanged;

  @override
  Widget build(BuildContext context) {
    final categoryField = DropdownButtonFormField<String>(
      initialValue: categoryValue.isEmpty ? '' : categoryValue,
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem(value: '', child: Text('Tutte le categorie')),
        ...categories.map(
          (category) => DropdownMenuItem(value: category, child: Text(category)),
        ),
      ],
      onChanged: onCategoryChanged,
      decoration: const InputDecoration(labelText: 'Categoria'),
    );

    final tagField = DropdownButtonFormField<String>(
      initialValue: tagValue.isEmpty ? '' : tagValue,
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem(value: '', child: Text('Tutti i tag')),
        ...tags.map((tag) => DropdownMenuItem(value: tag, child: Text(tag))),
      ],
      onChanged: onTagChanged,
      decoration: const InputDecoration(labelText: 'Tag'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 540) {
          return Column(
            children: <Widget>[
              categoryField,
              const SizedBox(height: 12),
              tagField,
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(child: categoryField),
            const SizedBox(width: 12),
            Expanded(child: tagField),
          ],
        );
      },
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({required this.controller});

  final DestinationController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: DropdownButtonFormField<DestinationSortField>(
            initialValue: controller.sortField,
            items: DestinationSortField.values
                .map(
                  (field) => DropdownMenuItem<DestinationSortField>(
                    value: field,
                    child: Text(field.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              controller.updateSorting(
                sortField: value,
                sortAscending: controller.sortAscending,
              );
            },
            decoration: const InputDecoration(labelText: 'Ordina per'),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: () {
            controller.updateSorting(
              sortField: controller.sortField,
              sortAscending: !controller.sortAscending,
            );
          },
          icon: Icon(
            controller.sortAscending
                ? Icons.arrow_upward_outlined
                : Icons.arrow_downward_outlined,
          ),
          label: Text(controller.sortAscending ? 'A-Z' : 'Z-A'),
        ),
      ],
    );
  }
}

class _DriveSyncCard extends StatelessWidget {
  const _DriveSyncCard({
    required this.isConfigured,
    required this.isBusy,
    required this.selectedFile,
    required this.accountEmail,
    required this.lastSyncAt,
    required this.onLinkDrive,
    required this.onSyncDrive,
  });

  final bool isConfigured;
  final bool isBusy;
  final DriveFileReference? selectedFile;
  final String? accountEmail;
  final DateTime? lastSyncAt;
  final Future<void> Function() onLinkDrive;
  final Future<void> Function() onSyncDrive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.cloud_sync_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Google Drive',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_buildDescription(), style: theme.textTheme.bodyMedium),
            if (selectedFile != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'File collegato: ${selectedFile!.name}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (accountEmail != null && accountEmail!.trim().isNotEmpty) ...<
              Widget
            >[
              const SizedBox(height: 4),
              Text('Account: $accountEmail', style: theme.textTheme.bodySmall),
            ],
            if (lastSyncAt != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Ultimo controllo: ${_formatDateTime(lastSyncAt!)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: isBusy ? null : onLinkDrive,
                  icon: const Icon(Icons.link_outlined),
                  label: Text(
                    selectedFile == null ? 'Collega Drive' : 'Cambia file',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy || selectedFile == null ? null : onSyncDrive,
                  icon: const Icon(Icons.sync_outlined),
                  label: const Text('Sincronizza'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildDescription() {
    if (!isConfigured) {
      return 'Configura GOOGLE_DRIVE_SERVER_CLIENT_ID per collegare un file CSV/XLSX da Drive.';
    }
    if (selectedFile == null) {
      return 'Collega un file Excel/CSV da Google Drive e l’app lo sincronizzerà anche ai riavvii.';
    }
    return 'L’app controlla se il file è cambiato e importa solo quando trova una versione nuova.';
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.location_off_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Nessuna destinazione trovata',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Aggiungi una riga manualmente oppure importa un CSV/XLSX per iniziare.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
