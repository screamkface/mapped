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

class ChecklistItem {
  const ChecklistItem({required this.label, required this.isDone});

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      label: (json['label'] as String? ?? '').trim(),
      isDone: json['isDone'] == true,
    );
  }

  final String label;
  final bool isDone;

  ChecklistItem copyWith({String? label, bool? isDone}) {
    return ChecklistItem(
      label: (label ?? this.label).trim(),
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'label': label, 'isDone': isDone};
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
    String? photoPath,
    List<String>? attachmentPaths,
    required this.latitude,
    required this.longitude,
    required this.status,
    String category = '',
    List<String>? tags,
    this.dueDate,
    List<ChecklistItem>? checklistItems,
    Map<String, String>? customFields,
  }) : category = category.trim(),
       tags = List.unmodifiable(_normalizeTags(tags)),
       attachmentPaths = List.unmodifiable(
         _normalizeAttachmentPaths(attachmentPaths, legacyPhotoPath: photoPath),
       ),
       checklistItems = List.unmodifiable(
         _normalizeChecklistItems(checklistItems),
       ),
       customFields = Map.unmodifiable(
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
  final List<String> attachmentPaths;
  final double? latitude;
  final double? longitude;
  final DestinationStatus status;
  final String category;
  final List<String> tags;
  final DateTime? dueDate;
  final List<ChecklistItem> checklistItems;
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
      attachmentPaths: _parseAttachmentPaths(json['attachmentPaths']),
      latitude: _parseCoordinate(json['latitude']?.toString()),
      longitude: _parseCoordinate(json['longitude']?.toString()),
      status: DestinationStatusX.fromRawValue(json['status']?.toString()),
      category: (json['category'] as String? ?? '').trim(),
      tags: _parseTags(json['tags']),
      dueDate: _parseDate(json['dueDate']),
      checklistItems: _parseChecklistItems(json['checklistItems']),
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
      attachmentPaths: _splitRawList(_readField(row, _HeaderAliases.attachments)),
      latitude: _parseCoordinate(_readField(row, _HeaderAliases.latitude)),
      longitude: _parseCoordinate(_readField(row, _HeaderAliases.longitude)),
      status: DestinationStatusX.fromRawValue(
        _readField(row, _HeaderAliases.status),
      ),
      category: _readField(row, _HeaderAliases.category).trim(),
      tags: _splitRawList(_readField(row, _HeaderAliases.tags)),
      dueDate: _parseDate(_readField(row, _HeaderAliases.dueDate)),
      checklistItems: _parseChecklistFromCsv(
        _readField(row, _HeaderAliases.checklist),
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
      'attachmentPaths': attachmentPaths,
      'latitude': latitude,
      'longitude': longitude,
      'status': status.storageValue,
      'category': category,
      'tags': tags,
      'dueDate': dueDate?.toIso8601String(),
      'checklistItems': checklistItems.map((item) => item.toJson()).toList(),
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
    List<String>? attachmentPaths,
    double? latitude,
    double? longitude,
    DestinationStatus? status,
    String? category,
    List<String>? tags,
    DateTime? dueDate,
    List<ChecklistItem>? checklistItems,
    Map<String, String>? customFields,
    bool clearCoordinates = false,
    bool clearDueDate = false,
  }) {
    return Destination(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      notes: notes ?? this.notes,
      phone: phone ?? this.phone,
      photoPath: photoPath,
      attachmentPaths:
          attachmentPaths ??
          (photoPath != null ? <String>[photoPath] : this.attachmentPaths),
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      status: status ?? this.status,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      checklistItems: checklistItems ?? this.checklistItems,
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

  String get photoPath => attachmentPaths.isEmpty ? '' : attachmentPaths.first;

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

  bool get hasAttachments => attachmentPaths.isNotEmpty;

  bool get hasChecklist => checklistItems.isNotEmpty;

  bool get hasTags => tags.isNotEmpty;

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

  static List<String> _parseAttachmentPaths(dynamic rawValue) {
    if (rawValue is! List) {
      return const <String>[];
    }

    return rawValue
        .map((value) => _parseOptionalString(value?.toString()))
        .whereType<String>()
        .toList(growable: false);
  }

  static List<String> _normalizeAttachmentPaths(
    List<String>? rawPaths, {
    String? legacyPhotoPath,
  }) {
    final paths = <String>[];
    final seen = <String>{};

    for (final path in <String?>[
      legacyPhotoPath,
      ...(rawPaths ?? const <String>[]),
    ]) {
      final normalized = _parseOptionalString(path);
      if (normalized == null || seen.contains(normalized)) {
        continue;
      }
      seen.add(normalized);
      paths.add(normalized);
    }

    return paths;
  }

  static List<String> _normalizeTags(List<String>? rawTags) {
    if (rawTags == null) {
      return const <String>[];
    }

    final normalizedTags = <String>[];
    final seen = <String>{};

    for (final rawTag in rawTags) {
      final normalized = rawTag.trim();
      if (normalized.isEmpty) {
        continue;
      }

      final key = normalized.toLowerCase();
      if (seen.contains(key)) {
        continue;
      }

      seen.add(key);
      normalizedTags.add(normalized);
    }

    return normalizedTags;
  }

  static List<ChecklistItem> _normalizeChecklistItems(
    List<ChecklistItem>? rawItems,
  ) {
    if (rawItems == null) {
      return const <ChecklistItem>[];
    }

    return rawItems
        .map(
          (item) => item.copyWith(label: item.label.trim()),
        )
        .where((item) => item.label.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _parseTags(dynamic rawValue) {
    if (rawValue is! List) {
      return const <String>[];
    }

    return rawValue
        .map((value) => value?.toString() ?? '')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static List<ChecklistItem> _parseChecklistItems(dynamic rawValue) {
    if (rawValue is! List) {
      return const <ChecklistItem>[];
    }

    return rawValue
        .whereType<Map>()
        .map(
          (item) => ChecklistItem.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((item) => item.label.isNotEmpty)
        .toList(growable: false);
  }

  static List<ChecklistItem> _parseChecklistFromCsv(String rawValue) {
    return _splitRawList(rawValue)
        .map((value) {
          final isDone = value.startsWith('[x]') || value.startsWith('[X]');
          final label = value.replaceFirst(RegExp(r'^\[(x|X| )\]\s*'), '');
          return ChecklistItem(label: label, isDone: isDone);
        })
        .where((item) => item.label.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _splitRawList(String rawValue) {
    return rawValue
        .split(RegExp(r'[|,;]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static DateTime? _parseDate(dynamic rawValue) {
    final stringValue = rawValue?.toString().trim() ?? '';
    if (stringValue.isEmpty) {
      return null;
    }

    final parsedIso = DateTime.tryParse(stringValue);
    if (parsedIso != null) {
      return DateTime(parsedIso.year, parsedIso.month, parsedIso.day);
    }

    final slashParts = stringValue.split('/');
    if (slashParts.length == 3) {
      final day = int.tryParse(slashParts[0]);
      final month = int.tryParse(slashParts[1]);
      final year = int.tryParse(slashParts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    final dashParts = stringValue.split('-');
    if (dashParts.length == 3) {
      final year = int.tryParse(dashParts[0]);
      final month = int.tryParse(dashParts[1]);
      final day = int.tryParse(dashParts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
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
  static const attachments = {'attachments', 'allegati', 'files', 'file'};
  static const latitude = {'lat', 'latitude', 'latitudine'};
  static const longitude = {'lng', 'lon', 'long', 'longitude', 'longitudine'};
  static const status = {'status', 'stato'};
  static const category = {'category', 'categoria', 'tipo', 'tipologia'};
  static const tags = {'tags', 'tag', 'etichette'};
  static const dueDate = {'duedate', 'deadline', 'scadenza', 'data'};
  static const checklist = {'checklist', 'tasks', 'todo', 'attivita'};

  static final Set<String> _allKnownHeaders = <String>{
    ...id,
    ...name,
    ...address,
    ...city,
    ...postalCode,
    ...notes,
    ...phone,
    ...photo,
    ...attachments,
    ...latitude,
    ...longitude,
    ...status,
    ...category,
    ...tags,
    ...dueDate,
    ...checklist,
  };

  static bool isStandardHeader(String rawHeader) {
    return _allKnownHeaders.contains(_normalizeToken(rawHeader));
  }
}

String normalizeToken(String? value) {
  return _normalizeToken(value);
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
