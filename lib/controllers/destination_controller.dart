import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/app_preferences.dart';
import '../models/destination.dart';
import '../services/app_preferences_service.dart';
import '../services/data_exchange_service.dart';
import '../services/destination_photo_service.dart';
import '../services/destination_storage_service.dart';
import '../services/drive_sync_service.dart';
import '../services/geocoding_service.dart';
import '../services/import_service.dart';
import '../services/navigation_service.dart';

class ImportSummary {
  const ImportSummary({
    required this.sourceName,
    required this.added,
    required this.updated,
    required this.skippedRows,
    required this.geocoded,
    required this.unresolved,
    this.cancelled = false,
  });

  const ImportSummary.cancelled()
    : sourceName = '',
      added = 0,
      updated = 0,
      skippedRows = 0,
      geocoded = 0,
      unresolved = 0,
      cancelled = true;

  final String sourceName;
  final int added;
  final int updated;
  final int skippedRows;
  final int geocoded;
  final int unresolved;
  final bool cancelled;

  int get totalImported => added + updated;
}

class SaveDestinationSummary {
  const SaveDestinationSummary({
    required this.destination,
    required this.wasGeocoded,
    required this.stillMissingCoordinates,
    required this.hasAddressReference,
  });

  final Destination destination;
  final bool wasGeocoded;
  final bool stillMissingCoordinates;
  final bool hasAddressReference;
}

class DriveSyncSummary {
  const DriveSyncSummary({
    required this.file,
    required this.wasUpToDate,
    required this.usedCachedFile,
    this.importSummary,
  });

  final DriveFileReference file;
  final ImportSummary? importSummary;
  final bool wasUpToDate;
  final bool usedCachedFile;
}

class RestoreSummary {
  const RestoreSummary({
    required this.restoredDestinations,
    required this.restoredProjectName,
  });

  final int restoredDestinations;
  final String restoredProjectName;
}

class DestinationController extends ChangeNotifier {
  DestinationController({
    required DestinationStorageService storageService,
    required AppPreferencesService preferencesService,
    required DestinationPhotoService photoService,
    required DriveSyncService driveSyncService,
    required ImportService importService,
    required NavigationService navigationService,
    required GeocodingService geocodingService,
    required DataExchangeService dataExchangeService,
  }) : _storageService = storageService,
       _preferencesService = preferencesService,
       _photoService = photoService,
       _driveSyncService = driveSyncService,
       _importService = importService,
       _navigationService = navigationService,
       _geocodingService = geocodingService,
       _dataExchangeService = dataExchangeService;

  final DestinationStorageService _storageService;
  final AppPreferencesService _preferencesService;
  final DestinationPhotoService _photoService;
  final DriveSyncService _driveSyncService;
  final ImportService _importService;
  final NavigationService _navigationService;
  final GeocodingService _geocodingService;
  final DataExchangeService _dataExchangeService;

  List<Destination> _destinations = <Destination>[];
  AppPreferences _preferences = AppPreferences.defaults();
  String _searchQuery = '';
  DestinationStatusFilter _statusFilter = DestinationStatusFilter.all;
  String _categoryFilter = '';
  String _tagFilter = '';
  String? _selectedDestinationId;
  bool _isDriveBusy = false;
  DriveFileReference? _driveSelectedFile;
  String? _driveAccountEmail;
  DateTime? _driveLastSyncAt;

