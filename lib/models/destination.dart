import 'dart:math';

enum DestinationStatus { pending, completed }

extension DestinationStatusX on DestinationStatus {
  String get storageValue => switch (this) {
    DestinationStatus.pending => 'pending',
    DestinationStatus.completed => 'completed',
  };

  String get label => switch (this) {
    DestinationStatus.pending => 'Da fare',
    DestinationStatus.completed => 'Completato',
  };

  static DestinationStatus fromRawValue(String? rawValue) {
    final normalized = _normalizeToken(rawValue);
    const completedValues = {
      'completed',
      'completato',
      'done',
      'ok',
      'true',
      '1',
    };

    return completedValues.contains(normalized)
        ? DestinationStatus.completed
        : DestinationStatus.pending;
  }
}

class Destination {
  Destination({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.postalCode,
    required this.notes,
    required this.phone,
    required this.photoPath,
    required this.latitude,
    required this.longitude,
    required this.status,
    Map<String, String>? customFields,
  }) : customFields = Map.unmodifiable(
         Map.fromEntries(
           (customFields ?? const <String, String>{}).entries
               .where(
                 (entry) =>
                     entry.key.trim().isNotEmpty &&
                     entry.value.trim().isNotEmpty,
               )
               .map((entry) => MapEntry(entry.key.trim(), entry.value.trim())),
         ),
       );

  final String id;
  final String name;
  final String address;
  final String city;
  final String postalCode;
  final String notes;
  final String phone;
  final String? photoPath;
  final double? latitude;
  final double? longitude;
  final DestinationStatus status;
  final Map<String, String> customFields;

  static final Random _random = Random();

