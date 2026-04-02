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

class ImportService {
  static const _sampleAssetPath = 'assets/sample_destinations.csv';

  ImportResult parseBytes(
    Uint8List bytes, {
    required String extension,
    required String sourceName,
  }) {
    return _parseBytes(
      bytes,
      extension: extension.replaceFirst('.', '').toLowerCase(),
      sourceName: sourceName,
    );
  }

  Future<ImportResult> importFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null) {
      return const ImportResult.cancelled();
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException(
        'Il file selezionato e\' vuoto o non leggibile.',
      );
    }

    final extension = (file.extension ?? '').toLowerCase();
    return parseBytes(bytes, extension: extension, sourceName: file.name);
  }

  Future<ImportResult> importSampleAsset() async {
    final data = await rootBundle.load(_sampleAssetPath);
    return parseBytes(
      data.buffer.asUint8List(),
      extension: 'csv',
      sourceName: 'sample_destinations.csv',
    );
  }

  ImportResult _parseBytes(
    Uint8List bytes, {
    required String extension,
    required String sourceName,
  }) {
    return switch (extension) {
      'csv' => _parseCsv(bytes, sourceName: sourceName),
      'xlsx' => _parseXlsx(bytes, sourceName: sourceName),
      _ => throw const FormatException(
        'Formato non supportato. Usa un file CSV o XLSX.',
      ),
    };
  }

  ImportResult _parseCsv(Uint8List bytes, {required String sourceName}) {
    final content = utf8
        .decode(bytes, allowMalformed: true)
        .replaceFirst('\ufeff', '');
    final delimiter = _detectCsvDelimiter(content);
    final rows = CsvToListConverter(
      shouldParseNumbers: false,
      fieldDelimiter: delimiter,
    ).convert(content);

    return _parseRows(
      rows.map(_normalizeDynamicRow).toList(growable: false),
      sourceName: sourceName,
    );
  }

  ImportResult _parseXlsx(Uint8List bytes, {required String sourceName}) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      return ImportResult(
        destinations: const <Destination>[],
        sourceName: sourceName,
        skippedRows: 0,
      );
    }

    final firstSheet = workbook.tables.values.first;
    final rows = firstSheet.rows
        .map((row) => row.map(_excelCellToString).toList(growable: false))
        .toList(growable: false);

    return _parseRows(rows, sourceName: sourceName);
  }

  ImportResult _parseRows(
    List<List<String>> rows, {
    required String sourceName,
  }) {
    final headerIndex = rows.indexWhere(
      (row) => row.any((cell) => cell.trim().isNotEmpty),
    );

    if (headerIndex == -1) {
      return ImportResult(
        destinations: const <Destination>[],
        sourceName: sourceName,
        skippedRows: 0,
      );
    }

    final headers = rows[headerIndex];
    final destinations = <Destination>[];
    var skippedRows = 0;

    for (var rowIndex = headerIndex + 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final mappedRow = <String, String>{};

      for (var columnIndex = 0; columnIndex < headers.length; columnIndex++) {
        final header = headers[columnIndex].trim();
        if (header.isEmpty) {
          continue;
        }

        final value = columnIndex < row.length ? row[columnIndex].trim() : '';
        mappedRow[header] = value;
      }

      if (mappedRow.values.every((value) => value.trim().isEmpty)) {
        skippedRows++;
        continue;
      }

      destinations.add(
        Destination.fromCsvRow(mappedRow, fallbackId: Destination.generateId()),
      );
    }

    return ImportResult(
      destinations: destinations,
      sourceName: sourceName,
      skippedRows: skippedRows,
    );
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