  List<Destination> get destinations => List.unmodifiable(_destinations);
  String get searchQuery => _searchQuery;
  DestinationStatusFilter get statusFilter => _statusFilter;
  String get categoryFilter => _categoryFilter;
  String get tagFilter => _tagFilter;
  String? get selectedDestinationId => _selectedDestinationId;
  bool get isDriveBusy => _isDriveBusy;
  bool get isDriveConfigured => _driveSyncService.isConfigured;
  DriveFileReference? get driveSelectedFile => _driveSelectedFile;
  String? get driveAccountEmail => _driveAccountEmail;
  DateTime? get driveLastSyncAt => _driveLastSyncAt;
  String get projectName => _preferences.projectName;
  Color get projectColor => Color(_preferences.projectColorValue);
  int get projectColorValue => _preferences.projectColorValue;
  DestinationSortField get sortField => _preferences.sortField;
  bool get sortAscending => _preferences.sortAscending;
  MarkerColorMode get markerColorMode => _preferences.markerColorMode;
  List<String> get visibleColumnIds => List.unmodifiable(
    _sanitizeVisibleColumns(_preferences.visibleColumns),
  );
  List<SavedFilterPreset> get savedFilters => List.unmodifiable(
    _preferences.savedFilters,
  );

  Destination? get selectedDestination {
    final id = _selectedDestinationId;
    if (id == null) {
      return null;
    }
    return findById(id);
  }

  List<Destination> get visibleDestinations {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _destinations.where((destination) {
      final matchesCustomField = destination.customFields.entries.any(
        (entry) =>
            entry.key.toLowerCase().contains(query) ||
            entry.value.toLowerCase().contains(query),
      );
      final matchesQuery =
          query.isEmpty ||
          destination.displayName.toLowerCase().contains(query) ||
          destination.address.toLowerCase().contains(query) ||
          destination.fullAddress.toLowerCase().contains(query) ||
          destination.city.toLowerCase().contains(query) ||
          destination.category.toLowerCase().contains(query) ||
          destination.tags.any((tag) => tag.toLowerCase().contains(query)) ||
          matchesCustomField;

      if (!matchesQuery) {
        return false;
      }

      final matchesStatus = switch (_statusFilter) {
        DestinationStatusFilter.all => true,
        DestinationStatusFilter.pending =>
          destination.status == DestinationStatus.pending,
        DestinationStatusFilter.completed =>
          destination.status == DestinationStatus.completed,
      };

      if (!matchesStatus) {
        return false;
      }

      if (_categoryFilter.trim().isNotEmpty &&
          destination.category.toLowerCase() != _categoryFilter.toLowerCase()) {
        return false;
      }

      if (_tagFilter.trim().isNotEmpty &&
          !destination.tags.any(
            (tag) => tag.toLowerCase() == _tagFilter.toLowerCase(),
          )) {
        return false;
      }

      return true;
    }).toList(growable: false);

    filtered.sort(_compareDestinations);
    return filtered;
  }

  List<Destination> get mappableDestinations => visibleDestinations
      .where((destination) => destination.hasCoordinates)
      .toList(growable: false);

  int get missingCoordinatesCount => visibleDestinations
      .where((destination) => !destination.hasCoordinates)
      .length;

