import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/destination.dart';
import '../services/destination_storage_service.dart';
import '../services/destination_photo_service.dart';
import '../services/drive_sync_service.dart';
import '../services/geocoding_service.dart';
import '../services/import_service.dart';
import '../services/navigation_service.dart';

enum DestinationStatusFilter { all, pending, completed }

extension DestinationStatusFilterX on DestinationStatusFilter {
  String get label => switch (this) {
    DestinationStatusFilter.all => 'Tutti',
    DestinationStatusFilter.pending => 'Da fare',
    DestinationStatusFilter.completed => 'Completati',
  };
}

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

class DestinationController extends ChangeNotifier {
  DestinationController({
    required DestinationStorageService storageService,
    required DestinationPhotoService photoService,
    required DriveSyncService driveSyncService,
    required ImportService importService,
    required NavigationService navigationService,
    required GeocodingService geocodingService,
  }) : _storageService = storageService,
       _photoService = photoService,
       _driveSyncService = driveSyncService,
       _importService = importService,
       _navigationService = navigationService,
       _geocodingService = geocodingService;

  final DestinationStorageService _storageService;
  final DestinationPhotoService _photoService;
  final DriveSyncService _driveSyncService;
  final ImportService _importService;
  final NavigationService _navigationService;
  final GeocodingService _geocodingService;

  List<Destination> _destinations = <Destination>[];
  String _searchQuery = '';
  DestinationStatusFilter _statusFilter = DestinationStatusFilter.all;
  String? _selectedDestinationId;
  bool _isDriveBusy = false;
  DriveFileReference? _driveSelectedFile;
  String? _driveAccountEmail;
  DateTime? _driveLastSyncAt;

  List<Destination> get destinations => List.unmodifiable(_destinations);
  String get searchQuery => _searchQuery;
  DestinationStatusFilter get statusFilter => _statusFilter;
  String? get selectedDestinationId => _selectedDestinationId;
  bool get isDriveBusy => _isDriveBusy;
  bool get isDriveConfigured => _driveSyncService.isConfigured;
  DriveFileReference? get driveSelectedFile => _driveSelectedFile;
  String? get driveAccountEmail => _driveAccountEmail;
  DateTime? get driveLastSyncAt => _driveLastSyncAt;

  Destination? get selectedDestination {
    final id = _selectedDestinationId;
    if (id == null) {
      return null;
    }
    return findById(id);
  }

  List<Destination> get visibleDestinations {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _destinations
        .where((destination) {
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
              matchesCustomField;

          if (!matchesQuery) {
            return false;
          }

          return switch (_statusFilter) {
            DestinationStatusFilter.all => true,
            DestinationStatusFilter.pending =>
              destination.status == DestinationStatus.pending,
            DestinationStatusFilter.completed =>
              destination.status == DestinationStatus.completed,
          };
        })
        .toList(growable: false);

    filtered.sort(_compareDestinations);
    return filtered;
  }

  List<Destination> get mappableDestinations => visibleDestinations
      .where((destination) => destination.hasCoordinates)
      .toList(growable: false);

  int get missingCoordinatesCount => visibleDestinations
      .where((destination) => !destination.hasCoordinates)
      .length;

  Future<void> initialize() async {
    _destinations = await _storageService.loadDestinations();
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
    await _persist();
    await _cleanupReplacedPhoto(
      previousDestination?.photoPath,
      resolvedDestination.photoPath,
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
    await _persist();
    await _photoService.deletePhoto(existingDestination?.photoPath);
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
        photoPath:
            geocodingResult.destination.photoPath ??
            existingDestination?.photoPath,
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
    await _persist();

    return ImportSummary(
      sourceName: result.sourceName,
      added: added,
      updated: updated,
      skippedRows: result.skippedRows,
      geocoded: geocoded,
      unresolved: unresolved,
    );
  }

  Future<void> _persist() async {
    await _storageService.saveDestinations(_destinations);
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

  Future<void> _cleanupReplacedPhoto(
    String? previousPhotoPath,
    String? newPhotoPath,
  ) async {
    if (previousPhotoPath == null || previousPhotoPath == newPhotoPath) {
      return;
    }

    await _photoService.deletePhoto(previousPhotoPath);
  }

  int _compareDestinations(Destination left, Destination right) {
    final nameComparison = left.displayName.toLowerCase().compareTo(
      right.displayName.toLowerCase(),
    );
    if (nameComparison != 0) {
      return nameComparison;
    }
    return left.id.compareTo(right.id);
  }
}
