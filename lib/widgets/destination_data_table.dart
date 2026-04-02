import 'package:flutter/material.dart';

import '../models/destination.dart';

class DestinationDataTable extends StatefulWidget {
  const DestinationDataTable({
    super.key,
    required this.destinations,
    required this.selectedDestinationId,
    required this.onRowTap,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Destination> destinations;
  final String? selectedDestinationId;
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
              constraints: const BoxConstraints(minWidth: 980),
              child: Scrollbar(
                controller: _verticalController,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.depth == 1,
                child: SingleChildScrollView(
                  controller: _verticalController,
                  child: DataTable(
                    columnSpacing: 18,
                    headingRowHeight: 44,
                    dataRowMinHeight: 62,
                    dataRowMaxHeight: 72,
                    columns: const <DataColumn>[
                      DataColumn(label: Text('Nome')),
                      DataColumn(label: Text('Indirizzo')),
                      DataColumn(label: Text('Citta\'')),
                      DataColumn(label: Text('CAP')),
                      DataColumn(label: Text('Telefono')),
                      DataColumn(label: Text('Stato')),
                      DataColumn(label: Text('Mappa')),
                      DataColumn(label: Text('Azioni')),
                    ],
                    rows: widget.destinations
                        .asMap()
                        .entries
                        .map((entry) {
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
                            onSelectChanged: (_) =>
                                widget.onRowTap(destination),
                            cells: <DataCell>[
                              DataCell(
                                SizedBox(
                                  width: 180,
                                  child: Text(
                                    destination.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Text(
                                    destination.address.isNotEmpty
                                        ? destination.address
                                        : '-',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  destination.city.isNotEmpty
                                      ? destination.city
                                      : '-',
                                ),
                              ),
                              DataCell(
                                Text(
                                  destination.postalCode.isNotEmpty
                                      ? destination.postalCode
                                      : '-',
                                ),
                              ),
                              DataCell(
                                Text(
                                  destination.phone.isNotEmpty
                                      ? destination.phone
                                      : '-',
                                ),
                              ),
                              DataCell(
                                Chip(
                                  label: Text(destination.status.label),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              DataCell(
                                destination.hasCoordinates
                                    ? const Icon(Icons.place_outlined)
                                    : const Text('Coordinate mancanti'),
                              ),
                              DataCell(
                                Row(
                                  children: <Widget>[
                                    IconButton(
                                      tooltip: 'Modifica',
                                      onPressed: () =>
                                          widget.onEdit(destination),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Elimina',
                                      onPressed: () =>
                                          widget.onDelete(destination),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