  List<String> get knownCategories {
    final values = _destinations
        .map((item) => item.category.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
    return values;
  }

  List<String> get knownTags {
    final values = _destinations
        .expand((item) => item.tags)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
    return values;
  }

  List<String> get availableCustomFieldKeys {
    final values = _destinations
        .expand((item) => item.customFields.keys)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
    return values;
  }

  List<String> get availableColumnIds {
    return <String>[
      'id',
      'name',
      'address',
      'city',
      'postalCode',
      'phone',
      'category',
      'tags',
      'status',
      'dueDate',
      'map',
      'attachments',
      'notes',
      ...availableCustomFieldKeys.map((key) => 'custom:$key'),
    ];
  }

  Future<void> initialize() async {
    _destinations = await _storageService.loadDestinations();
    _preferences = await _preferencesService.loadPreferences();
    _destinations.sort(_compareDestinations);
    await _driveSyncService.initialize();
    _refreshDriveState();
    notifyListeners();
    unawaited(_attemptInitialDriveSync());
  }

  Future<SaveDestinationSummary> upsertDestination(
    Destination destination,
  ) async {
    final previousDestination = findById(destination.id);
    final geocodingResult = await _geocodingService.fillCoordinatesIfNeeded(
      destination,
    );
    final resolvedDestination = geocodingResult.destination;

    final index = _destinations.indexWhere(
      (item) => item.id == resolvedDestination.id,
    );
    if (index == -1) {
      _destinations.add(resolvedDestination);
    } else {
      _destinations[index] = resolvedDestination;
    }

    _selectedDestinationId = resolvedDestination.id;
    _destinations.sort(_compareDestinations);
    await _persistDestinations();
    await _cleanupRemovedAttachments(
      previousDestination?.attachmentPaths ?? const <String>[],
      resolvedDestination.attachmentPaths,
    );

    return SaveDestinationSummary(
      destination: resolvedDestination,
      wasGeocoded: geocodingResult.wasGeocoded,
      stillMissingCoordinates: geocodingResult.stillMissingCoordinates,
      hasAddressReference: geocodingResult.hasAddressReference,
    );
  }

  Future<void> deleteDestination(String destinationId) async {
    final existingDestination = findById(destinationId);
    _destinations.removeWhere((destination) => destination.id == destinationId);
    if (_selectedDestinationId == destinationId) {
      _selectedDestinationId = null;
    }
    await _persistDestinations();
    await _photoService.deletePhotos(
      existingDestination?.attachmentPaths ?? const <String>[],
    );
  }

  void updateSearchQuery(String value) {
    _searchQuery = value.trim();
    notifyListeners();
  }

  void updateStatusFilter(DestinationStatusFilter value) {
    if (_statusFilter == value) {
      return;
    }
    _statusFilter = value;
    notifyListeners();
  }

  void updateCategoryFilter(String value) {
    _categoryFilter = value.trim();
    notifyListeners();
  }

  void updateTagFilter(String value) {
    _tagFilter = value.trim();
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _statusFilter = DestinationStatusFilter.all;
    _categoryFilter = '';
    _tagFilter = '';
    notifyListeners();
  }

  Future<void> saveCurrentFilter(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return;
    }

    final updatedFilters = <SavedFilterPreset>[
      ..._preferences.savedFilters,
      SavedFilterPreset.create(
        name: trimmedName,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        category: _categoryFilter,
        tag: _tagFilter,
      ),
    ];

    _preferences = _preferences.copyWith(savedFilters: updatedFilters);
    await _persistPreferences();
  }

  Future<void> deleteSavedFilter(String filterId) async {
    _preferences = _preferences.copyWith(
      savedFilters: _preferences.savedFilters
          .where((item) => item.id != filterId)
          .toList(growable: false),
    );
    await _persistPreferences();
  }

  void applySavedFilter(SavedFilterPreset preset) {
    _searchQuery = preset.searchQuery;
    _statusFilter = preset.statusFilter;
    _categoryFilter = preset.category;
    _tagFilter = preset.tag;
    notifyListeners();
  }

  void selectDestination(String? destinationId) {
    if (_selectedDestinationId == destinationId) {
      return;
    }
    _selectedDestinationId = destinationId;
    notifyListeners();
  }

  Destination? findById(String destinationId) {
    for (final destination in _destinations) {
      if (destination.id == destinationId) {
        return destination;
      }
    }
    return null;
  }

  Future<ImportSummary> importFromDevice() async {
    final result = await _importService.importFromDevice();
    if (result.cancelled) {
      return const ImportSummary.cancelled();
    }
    return _applyImportResult(result);
  }

  Future<ImportDraft?> pickImportDraft() async {
    final pickedFile = await _importService.pickImportFile();
    if (pickedFile == null) {
      return null;
    }

    return _importService.inspectBytes(
      pickedFile.bytes,
      extension: pickedFile.extension,
      sourceName: pickedFile.sourceName,
    );
  }

  Future<ImportSummary> importDraft(
    ImportDraft draft,
    ImportMappingConfig config,
  ) async {
    final result = _importService.parseDraft(draft, config);
    return _applyImportResult(result);
  }

  Future<ImportSummary> importSample() async {
    final result = await _importService.importSampleAsset();
    return _applyImportResult(result);
  }

