import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../models/app_preferences.dart';
import '../models/destination.dart';

class BackupPayload {
  const BackupPayload({
    required this.destinations,
    required this.preferences,
  });

  final List<Destination> destinations;
  final AppPreferences preferences;
}

class DataExchangeService {
  Future<String?> exportCsv(List<Destination> destinations) {
    final bytes = Uint8List.fromList(_buildCsvBytes(destinations));
    return _saveBytes(
      fileName: 'mapped_destinations.csv',
      bytes: bytes,
      allowedExtensions: const <String>['csv'],
    );
  }

  Future<String?> exportXlsx(List<Destination> destinations) {
    final bytes = _buildXlsxBytes(destinations);
    return _saveBytes(
      fileName: 'mapped_destinations.xlsx',
      bytes: bytes,
      allowedExtensions: const <String>['xlsx'],
    );
  }

  Future<String?> exportBackup({
    required List<Destination> destinations,
    required AppPreferences preferences,
  }) {
    final payload = jsonEncode(<String, dynamic>{
      'version': 1,
      'destinations': destinations.map((item) => item.toJson()).toList(),
      'preferences': preferences.toJson(),
    });

    return _saveBytes(
      fileName: 'mapped_backup.json',
      bytes: Uint8List.fromList(utf8.encode(payload)),
      allowedExtensions: const <String>['json'],
    );
  }

  Future<BackupPayload?> importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Backup JSON non leggibile.');
    }

    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is! Map) {
      throw const FormatException('Backup JSON non valido.');
    }

    final mapped = decoded.map((key, value) => MapEntry(key.toString(), value));
    final rawDestinations = mapped['destinations'];
    final rawPreferences = mapped['preferences'];

    final destinations = rawDestinations is List
        ? rawDestinations
              .whereType<Map>()
              .map(
                (item) => Destination.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList(growable: false)
        : const <Destination>[];

    final preferences = rawPreferences is Map
        ? AppPreferences.fromJson(
            rawPreferences.map((key, value) => MapEntry(key.toString(), value)),
          )
        : AppPreferences.defaults();

    return BackupPayload(destinations: destinations, preferences: preferences);
  }

  Future<String?> _saveBytes({
    required String fileName,
    required Uint8List bytes,
    required List<String> allowedExtensions,
  }) {
    return FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
  }

  List<int> _buildCsvBytes(List<Destination> destinations) {
    final headers = _buildHeaders(destinations);
    final rows = <List<dynamic>>[
      headers,
      ...destinations.map((destination) => _buildRow(destination, headers)),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    return utf8.encode(csv);
  }

  Uint8List _buildXlsxBytes(List<Destination> destinations) {
    final excel = Excel.createExcel();
    final sheet = excel['Destinations'];
    final headers = _buildHeaders(destinations);
    sheet.appendRow(
      headers
          .map((value) => TextCellValue(value))
          .toList(growable: false),
    );

    for (final row in destinations.map((destination) => _buildRow(destination, headers))) {
      sheet.appendRow(
        row.map((value) => TextCellValue(value.toString())).toList(
          growable: false,
        ),
      );
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw const FormatException('Esportazione XLSX non riuscita.');
    }

    return Uint8List.fromList(bytes);
  }

  List<String> _buildHeaders(List<Destination> destinations) {
    final customHeaders = <String>{};
    for (final destination in destinations) {
      customHeaders.addAll(destination.customFields.keys);
    }

    final sortedCustomHeaders = customHeaders.toList(growable: false)
      ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));

    return <String>[
      'id',
      'name',
      'address',
      'city',
      'postalCode',
      'notes',
      'phone',
      'attachments',
      'latitude',
      'longitude',
      'status',
      'category',
      'tags',
      'dueDate',
      'checklist',
      ...sortedCustomHeaders,
    ];
  }

  List<String> _buildRow(Destination destination, List<String> headers) {
    return headers.map((header) {
      return switch (header) {
        'id' => destination.id,
        'name' => destination.name,
        'address' => destination.address,
        'city' => destination.city,
        'postalCode' => destination.postalCode,
        'notes' => destination.notes,
        'phone' => destination.phone,
        'attachments' => destination.attachmentPaths.join('|'),
        'latitude' => destination.latitude?.toString() ?? '',
        'longitude' => destination.longitude?.toString() ?? '',
        'status' => destination.status.storageValue,
        'category' => destination.category,
        'tags' => destination.tags.join('|'),
        'dueDate' => destination.dueDate?.toIso8601String().split('T').first ?? '',
        'checklist' => destination.checklistItems
            .map((item) => '${item.isDone ? '[x]' : '[ ]'} ${item.label}')
            .join('|'),
        _ => destination.customFields[header] ?? '',
      };
    }).toList(growable: false);
  }
}