  static String generateId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
  }

  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : generateId(),
      name: (json['name'] as String? ?? '').trim(),
      address: (json['address'] as String? ?? '').trim(),
      city: (json['city'] as String? ?? '').trim(),
      postalCode: (json['postalCode'] as String? ?? '').trim(),
      notes: (json['notes'] as String? ?? '').trim(),
      phone: (json['phone'] as String? ?? '').trim(),
      photoPath: _parseOptionalString(json['photoPath']?.toString()),
      latitude: _parseCoordinate(json['latitude']?.toString()),
      longitude: _parseCoordinate(json['longitude']?.toString()),
      status: DestinationStatusX.fromRawValue(json['status']?.toString()),
      customFields: _parseCustomFields(json['customFields']),
    );
  }

  factory Destination.fromCsvRow(
    Map<String, String> row, {
    String? fallbackId,
  }) {
    final destinationId = _readField(row, _HeaderAliases.id).trim().isNotEmpty
        ? _readField(row, _HeaderAliases.id).trim()
        : (fallbackId ?? generateId());

    return Destination(
      id: destinationId,
      name: _readField(row, _HeaderAliases.name).trim(),
      address: _readField(row, _HeaderAliases.address).trim(),
      city: _readField(row, _HeaderAliases.city).trim(),
      postalCode: _readField(row, _HeaderAliases.postalCode).trim(),
      notes: _readField(row, _HeaderAliases.notes).trim(),
      phone: _readField(row, _HeaderAliases.phone).trim(),
      photoPath: _parseOptionalString(_readField(row, _HeaderAliases.photo)),
      latitude: _parseCoordinate(_readField(row, _HeaderAliases.latitude)),
      longitude: _parseCoordinate(_readField(row, _HeaderAliases.longitude)),
      status: DestinationStatusX.fromRawValue(
        _readField(row, _HeaderAliases.status),
      ),
      customFields: _extractCustomFields(row),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'address': address,
      'city': city,
      'postalCode': postalCode,
      'notes': notes,
      'phone': phone,
      'photoPath': photoPath,
      'latitude': latitude,
      'longitude': longitude,
      'status': status.storageValue,
      'customFields': customFields,
    };
  }

  Destination copyWith({
    String? id,
    String? name,
    String? address,
    String? city,
    String? postalCode,
    String? notes,
    String? phone,
    String? photoPath,
    double? latitude,
    double? longitude,
    DestinationStatus? status,
    Map<String, String>? customFields,
    bool clearCoordinates = false,
  }) {
    return Destination(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      notes: notes ?? this.notes,
      phone: phone ?? this.phone,
      photoPath: photoPath ?? this.photoPath,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      status: status ?? this.status,
      customFields: customFields ?? this.customFields,
    );
  }

  String get displayName {
    if (name.trim().isNotEmpty) {
      return name.trim();
    }
    if (fullAddress.isNotEmpty) {
      return fullAddress;
    }
    return 'Destinazione $id';
  }

  String get fullAddress {
    final locality = [
      postalCode.trim(),
      city.trim(),
    ].where((value) => value.isNotEmpty).join(' ');

    return [
      address.trim(),
      locality,
    ].where((value) => value.isNotEmpty).join(', ');
  }

  bool get hasCoordinates {
    if (latitude == null || longitude == null) {
      return false;
    }

    return latitude! >= -90 &&
        latitude! <= 90 &&
        longitude! >= -180 &&
        longitude! <= 180;
  }

  bool get hasCustomFields => customFields.isNotEmpty;

  List<MapEntry<String, String>> get sortedCustomFields {
    final entries = customFields.entries.toList(growable: false);
    entries.sort(
      (left, right) =>
          left.key.toLowerCase().compareTo(right.key.toLowerCase()),
    );
    return entries;
  }

  static String _readField(Map<String, String> row, Set<String> aliases) {
    for (final entry in row.entries) {
      if (aliases.contains(_normalizeToken(entry.key))) {
        return entry.value;
      }
    }
    return '';
  }

  static Map<String, String> _extractCustomFields(Map<String, String> row) {
    final customFields = <String, String>{};

    for (final entry in row.entries) {
      if (_HeaderAliases.isStandardHeader(entry.key)) {
        continue;
      }

      final header = entry.key.trim();
      final value = entry.value.trim();
      if (header.isEmpty || value.isEmpty) {
        continue;
      }

      customFields[header] = value;
    }

    return customFields;
  }

  static Map<String, String> _parseCustomFields(dynamic rawValue) {
    if (rawValue is! Map) {
      return const <String, String>{};
    }

    return Map<String, String>.fromEntries(
      rawValue.entries
          .where((entry) {
            return entry.key.toString().trim().isNotEmpty &&
                entry.value?.toString().trim().isNotEmpty == true;
          })
          .map(
            (entry) => MapEntry(
              entry.key.toString().trim(),
              entry.value.toString().trim(),
            ),
          ),
    );
  }

  static double? _parseCoordinate(String? rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = rawValue.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }

    return double.tryParse(normalized);
  }

  static String? _parseOptionalString(String? rawValue) {
    final trimmed = rawValue?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _HeaderAliases {
  static const id = {'id', 'codice', 'identifier'};
  static const name = {'name', 'nome', 'ragionesociale', 'cliente'};
  static const address = {'address', 'indirizzo', 'street', 'via'};
  static const city = {'city', 'citta', 'comune'};
  static const postalCode = {'postalcode', 'postal', 'cap', 'zip', 'zipcode'};
  static const notes = {'notes', 'note', 'descrizione', 'description'};
  static const phone = {'phone', 'telefono', 'tel', 'mobile', 'cellulare'};
  static const photo = {'photo', 'foto', 'image', 'imagepath', 'photopath'};
  static const latitude = {'lat', 'latitude', 'latitudine'};
  static const longitude = {'lng', 'lon', 'long', 'longitude', 'longitudine'};
  static const status = {'status', 'stato'};

  static final Set<String> _allKnownHeaders = <String>{
    ...id,
    ...name,
    ...address,
    ...city,
    ...postalCode,
    ...notes,
    ...phone,
    ...photo,
    ...latitude,
    ...longitude,
    ...status,
  };

  static bool isStandardHeader(String rawHeader) {
    return _allKnownHeaders.contains(_normalizeToken(rawHeader));
  }
}

String _normalizeToken(String? value) {
  if (value == null || value.trim().isEmpty) {
    return '';
  }

  return value
      .trim()
      .toLowerCase()
      .replaceAll('à', 'a')
      .replaceAll('á', 'a')
      .replaceAll('è', 'e')
      .replaceAll('é', 'e')
      .replaceAll('ì', 'i')
      .replaceAll('í', 'i')
      .replaceAll('ò', 'o')
      .replaceAll('ó', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('ú', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}