  Future<List<DriveFileReference>> listDriveFiles() async {
    return _withDriveBusy(() async {
      final files = await _driveSyncService.connectAndListImportableFiles();
      _refreshDriveState();
      return files;
    });
  }

  Future<DriveSyncSummary> selectDriveFileAndSync(
    DriveFileReference file,
  ) async {
    return _withDriveBusy(() async {
      await _driveSyncService.selectFile(file);
      _refreshDriveState();
      return _syncDriveSelection(forceDownload: true, allowUserPrompt: true);
    });
  }

  Future<DriveSyncSummary> syncSelectedDriveFile() async {
    return _withDriveBusy(() async {
      return _syncDriveSelection(forceDownload: false, allowUserPrompt: true);
    });
  }

  Future<void> navigateToDestination(Destination destination) {
    return _navigationService.openInGoogleMaps(destination);
  }

  Future<List<GeocodingCandidate>> searchGeocodingCandidates(
    String rawAddress,
  ) {
    return _geocodingService.searchCandidates(rawAddress);
  }

  Future<String?> exportCsv() {
    return _dataExchangeService.exportCsv(_destinations);
  }

  Future<String?> exportXlsx() {
    return _dataExchangeService.exportXlsx(_destinations);
  }

  Future<String?> exportBackup() {
    return _dataExchangeService.exportBackup(
      destinations: _destinations,
      preferences: _preferences,
    );
  }

  Future<RestoreSummary?> restoreFromBackup() async {
    final backup = await _dataExchangeService.importBackup();
    if (backup == null) {
      return null;
    }

    final previousAttachments = _destinations
        .expand((destination) => destination.attachmentPaths)
        .toSet();
    final nextAttachments = backup.destinations
        .expand((destination) => destination.attachmentPaths)
        .toSet();

    _destinations = backup.destinations.toList(growable: false);
    _preferences = backup.preferences;
    _selectedDestinationId = _destinations.isEmpty ? null : _destinations.first.id;
    await _persistAll();

    final removedAttachments = previousAttachments
        .where((path) => !nextAttachments.contains(path))
        .toList(growable: false);
    await _photoService.deletePhotos(removedAttachments);

    return RestoreSummary(
      restoredDestinations: _destinations.length,
      restoredProjectName: _preferences.projectName,
    );
  }

  Future<void> updateProjectSettings({
    required String projectName,
    required int projectColorValue,
    required MarkerColorMode markerColorMode,
  }) async {
    _preferences = _preferences.copyWith(
      projectName: projectName.trim().isEmpty ? 'Mapped' : projectName.trim(),
      projectColorValue: projectColorValue,
      markerColorMode: markerColorMode,
    );
    await _persistPreferences();
  }

  Future<void> updateSorting({
    required DestinationSortField sortField,
    required bool sortAscending,
  }) async {
    _preferences = _preferences.copyWith(
      sortField: sortField,
      sortAscending: sortAscending,
    );
    await _persistPreferences();
  }

  Future<void> sortByColumn(String columnId) async {
    final targetField = sortFieldForColumn(columnId);
    if (targetField == null) {
      return;
    }

    final nextAscending = _preferences.sortField == targetField
        ? !_preferences.sortAscending
        : true;

    await updateSorting(sortField: targetField, sortAscending: nextAscending);
  }

  Future<void> toggleVisibleColumn(String columnId) async {
    final sanitizedColumns = _sanitizeVisibleColumns(_preferences.visibleColumns);
    final updatedColumns = <String>[...sanitizedColumns];

    if (updatedColumns.contains(columnId)) {
      if (updatedColumns.length == 1) {
        return;
      }
      updatedColumns.remove(columnId);
    } else {
      updatedColumns.add(columnId);
    }

    _preferences = _preferences.copyWith(visibleColumns: updatedColumns);
    await _persistPreferences();
  }

  Future<void> setVisibleColumns(List<String> columnIds) async {
    final sanitizedColumns = _sanitizeVisibleColumns(columnIds);
    _preferences = _preferences.copyWith(visibleColumns: sanitizedColumns);
    await _persistPreferences();
  }

