import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../models/destination.dart';

class ImportResult {
  const ImportResult({
    required this.destinations,
    required this.sourceName,
    required this.skippedRows,
    this.cancelled = false,
  });

  const ImportResult.cancelled()
    : destinations = const <Destination>[],
      sourceName = '',
      skippedRows = 0,
      cancelled = true;

  final List<Destination> destinations;
  final String sourceName;
  final int skippedRows;
  final bool cancelled;
}

enum ImportTarget {
  id('ID', 'id'),
  name('Nome', 'name'),
  address('Indirizzo', 'address'),
  city('Città', 'city'),
  postalCode('CAP', 'postalCode'),
  notes('Note', 'notes'),
  phone('Telefono', 'phone'),
  attachments('Allegati', 'attachments'),
  latitude('Latitudine', 'latitude'),
  longitude('Longitudine', 'longitude'),
  status('Stato', 'status'),
  category('Categoria', 'category'),
  tags('Tag', 'tags'),
  dueDate('Scadenza', 'dueDate'),
  checklist('Checklist', 'checklist');

  const ImportTarget(this.label, this.canonicalHeader);

  final String label;
  final String canonicalHeader;
}

class PickedImportFile {
  const PickedImportFile({
    required this.bytes,
    required this.extension,
    required this.sourceName,
  });

  final Uint8List bytes;
  final String extension;
  final String sourceName;
}

class ImportDraft {
  const ImportDraft({
    required this.rows,
    required this.headers,
    required this.sourceName,
    required this.extension,
    required this.headerIndex,
    required this.suggestedMapping,
  });

  final List<List<String>> rows;
  final List<String> headers;
  final String sourceName;
  final String extension;
  final int headerIndex;
  final Map<ImportTarget, String?> suggestedMapping;

  List<List<String>> get previewRows {
    final startIndex = headerIndex + 1;
    final endIndex = rows.length < startIndex + 4 ? rows.length : startIndex + 4;
    return rows.sublist(startIndex, endIndex);
  }
}

class ImportMappingConfig {
  const ImportMappingConfig({
    required this.mapping,
    this.importUnmappedColumnsAsCustomFields = true,
  });

  final Map<ImportTarget, String?> mapping;
  final bool importUnmappedColumnsAsCustomFields;
}

class ImportService {
  static const _sampleAssetPath = 'assets/sample_destinations.csv';

