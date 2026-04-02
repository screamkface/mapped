import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/destination_controller.dart';
import '../models/destination.dart';
import '../services/drive_sync_service.dart';
import '../widgets/destination_data_table.dart';

class HomeScreen extends StatelessWidget {
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
  });

  final Future<void> Function() onAddDestination;
  final Future<void> Function(Destination destination) onEditDestination;
  final Future<void> Function(Destination destination) onDeleteDestination;
  final Future<void> Function(String destinationId) onOpenDetail;
  final Future<void> Function() onImportFromDevice;
  final Future<void> Function() onImportSample;
  final Future<void> Function() onLinkDrive;
  final Future<void> Function() onSyncDrive;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DestinationController>();
    final destinations = controller.visibleDestinations;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final tableHeight = (availableHeight * 0.48).clamp(260.0, 520.0);

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
                  onLinkDrive: onLinkDrive,
                  onSyncDrive: onSyncDrive,
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
                              onPressed: onImportFromDevice,
                              icon: const Icon(Icons.upload_file_outlined),
                              label: const Text('Importa CSV/XLSX'),
                            ),
                            TextButton.icon(
                              onPressed: onImportSample,
                              icon: const Icon(Icons.description_outlined),
                              label: const Text('Carica esempio'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: onAddDestination,
                              icon: const Icon(Icons.add),
                              label: const Text('Nuova riga'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: controller.searchQuery,
                          decoration: const InputDecoration(
                            hintText: 'Cerca per nome o indirizzo',
                            prefixIcon: Icon(Icons.search),
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
                          onRowTap: (destination) async {
                            controller.selectDestination(destination.id);
                            await onOpenDetail(destination.id);
                          },
                          onEdit: (destination) async {
                            controller.selectDestination(destination.id);
                            await onEditDestination(destination);
                          },
                          onDelete: onDeleteDestination,
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
                    label: 'Record',
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
            Text(
              _buildDescription(),
              style: theme.textTheme.bodyMedium,
            ),
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
              Text(
                'Account: $accountEmail',
                style: theme.textTheme.bodySmall,
              ),
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
