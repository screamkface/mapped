import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/destination.dart';

class GeocodingResult {
  const GeocodingResult({
    required this.destination,
    required this.wasGeocoded,
    required this.hasAddressReference,
  });

  final Destination destination;
  final bool wasGeocoded;
  final bool hasAddressReference;

  bool get stillMissingCoordinates => !destination.hasCoordinates;
}

class GeocodingCandidate {
  const GeocodingCandidate({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

class GeocodingService {
  GeocodingService(this._preferences)
    : _cache = _loadCache(_preferences.getString(_cacheStorageKey));

  static const _cacheStorageKey = 'mapped_geocoding_cache_v1';
  static const _maxEntries = 500;
  static const _negativeCacheTtl = Duration(hours: 24);

  final SharedPreferences _preferences;
  final Map<String, _GeocodingCacheEntry> _cache;

  Future<List<GeocodingCandidate>> searchCandidates(String rawAddress) async {
    final address = rawAddress.trim();
    if (address.isEmpty) {
      return const <GeocodingCandidate>[];
    }

    final available = await isPresent();
    if (!available) {
      return const <GeocodingCandidate>[];
    }

    try {
      final locations = await locationFromAddress(
        address,
      ).timeout(const Duration(seconds: 12));

      final uniqueCandidates = <String, GeocodingCandidate>{};
      for (final location in locations.take(5)) {
        final latitude = location.latitude;
        final longitude = location.longitude;
        final key =
            '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

        final placemarks = await placemarkFromCoordinates(
          latitude,
          longitude,
        ).timeout(const Duration(seconds: 8), onTimeout: () => <Placemark>[]);
        final label = _buildPlacemarkLabel(placemarks);

        uniqueCandidates[key] = GeocodingCandidate(
          label: label.isEmpty
              ? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
              : label,
          latitude: latitude,
          longitude: longitude,
        );
      }

      return uniqueCandidates.values.toList(growable: false);
    } catch (_) {
      return const <GeocodingCandidate>[];
    }
  }

  Future<GeocodingResult> fillCoordinatesIfNeeded(
    Destination destination,
  ) async {
    if (destination.hasCoordinates) {
      return GeocodingResult(
        destination: destination,
        wasGeocoded: false,
        hasAddressReference: destination.fullAddress.trim().isNotEmpty,
      );
    }

    final address = destination.fullAddress.trim();
    if (address.isEmpty) {
      return GeocodingResult(
        destination: destination,
        wasGeocoded: false,
        hasAddressReference: false,
      );
    }

    final cacheKey = _normalizeAddressKey(address);
    final cachedResult = _resolveFromCache(cacheKey, destination);
    if (cachedResult != null) {
      return cachedResult;
    }

    try {
      final available = await isPresent();
      if (!available) {
        return GeocodingResult(
          destination: destination,
          wasGeocoded: false,
          hasAddressReference: true,
        );
      }

      final locations = await locationFromAddress(
        address,
      ).timeout(const Duration(seconds: 12));

      if (locations.isEmpty) {
        await _saveCacheEntry(
          cacheKey,
          _GeocodingCacheEntry.miss(updatedAt: DateTime.now()),
        );

        return GeocodingResult(
          destination: destination,
          wasGeocoded: false,
          hasAddressReference: true,
        );
      }

      final resolved = locations.first;
      await _saveCacheEntry(
        cacheKey,
        _GeocodingCacheEntry.success(
          latitude: resolved.latitude,
          longitude: resolved.longitude,
          updatedAt: DateTime.now(),
        ),
      );

      return GeocodingResult(
        destination: destination.copyWith(
          latitude: resolved.latitude,
          longitude: resolved.longitude,
        ),
        wasGeocoded: true,
        hasAddressReference: true,
      );
    } catch (_) {
      await _saveCacheEntry(
        cacheKey,
        _GeocodingCacheEntry.miss(updatedAt: DateTime.now()),
      );

      return GeocodingResult(
        destination: destination,
        wasGeocoded: false,
        hasAddressReference: true,
      );
    }
  }

  GeocodingResult? _resolveFromCache(String cacheKey, Destination destination) {
    final entry = _cache[cacheKey];
    if (entry == null) {
      return null;
    }

    if (entry.isSuccess) {
      if (entry.latitude == null || entry.longitude == null) {
        return null;
      }

      return GeocodingResult(
        destination: destination.copyWith(
          latitude: entry.latitude,
          longitude: entry.longitude,
        ),
        wasGeocoded: false,
        hasAddressReference: true,
      );
    }

    if (!entry.isNegativeCacheExpired) {
      return GeocodingResult(
        destination: destination,
        wasGeocoded: false,
        hasAddressReference: true,
      );
    }

    _cache.remove(cacheKey);
    _persistCache();
    return null;
  }

  Future<void> _saveCacheEntry(
    String cacheKey,
    _GeocodingCacheEntry entry,
  ) async {
    _cache[cacheKey] = entry;
    _pruneCache();
    await _persistCache();
  }

  void _pruneCache() {
    _cache.removeWhere(
      (_, entry) => !entry.isSuccess && entry.isNegativeCacheExpired,
    );

    if (_cache.length <= _maxEntries) {
      return;
    }

    final sortedEntries = _cache.entries.toList(growable: false)
      ..sort(
        (left, right) => left.value.updatedAt.compareTo(right.value.updatedAt),
      );

    final overflow = _cache.length - _maxEntries;
    for (var index = 0; index < overflow; index++) {
      _cache.remove(sortedEntries[index].key);
    }
  }

  Future<void> _persistCache() async {
    final payload = jsonEncode(
      _cache.map((key, value) => MapEntry(key, value.toJson())),
    );
    await _preferences.setString(_cacheStorageKey, payload);
  }

  static Map<String, _GeocodingCacheEntry> _loadCache(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return <String, _GeocodingCacheEntry>{};
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map) {
        return <String, _GeocodingCacheEntry>{};
      }

      final cache = <String, _GeocodingCacheEntry>{};
      for (final entry in decoded.entries) {
        final parsedEntry = _GeocodingCacheEntry.tryParse(entry.value);
        if (parsedEntry == null) {
          continue;
        }
        if (!parsedEntry.isSuccess && parsedEntry.isNegativeCacheExpired) {
          continue;
        }

        cache[entry.key.toString()] = parsedEntry;
      }

      return cache;
    } catch (_) {
      return <String, _GeocodingCacheEntry>{};
    }
  }

  String _normalizeAddressKey(String address) {
    return address
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), '');
  }

  String _buildPlacemarkLabel(List<Placemark> placemarks) {
    if (placemarks.isEmpty) {
      return '';
    }

    final placemark = placemarks.first;
    return <String>[
      placemark.street ?? '',
      placemark.locality ?? '',
      placemark.postalCode ?? '',
      placemark.country ?? '',
    ].where((value) => value.trim().isNotEmpty).join(', ');
  }
}