  Future<PickedImportFile?> pickImportFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException(
        'Il file selezionato è vuoto o non leggibile.',
      );
    }

    return PickedImportFile(
      bytes: bytes,
      extension: (file.extension ?? '').toLowerCase(),
      sourceName: file.name,
    );
  }

  Future<ImportResult> importFromDevice() async {
    final pickedFile = await pickImportFile();
    if (pickedFile == null) {
      return const ImportResult.cancelled();
    }

    return parseBytes(
      pickedFile.bytes,
      extension: pickedFile.extension,
      sourceName: pickedFile.sourceName,
    );
  }

  Future<ImportResult> importSampleAsset() async {
    final data = await rootBundle.load(_sampleAssetPath);
    return parseBytes(
      data.buffer.asUint8List(),
      extension: 'csv',
      sourceName: 'sample_destinations.csv',
    );
  }

  ImportResult parseBytes(
    Uint8List bytes, {
    required String extension,
    required String sourceName,
  }) {
    final draft = inspectBytes(
      bytes,
      extension: extension,
      sourceName: sourceName,
    );
    return parseDraft(
      draft,
      ImportMappingConfig(mapping: draft.suggestedMapping),
    );
  }

  ImportDraft inspectBytes(
    Uint8List bytes, {
    required String extension,
    required String sourceName,
  }) {
    final normalizedExtension = extension.replaceFirst('.', '').toLowerCase();
    final rows = switch (normalizedExtension) {
      'csv' => _parseCsvRows(bytes),
      'xlsx' => _parseXlsxRows(bytes),
      _ => throw const FormatException(
          'Formato non supportato. Usa un file CSV o XLSX.',
        ),
    };

    final headerIndex = rows.indexWhere(
      (row) => row.any((cell) => cell.trim().isNotEmpty),
    );

    if (headerIndex == -1) {
      return ImportDraft(
        rows: rows,
        headers: const <String>[],
        sourceName: sourceName,
        extension: normalizedExtension,
        headerIndex: -1,
        suggestedMapping: const <ImportTarget, String?>{},
      );
    }

    final headers = rows[headerIndex];
    final suggestedMapping = <ImportTarget, String?>{
      for (final target in ImportTarget.values) target: _detectHeader(headers, target),
    };

    return ImportDraft(
      rows: rows,
      headers: headers,
      sourceName: sourceName,
      extension: normalizedExtension,
      headerIndex: headerIndex,
      suggestedMapping: suggestedMapping,
    );
  }

  ImportResult parseDraft(ImportDraft draft, ImportMappingConfig config) {
    if (draft.headerIndex == -1 || draft.headers.isEmpty) {
      return ImportResult(
        destinations: const <Destination>[],
        sourceName: draft.sourceName,
        skippedRows: 0,
      );
    }

    final destinations = <Destination>[];
    var skippedRows = 0;
    final mappedSourceHeaders = config.mapping.values
        .whereType<String>()
        .map(normalizeToken)
        .toSet();

    for (var rowIndex = draft.headerIndex + 1;
        rowIndex < draft.rows.length;
        rowIndex++) {
      final row = draft.rows[rowIndex];
      final sourceRow = <String, String>{};

      for (var columnIndex = 0; columnIndex < draft.headers.length; columnIndex++) {
        final header = draft.headers[columnIndex].trim();
        if (header.isEmpty) {
          continue;
        }
        final value = columnIndex < row.length ? row[columnIndex].trim() : '';
        sourceRow[header] = value;
      }

      if (sourceRow.values.every((value) => value.trim().isEmpty)) {
        skippedRows++;
        continue;
      }

      final mappedRow = <String, String>{};
      for (final target in ImportTarget.values) {
        final sourceHeader = config.mapping[target];
        if (sourceHeader == null || sourceHeader.trim().isEmpty) {
          continue;
        }
        mappedRow[target.canonicalHeader] = sourceRow[sourceHeader]?.trim() ?? '';
      }

      if (config.importUnmappedColumnsAsCustomFields) {
        for (final entry in sourceRow.entries) {
          if (mappedSourceHeaders.contains(normalizeToken(entry.key))) {
            continue;
          }
          mappedRow[entry.key] = entry.value;
        }
      }

      destinations.add(
        Destination.fromCsvRow(mappedRow, fallbackId: Destination.generateId()),
      );
    }

    return ImportResult(
      destinations: destinations,
      sourceName: draft.sourceName,
      skippedRows: skippedRows,
    );
  }

  List<List<String>> _parseCsvRows(Uint8List bytes) {
    final content = utf8
        .decode(bytes, allowMalformed: true)
        .replaceFirst('\ufeff', '');
    final delimiter = _detectCsvDelimiter(content);
    final rows = CsvToListConverter(
      shouldParseNumbers: false,
      fieldDelimiter: delimiter,
    ).convert(content);
    return rows.map(_normalizeDynamicRow).toList(growable: false);
  }

  List<List<String>> _parseXlsxRows(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      return const <List<String>>[];
    }

    final firstSheet = workbook.tables.values.first;
    return firstSheet.rows
        .map((row) => row.map(_excelCellToString).toList(growable: false))
        .toList(growable: false);
  }

  String? _detectHeader(List<String> headers, ImportTarget target) {
    final aliases = _aliasesFor(target);
    for (final header in headers) {
      if (aliases.contains(normalizeToken(header))) {
        return header;
      }
    }
    return null;
  }

  Set<String> _aliasesFor(ImportTarget target) {
    return switch (target) {
      ImportTarget.id => {'id', 'codice', 'identifier'},
      ImportTarget.name => {'name', 'nome', 'ragionesociale', 'cliente'},
      ImportTarget.address => {'address', 'indirizzo', 'street', 'via'},
      ImportTarget.city => {'city', 'citta', 'comune'},
      ImportTarget.postalCode => {'postalcode', 'postal', 'cap', 'zip', 'zipcode'},
      ImportTarget.notes => {'notes', 'note', 'descrizione', 'description'},
      ImportTarget.phone => {'phone', 'telefono', 'tel', 'mobile', 'cellulare'},
      ImportTarget.attachments => {'attachments', 'allegati', 'files', 'file', 'photo', 'foto'},
      ImportTarget.latitude => {'lat', 'latitude', 'latitudine'},
      ImportTarget.longitude => {'lng', 'lon', 'long', 'longitude', 'longitudine'},
      ImportTarget.status => {'status', 'stato'},
      ImportTarget.category => {'category', 'categoria', 'tipo', 'tipologia'},
      ImportTarget.tags => {'tags', 'tag', 'etichette'},
      ImportTarget.dueDate => {'duedate', 'deadline', 'scadenza', 'data'},
      ImportTarget.checklist => {'checklist', 'tasks', 'todo', 'attivita'},
    };
  }

  String _detectCsvDelimiter(String content) {
    final firstLine = content
        .split(RegExp(r'\r\n|\n|\r'))
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');

    final commaCount = ','.allMatches(firstLine).length;
    final semicolonCount = ';'.allMatches(firstLine).length;
    return semicolonCount > commaCount ? ';' : ',';
  }

  List<String> _normalizeDynamicRow(List<dynamic> row) {
    return row.map((value) => value?.toString() ?? '').toList(growable: false);
  }

  String _excelCellToString(Data? cell) {
    final value = cell?.value;

    return switch (value) {
      null => '',
      TextCellValue(value: final text) => text.toString(),
      FormulaCellValue(formula: final formula) => formula.toString(),
      IntCellValue(value: final number) => number.toString(),
      DoubleCellValue(value: final number) => number.toString(),
      BoolCellValue(value: final boolean) => boolean.toString(),
      DateCellValue() => value.asDateTimeLocal().toIso8601String(),
      TimeCellValue() => value.asDuration().toString(),
      DateTimeCellValue() => value.asDateTimeLocal().toIso8601String(),
    };
  }
}
