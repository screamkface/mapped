import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_preferences.dart';
import '../models/destination.dart';

class DestinationDataTable extends StatefulWidget {
  const DestinationDataTable({
    super.key,
    required this.destinations,
    required this.selectedDestinationId,
    required this.visibleColumnIds,
    required this.currentSortField,
    required this.sortAscending,
    required this.columnLabelFor,
    required this.sortFieldForColumn,
    required this.onSortColumn,
    required this.onRowTap,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Destination> destinations;
  final String? selectedDestinationId;
  final List<String> visibleColumnIds;
  final DestinationSortField currentSortField;
  final bool sortAscending;
  final String Function(String columnId) columnLabelFor;
  final DestinationSortField? Function(String columnId) sortFieldForColumn;
  final Future<void> Function(String columnId) onSortColumn;
  final Future<void> Function(Destination destination) onRowTap;
  final Future<void> Function(Destination destination) onEdit;
  final Future<void> Function(Destination destination) onDelete;

  @override
  State<DestinationDataTable> createState() => _DestinationDataTableState();
}

class _DestinationDataTableState extends State<DestinationDataTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sortColumnIndex = widget.visibleColumnIds.indexWhere(
      (columnId) => widget.sortFieldForColumn(columnId) == widget.currentSortField,
    );
    final minTableWidth = math.max(
      980.0,
      widget.visibleColumnIds.length * 150.0 + 160.0,
    );

    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          notificationPredicate: (notification) => notification.depth == 0,
          child: SingleChildScrollView(
            controller: _horizontalController,
            padding: const EdgeInsets.all(8),
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minTableWidth),
              child: Scrollbar(
                controller: _verticalController,
                thumbVisibility: true,
                notificationPredicate: (notification) => notification.depth == 1,
                child: SingleChildScrollView(
                  controller: _verticalController,
                  child: DataTable(
                    sortAscending: widget.sortAscending,
                    sortColumnIndex: sortColumnIndex >= 0 ? sortColumnIndex : null,
                    columnSpacing: 18,
                    headingRowHeight: 44,
                    dataRowMinHeight: 62,
                    dataRowMaxHeight: 84,
                    columns: <DataColumn>[
                      ...widget.visibleColumnIds.asMap().entries.map((entry) {
                        final columnId = entry.value;
                        final sortField = widget.sortFieldForColumn(columnId);
                        return DataColumn(
                          onSort: sortField == null
                              ? null
                              : (_, __) => widget.onSortColumn(columnId),
                          label: SizedBox(
                            width: _columnWidthFor(columnId),
                            child: Text(widget.columnLabelFor(columnId)),
                          ),
                        );
                      }),
                      const DataColumn(label: Text('Azioni')),
                    ],
                    rows: widget.destinations.asMap().entries.map((entry) {
                      final destination = entry.value;
                      final isSelected =
                          destination.id == widget.selectedDestinationId;

                      return DataRow.byIndex(
                        index: entry.key,
                        color: WidgetStateProperty.resolveWith((states) {
                          if (isSelected) {
                            return Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.35);
                          }
                          return null;
                        }),
                        onSelectChanged: (_) => widget.onRowTap(destination),
                        cells: <DataCell>[
                          ...widget.visibleColumnIds.map(
                            (columnId) => DataCell(
                              SizedBox(
                                width: _columnWidthFor(columnId),
                                child: _buildCell(context, destination, columnId),
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  tooltip: 'Modifica',
                                  onPressed: () => widget.onEdit(destination),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Elimina',
                                  onPressed: () => widget.onDelete(destination),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(growable: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _columnWidthFor(String columnId) {
    return switch (columnId) {
      'id' => 180,
      'name' => 180,
      'address' => 220,
      'notes' => 220,
      'tags' => 170,
      _ when columnId.startsWith('custom:') => 170,
      _ => 140,
    };
  }

  Widget _buildCell(BuildContext context, Destination destination, String columnId) {
    if (columnId.startsWith('custom:')) {
      final key = columnId.substring('custom:'.length);
      return Text(
        destination.customFields[key] ?? '-',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return switch (columnId) {
      'id' => Text(destination.id, maxLines: 1, overflow: TextOverflow.ellipsis),
      'name' => Text(
          destination.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      'address' => Text(
          destination.address.isNotEmpty ? destination.address : '-',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      'city' => Text(destination.city.isNotEmpty ? destination.city : '-'),
      'postalCode' => Text(
          destination.postalCode.isNotEmpty ? destination.postalCode : '-',
        ),
      'phone' => Text(destination.phone.isNotEmpty ? destination.phone : '-'),
      'category' => Text(
          destination.category.isNotEmpty ? destination.category : '-',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      'tags' => destination.tags.isEmpty
          ? const Text('-')
          : Text(
              destination.tags.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      'status' => Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            label: Text(destination.status.label),
            visualDensity: VisualDensity.compact,
          ),
        ),
      'dueDate' => Text(_formatDueDate(destination.dueDate)),
      'map' => destination.hasCoordinates
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.place_outlined, size: 18),
                SizedBox(width: 6),
                Flexible(child: Text('Marker')),
              ],
            )
          : const Text('Coordinate mancanti'),
      'attachments' => Text(
          destination.attachmentPaths.isEmpty
              ? '-'
              : '${destination.attachmentPaths.length} allegati',
        ),
      'notes' => Text(
          destination.notes.isNotEmpty ? destination.notes : '-',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      _ => Text(widget.columnLabelFor(columnId)),
    };
  }

  String _formatDueDate(DateTime? dueDate) {
    if (dueDate == null) {
      return '-';
    }

    final localDate = dueDate.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final year = localDate.year.toString();
    return '$day/$month/$year';
  }
}