  String columnLabelFor(String columnId) {
    if (columnId.startsWith('custom:')) {
      return columnId.substring('custom:'.length);
    }

    return switch (columnId) {
      'id' => 'ID',
      'name' => 'Nome',
      'address' => 'Indirizzo',
      'city' => 'Città',
      'postalCode' => 'CAP',
      'phone' => 'Telefono',
      'category' => 'Categoria',
      'tags' => 'Tag',
      'status' => 'Stato',
      'dueDate' => 'Scadenza',
      'map' => 'Mappa',
      'attachments' => 'Allegati',
      'notes' => 'Note',
      _ => columnId,
    };
  }

  DestinationSortField? sortFieldForColumn(String columnId) {
    return switch (columnId) {
      'name' => DestinationSortField.name,
      'address' => DestinationSortField.address,
      'city' => DestinationSortField.city,
      'postalCode' => DestinationSortField.postalCode,
      'phone' => DestinationSortField.phone,
      'status' => DestinationSortField.status,
      'category' => DestinationSortField.category,
      'dueDate' => DestinationSortField.dueDate,
      _ => null,
    };
  }

  double markerHueFor(Destination destination) {
    if (_preferences.markerColorMode == MarkerColorMode.status ||
        destination.category.trim().isEmpty) {
      return destination.status == DestinationStatus.completed
          ? BitmapDescriptor.hueGreen
          : BitmapDescriptor.hueRed;
    }

    final hues = <double>[
      BitmapDescriptor.hueAzure,
      BitmapDescriptor.hueCyan,
      BitmapDescriptor.hueGreen,
      BitmapDescriptor.hueOrange,
      BitmapDescriptor.hueRose,
      BitmapDescriptor.hueViolet,
      BitmapDescriptor.hueYellow,
    ];

    final hash = destination.category.toLowerCase().codeUnits.fold<int>(
      0,
      (total, item) => total + item,
    );
    return hues[hash % hues.length];
  }

  Future<ImportSummary> _applyImportResult(ImportResult result) async {
    final byId = <String, Destination>{
      for (final destination in _destinations) destination.id: destination,
    };

    var added = 0;
    var updated = 0;
    var geocoded = 0;
    var unresolved = 0;

    for (final rawDestination in result.destinations) {
      final geocodingResult = await _geocodingService.fillCoordinatesIfNeeded(
        rawDestination,
      );
      final existingDestination = byId[rawDestination.id];
      final destination = geocodingResult.destination.copyWith(
        attachmentPaths:
            geocodingResult.destination.attachmentPaths.isNotEmpty
            ? geocodingResult.destination.attachmentPaths
            : (existingDestination?.attachmentPaths ?? const <String>[]),
      );

      if (geocodingResult.wasGeocoded) {
        geocoded++;
      }
      if (!destination.hasCoordinates) {
        unresolved++;
      }

      if (byId.containsKey(destination.id)) {
        updated++;
      } else {
        added++;
      }
      byId[destination.id] = destination;
    }

    _destinations = byId.values.toList()..sort(_compareDestinations);
    if (result.destinations.isNotEmpty) {
      _selectedDestinationId = result.destinations.first.id;
    }
    await _persistDestinations();

    return ImportSummary(
      sourceName: result.sourceName,
      added: added,
      updated: updated,
      skippedRows: result.skippedRows,
      geocoded: geocoded,
      unresolved: unresolved,
    );
  }

  Future<void> _persistAll() async {
    await _storageService.saveDestinations(_destinations);
    await _preferencesService.savePreferences(_preferences);
    notifyListeners();
  }

  Future<void> _persistDestinations() async {
    await _storageService.saveDestinations(_destinations);
    notifyListeners();
  }

  Future<void> _persistPreferences() async {
    await _preferencesService.savePreferences(_preferences);
    notifyListeners();
  }

