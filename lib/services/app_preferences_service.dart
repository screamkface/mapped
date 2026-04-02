import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_preferences.dart';

class AppPreferencesService {
  AppPreferencesService(this._preferences);

  static const _storageKey = 'mapped_app_preferences_v1';

  final SharedPreferences _preferences;

  Future<AppPreferences> loadPreferences() async {
    final rawJson = _preferences.getString(_storageKey);
    if (rawJson == null || rawJson.trim().isEmpty) {
      return AppPreferences.defaults();
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return AppPreferences.defaults();
      }

      return AppPreferences.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      return AppPreferences.defaults();
    } on TypeError {
      return AppPreferences.defaults();
    }
  }

  Future<void> savePreferences(AppPreferences preferences) async {
    await _preferences.setString(_storageKey, jsonEncode(preferences.toJson()));
  }
}
