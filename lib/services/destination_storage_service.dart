import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/destination.dart';

class DestinationStorageService {
  DestinationStorageService(this._preferences);

  static const _storageKey = 'mapped_destinations';

  final SharedPreferences _preferences;

  Future<List<Destination>> loadDestinations() async {
    final rawJson = _preferences.getString(_storageKey);
    if (rawJson == null || rawJson.trim().isEmpty) {
      return <Destination>[];
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        return <Destination>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (entry) =>
                entry.map((key, value) => MapEntry(key.toString(), value)),
          )
          .map(Destination.fromJson)
          .toList(growable: false);
    } on FormatException {
      return <Destination>[];
    } on TypeError {
      return <Destination>[];
    }
  }

  Future<void> saveDestinations(List<Destination> destinations) async {
    final payload = jsonEncode(
      destinations.map((destination) => destination.toJson()).toList(),
    );
    await _preferences.setString(_storageKey, payload);
  }
}