  Future<void> _attemptInitialDriveSync() async {
    if (_driveSelectedFile == null || _isDriveBusy) {
      return;
    }

    try {
      await _syncDriveSelection(
        forceDownload: false,
        allowUserPrompt: false,
      );
    } on Object {
      _refreshDriveState(notify: true);
    }
  }

  Future<DriveSyncSummary> _syncDriveSelection({
    required bool forceDownload,
    required bool allowUserPrompt,
  }) async {
    final downloadResult = await _driveSyncService.syncSelectedFile(
      allowUserPrompt: allowUserPrompt,
      forceDownload: forceDownload,
    );

    _refreshDriveState();

    if (downloadResult.wasUpToDate || !downloadResult.hasBytes) {
      final summary = DriveSyncSummary(
        file: downloadResult.file,
        wasUpToDate: downloadResult.wasUpToDate,
        usedCachedFile: downloadResult.usedCachedFile,
      );
      notifyListeners();
      return summary;
    }

    final importResult = _importService.parseBytes(
      downloadResult.bytes!,
      extension: downloadResult.extension,
      sourceName: downloadResult.file.name,
    );
    final importSummary = await _applyImportResult(importResult);

    _refreshDriveState();
    return DriveSyncSummary(
      file: downloadResult.file,
      importSummary: importSummary,
      wasUpToDate: false,
      usedCachedFile: downloadResult.usedCachedFile,
    );
  }

  Future<T> _withDriveBusy<T>(Future<T> Function() action) async {
    _isDriveBusy = true;
    notifyListeners();
    try {
      final result = await action();
      return result;
    } finally {
      _isDriveBusy = false;
      _refreshDriveState();
      notifyListeners();
    }
  }

  void _refreshDriveState({bool notify = false}) {
    _driveSelectedFile = _driveSyncService.selectedFile;
    _driveAccountEmail = _driveSyncService.connectedEmail;
    _driveLastSyncAt = _driveSyncService.lastSyncAt;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _cleanupRemovedAttachments(
    List<String> previousAttachments,
    List<String> nextAttachments,
  ) async {
    final removablePaths = previousAttachments
        .where((path) => !nextAttachments.contains(path))
        .toList(growable: false);

    await _photoService.deletePhotos(removablePaths);
  }

  int _compareDestinations(Destination left, Destination right) {
    final rawComparison = switch (_preferences.sortField) {
      DestinationSortField.name => left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      ),
      DestinationSortField.address =>
        left.address.toLowerCase().compareTo(right.address.toLowerCase()),
      DestinationSortField.city =>
        left.city.toLowerCase().compareTo(right.city.toLowerCase()),
      DestinationSortField.postalCode =>
        left.postalCode.toLowerCase().compareTo(right.postalCode.toLowerCase()),
      DestinationSortField.phone =>
        left.phone.toLowerCase().compareTo(right.phone.toLowerCase()),
      DestinationSortField.status =>
        left.status.storageValue.compareTo(right.status.storageValue),
      DestinationSortField.category =>
        left.category.toLowerCase().compareTo(right.category.toLowerCase()),
      DestinationSortField.dueDate => _compareDueDates(left.dueDate, right.dueDate),
    };

    final comparison = _preferences.sortAscending ? rawComparison : -rawComparison;
    if (comparison != 0) {
      return comparison;
    }

    final nameComparison = left.displayName.toLowerCase().compareTo(
      right.displayName.toLowerCase(),
    );
    if (nameComparison != 0) {
      return nameComparison;
    }
    return left.id.compareTo(right.id);
  }

  int _compareDueDates(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.compareTo(right);
  }

  List<String> _sanitizeVisibleColumns(List<String> rawColumns) {
    final allowedColumns = availableColumnIds.toSet();
    final sanitized = rawColumns
        .where((columnId) => allowedColumns.contains(columnId))
        .toSet()
        .toList(growable: false);

    if (sanitized.isEmpty) {
      return AppPreferences.defaults().visibleColumns;
    }

    return sanitized;
  }
}
