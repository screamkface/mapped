import 'dart:math';

enum DestinationSortField {
  name,
  address,
  city,
  postalCode,
  phone,
  status,
  category,
  dueDate,
}

extension DestinationSortFieldX on DestinationSortField {
  String get label => switch (this) {
    DestinationSortField.name => 'Nome',
    DestinationSortField.address => 'Indirizzo',
    DestinationSortField.city => 'Città',
    DestinationSortField.postalCode => 'CAP',
    DestinationSortField.phone => 'Telefono',
    DestinationSortField.status => 'Stato',
    DestinationSortField.category => 'Categoria',
    DestinationSortField.dueDate => 'Scadenza',
  };

  String get storageValue => name;

  static DestinationSortField fromRawValue(String? rawValue) {
    return DestinationSortField.values.firstWhere(
      (field) => field.name == rawValue,
      orElse: () => DestinationSortField.name,
    );
  }
}

enum MarkerColorMode { status, category }

extension MarkerColorModeX on MarkerColorMode {
  String get label => switch (this) {
    MarkerColorMode.status => 'Per stato',
    MarkerColorMode.category => 'Per categoria',
  };

  static MarkerColorMode fromRawValue(String? rawValue) {
    return MarkerColorMode.values.firstWhere(
      (mode) => mode.name == rawValue,
      orElse: () => MarkerColorMode.status,
    );
  }
}

class SavedFilterPreset {
  SavedFilterPreset({
    required this.id,
    required this.name,
    required this.searchQuery,
    required this.statusFilter,
    required this.category,
    required this.tag,
  });

  factory SavedFilterPreset.create({
    required String name,
    required String searchQuery,
    required DestinationStatusFilter statusFilter,
    required String category,
    required String tag,
  }) {
    return SavedFilterPreset(
      id:
          '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
      name: name.trim(),
      searchQuery: searchQuery.trim(),
      statusFilter: statusFilter,
      category: category.trim(),
      tag: tag.trim(),
    );
  }

  factory SavedFilterPreset.fromJson(Map<String, dynamic> json) {
    return SavedFilterPreset(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      searchQuery: (json['searchQuery'] as String? ?? '').trim(),
      statusFilter: DestinationStatusFilterX.fromRawValue(
        json['statusFilter']?.toString(),
      ),
      category: (json['category'] as String? ?? '').trim(),
      tag: (json['tag'] as String? ?? '').trim(),
    );
  }

  final String id;
  final String name;
  final String searchQuery;
  final DestinationStatusFilter statusFilter;
  final String category;
  final String tag;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'searchQuery': searchQuery,
      'statusFilter': statusFilter.name,
      'category': category,
      'tag': tag,
    };
  }
}

enum DestinationStatusFilter { all, pending, completed }

extension DestinationStatusFilterX on DestinationStatusFilter {
  String get label => switch (this) {
    DestinationStatusFilter.all => 'Tutti',
    DestinationStatusFilter.pending => 'Da fare',
    DestinationStatusFilter.completed => 'Completati',
  };

  static DestinationStatusFilter fromRawValue(String? rawValue) {
    return DestinationStatusFilter.values.firstWhere(
      (filter) => filter.name == rawValue,
      orElse: () => DestinationStatusFilter.all,
    );
  }
}

class AppPreferences {
  const AppPreferences({
    required this.projectName,
    required this.projectColorValue,
    required this.sortField,
    required this.sortAscending,
    required this.markerColorMode,
    required this.visibleColumns,
    required this.savedFilters,
  });

  factory AppPreferences.defaults() {
    return const AppPreferences(
      projectName: 'Mapped',
      projectColorValue: 0xFF146C5B,
      sortField: DestinationSortField.name,
      sortAscending: true,
      markerColorMode: MarkerColorMode.status,
      visibleColumns: <String>[
        'name',
        'address',
        'city',
        'category',
        'status',
        'dueDate',
        'map',
        'attachments',
      ],
      savedFilters: <SavedFilterPreset>[],
    );
  }

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    final visibleColumns = (json['visibleColumns'] as List?)
        ?.map((value) => value?.toString() ?? '')
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);

    final rawSavedFilters = json['savedFilters'];
    final savedFilters = rawSavedFilters is List
        ? rawSavedFilters
              .whereType<Map>()
              .map(
                (item) => SavedFilterPreset.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
              .toList(growable: false)
        : const <SavedFilterPreset>[];

    return AppPreferences(
      projectName: (json['projectName'] as String? ?? 'Mapped').trim(),
      projectColorValue:
          int.tryParse(json['projectColorValue']?.toString() ?? '') ??
          0xFF146C5B,
      sortField: DestinationSortFieldX.fromRawValue(
        json['sortField']?.toString(),
      ),
      sortAscending: json['sortAscending'] != false,
      markerColorMode: MarkerColorModeX.fromRawValue(
        json['markerColorMode']?.toString(),
      ),
      visibleColumns:
          visibleColumns == null || visibleColumns.isEmpty
          ? AppPreferences.defaults().visibleColumns
          : visibleColumns,
      savedFilters: savedFilters,
    );
  }

  final String projectName;
  final int projectColorValue;
  final DestinationSortField sortField;
  final bool sortAscending;
  final MarkerColorMode markerColorMode;
  final List<String> visibleColumns;
  final List<SavedFilterPreset> savedFilters;

  AppPreferences copyWith({
    String? projectName,
    int? projectColorValue,
    DestinationSortField? sortField,
    bool? sortAscending,
    MarkerColorMode? markerColorMode,
    List<String>? visibleColumns,
    List<SavedFilterPreset>? savedFilters,
  }) {
    return AppPreferences(
      projectName: projectName ?? this.projectName,
      projectColorValue: projectColorValue ?? this.projectColorValue,
      sortField: sortField ?? this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
      markerColorMode: markerColorMode ?? this.markerColorMode,
      visibleColumns: visibleColumns ?? this.visibleColumns,
      savedFilters: savedFilters ?? this.savedFilters,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'projectName': projectName,
      'projectColorValue': projectColorValue,
      'sortField': sortField.storageValue,
      'sortAscending': sortAscending,
      'markerColorMode': markerColorMode.name,
      'visibleColumns': visibleColumns,
      'savedFilters': savedFilters.map((item) => item.toJson()).toList(),
    };
  }
}