class _GeocodingCacheEntry {
  const _GeocodingCacheEntry({
    required this.updatedAt,
    required this.isSuccess,
    this.latitude,
    this.longitude,
  });

  factory _GeocodingCacheEntry.success({
    required double latitude,
    required double longitude,
    required DateTime updatedAt,
  }) {
    return _GeocodingCacheEntry(
      updatedAt: updatedAt,
      isSuccess: true,
      latitude: latitude,
      longitude: longitude,
    );
  }

  factory _GeocodingCacheEntry.miss({required DateTime updatedAt}) {
    return _GeocodingCacheEntry(updatedAt: updatedAt, isSuccess: false);
  }

  static _GeocodingCacheEntry? tryParse(dynamic rawValue) {
    if (rawValue is! Map) {
      return null;
    }

    final updatedAtRaw = rawValue['updatedAt'];
    final updatedAt = DateTime.tryParse(updatedAtRaw?.toString() ?? '');
    if (updatedAt == null) {
      return null;
    }

    final isSuccess = rawValue['isSuccess'] == true;
    final latitude = double.tryParse(rawValue['latitude']?.toString() ?? '');
    final longitude = double.tryParse(rawValue['longitude']?.toString() ?? '');

    return _GeocodingCacheEntry(
      updatedAt: updatedAt,
      isSuccess: isSuccess,
      latitude: latitude,
      longitude: longitude,
    );
  }

  final DateTime updatedAt;
  final bool isSuccess;
  final double? latitude;
  final double? longitude;

  bool get isNegativeCacheExpired {
    if (isSuccess) {
      return false;
    }

    return DateTime.now().difference(updatedAt) >
        GeocodingService._negativeCacheTtl;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'updatedAt': updatedAt.toIso8601String(),
      'isSuccess': isSuccess,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
