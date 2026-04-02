import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_config_service.dart';

const String _driveReadonlyScope =
    'https://www.googleapis.com/auth/drive.readonly';
const String _driveFilesEndpoint = '/drive/v3/files';
const String _selectedFileKey = 'mapped_drive_selected_file_v1';
const String _lastSyncAtKey = 'mapped_drive_last_sync_at_v1';
const String _googleSpreadsheetMimeType =
    'application/vnd.google-apps.spreadsheet';
const String _xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const String _csvMimeType = 'text/csv';

class DriveSyncException implements Exception {
  const DriveSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DriveFileReference {
  const DriveFileReference({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.modifiedTime,
    this.sizeInBytes,
  });

  factory DriveFileReference.fromJson(Map<String, dynamic> json) {
    return DriveFileReference(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      mimeType: (json['mimeType'] as String? ?? '').trim(),
      modifiedTime: DateTime.tryParse(json['modifiedTime'] as String? ?? ''),
      sizeInBytes: _parseOptionalInt(json['size']),
    );
  }

  final String id;
  final String name;
  final String mimeType;
  final DateTime? modifiedTime;
  final int? sizeInBytes;

  bool get isGoogleSheet => mimeType == _googleSpreadsheetMimeType;

  bool get isImportable {
    return mimeType == _csvMimeType ||
        mimeType == _xlsxMimeType ||
        mimeType == _googleSpreadsheetMimeType ||
        name.toLowerCase().endsWith('.csv') ||
        name.toLowerCase().endsWith('.xlsx');
  }

  String get preferredExtension {
    if (mimeType == _csvMimeType || name.toLowerCase().endsWith('.csv')) {
      return 'csv';
    }
    return 'xlsx';
  }

  String get displayFormat => switch (preferredExtension) {
    'csv' => 'CSV',
    _ => isGoogleSheet ? 'Google Sheet' : 'Excel',
  };

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'mimeType': mimeType,
      'modifiedTime': modifiedTime?.toIso8601String(),
      'size': sizeInBytes,
    };
  }

  static int? _parseOptionalInt(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    return int.tryParse(rawValue.toString());
  }
}

class DriveDownloadResult {
  const DriveDownloadResult({
    required this.file,
    required this.extension,
    required this.wasUpToDate,
    required this.usedCachedFile,
    this.bytes,
  });

  final DriveFileReference file;
  final Uint8List? bytes;
  final String extension;
  final bool wasUpToDate;
  final bool usedCachedFile;

  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
}

class DriveSyncService {
  DriveSyncService(
    this._preferences, {
    PlatformConfigService? platformConfigService,
    http.Client? httpClient,
  }) : _platformConfigService =
           platformConfigService ?? PlatformConfigService(),
       _httpClient = httpClient ?? http.Client();

  final SharedPreferences _preferences;
  final PlatformConfigService _platformConfigService;
  final http.Client _httpClient;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _initialized = false;
  bool _authEventsBound = false;
  GoogleSignInAccount? _currentUser;
  String _serverClientId = '';
  DriveFileReference? _selectedFile;
  DateTime? _lastSyncAt;

  bool get isConfigured => _serverClientId.isNotEmpty;
  String? get connectedEmail => _currentUser?.email;
  DriveFileReference? get selectedFile => _selectedFile;
  DateTime? get lastSyncAt => _lastSyncAt;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _selectedFile = _loadStoredSelection();
    _lastSyncAt = _loadStoredLastSyncAt();
    _serverClientId = _normalizeServerClientId(
      await _platformConfigService.getGoogleDriveServerClientId(),
    );

    await _googleSignIn.initialize(
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );

    if (!_authEventsBound) {
      _authEventsBound = true;
      unawaited(
        _googleSignIn.authenticationEvents.forEach(_handleAuthenticationEvent),
      );
    }

    try {
      final lightweightAuth = _googleSignIn.attemptLightweightAuthentication();
      if (lightweightAuth != null) {
        _currentUser = await lightweightAuth;
      }
    } on GoogleSignInException {
      _currentUser = null;
    }

    _initialized = true;
  }

  Future<List<DriveFileReference>> connectAndListImportableFiles() async {
    await initialize();

    final response = await _authorizedGet(
      Uri.https('www.googleapis.com', _driveFilesEndpoint, <String, String>{
        'corpora': 'user',
        'q': 'trashed=false',
        'pageSize': '200',
        'spaces': 'drive',
        'supportsAllDrives': 'true',
        'includeItemsFromAllDrives': 'true',
        'orderBy': 'modifiedTime desc',
        'fields': 'files(id,name,mimeType,modifiedTime,size)',
      }),
      allowUserPrompt: true,
    );

    final payload = _decodeJsonMap(response.body);
    final rawFiles = payload['files'];
    if (rawFiles is! List) {
      return const <DriveFileReference>[];
    }

    final files = rawFiles
        .whereType<Map>()
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .map(DriveFileReference.fromJson)
        .where((file) => file.id.isNotEmpty && file.name.isNotEmpty)
        .where((file) => file.isImportable)
        .toList(growable: false);

    files.sort((left, right) {
      final leftTime = left.modifiedTime;
      final rightTime = right.modifiedTime;
      if (leftTime == null && rightTime == null) {
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      }
      if (leftTime == null) {
        return 1;
      }
      if (rightTime == null) {
        return -1;
      }
      return rightTime.compareTo(leftTime);
    });

    return files;
  }

  Future<void> selectFile(DriveFileReference file) async {
    await initialize();
    _selectedFile = file;
    await _preferences.setString(_selectedFileKey, jsonEncode(file.toJson()));
  }

  Future<DriveDownloadResult> syncSelectedFile({
    required bool allowUserPrompt,
    bool forceDownload = false,
  }) async {
    await initialize();

    final previousSelection = _selectedFile;
    if (previousSelection == null) {
      throw const DriveSyncException('Nessun file Drive selezionato.');
    }

    DriveFileReference currentFile;
    try {
      currentFile = await _fetchFileMetadata(
        previousSelection.id,
        allowUserPrompt: allowUserPrompt,
      );
    } catch (error) {
      final cachedBytes = await _loadCachedBytes(previousSelection);
      if (cachedBytes != null) {
        _lastSyncAt = DateTime.now();
        await _preferences.setString(
          _lastSyncAtKey,
          _lastSyncAt!.toIso8601String(),
        );
        return DriveDownloadResult(
          file: previousSelection,
          bytes: cachedBytes,
          extension: previousSelection.preferredExtension,
          wasUpToDate: false,
          usedCachedFile: true,
        );
      }
      rethrow;
    }

    await selectFile(currentFile);

    final sameVersion =
        !forceDownload &&
        previousSelection.modifiedTime != null &&
        currentFile.modifiedTime != null &&
        previousSelection.modifiedTime == currentFile.modifiedTime;

    _lastSyncAt = DateTime.now();
    await _preferences.setString(_lastSyncAtKey, _lastSyncAt!.toIso8601String());

    if (sameVersion) {
      return DriveDownloadResult(
        file: currentFile,
        extension: currentFile.preferredExtension,
        wasUpToDate: true,
        usedCachedFile: false,
      );
    }

    try {
      final bytes = await _downloadBytes(
        currentFile,
        allowUserPrompt: allowUserPrompt,
      );
      await _writeCache(currentFile, bytes);
      return DriveDownloadResult(
        file: currentFile,
        bytes: bytes,
        extension: currentFile.preferredExtension,
        wasUpToDate: false,
        usedCachedFile: false,
      );
    } catch (error) {
      final cachedBytes = await _loadCachedBytes(currentFile);
      if (cachedBytes != null) {
        return DriveDownloadResult(
          file: currentFile,
          bytes: cachedBytes,
          extension: currentFile.preferredExtension,
          wasUpToDate: false,
          usedCachedFile: true,
        );
      }
      rethrow;
    }
  }

  void _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn(user: final user):
        _currentUser = user;
      case GoogleSignInAuthenticationEventSignOut():
        _currentUser = null;
    }
  }

  DriveFileReference? _loadStoredSelection() {
    final rawValue = _preferences.getString(_selectedFileKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map) {
        return null;
      }
      final mapped = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final file = DriveFileReference.fromJson(mapped);
      return file.id.isEmpty ? null : file;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  DateTime? _loadStoredLastSyncAt() {
    final rawValue = _preferences.getString(_lastSyncAtKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(rawValue);
  }

  Future<DriveFileReference> _fetchFileMetadata(
    String fileId, {
    required bool allowUserPrompt,
  }) async {
    final response = await _authorizedGet(
      Uri.https(
        'www.googleapis.com',
        '$_driveFilesEndpoint/$fileId',
        <String, String>{
          'supportsAllDrives': 'true',
          'fields': 'id,name,mimeType,modifiedTime,size',
        },
      ),
      allowUserPrompt: allowUserPrompt,
    );

    final payload = DriveFileReference.fromJson(_decodeJsonMap(response.body));
    if (!payload.isImportable) {
      throw const FormatException(
        'Il file Drive selezionato non è un CSV, XLSX o Google Sheet.',
      );
    }
    return payload;
  }

  Future<Uint8List> _downloadBytes(
    DriveFileReference file, {
    required bool allowUserPrompt,
  }) async {
    final uri = file.isGoogleSheet
        ? Uri.https(
            'www.googleapis.com',
            '$_driveFilesEndpoint/${file.id}/export',
            <String, String>{
              'mimeType': _xlsxMimeType,
            },
          )
        : Uri.https(
            'www.googleapis.com',
            '$_driveFilesEndpoint/${file.id}',
            <String, String>{
              'alt': 'media',
              'supportsAllDrives': 'true',
            },
          );

    final response = await _authorizedGet(
      uri,
      allowUserPrompt: allowUserPrompt,
    );
    return response.bodyBytes;
  }

  Future<http.Response> _authorizedGet(
    Uri uri, {
    required bool allowUserPrompt,
  }) async {
    var headers = await _authorizationHeaders(allowUserPrompt: allowUserPrompt);
    var response = await _httpClient.get(uri, headers: headers);

    if (response.statusCode == 401) {
      final accessToken = _extractAccessToken(headers);
      if (accessToken != null && _currentUser != null) {
        await _currentUser!.authorizationClient.clearAuthorizationToken(
          accessToken: accessToken,
        );
        headers = await _authorizationHeaders(allowUserPrompt: allowUserPrompt);
        response = await _httpClient.get(uri, headers: headers);
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DriveSyncException(_buildDriveHttpError(response));
    }

    return response;
  }

  Future<Map<String, String>> _authorizationHeaders({
    required bool allowUserPrompt,
  }) async {
    final user = await _ensureAuthenticatedUser(
      allowUserPrompt: allowUserPrompt,
    );
    final headers = await user.authorizationClient.authorizationHeaders(
      const <String>[_driveReadonlyScope],
      promptIfNecessary: allowUserPrompt,
    );

    if (headers == null) {
      throw DriveSyncException(
        allowUserPrompt
            ? 'Autorizzazione Google Drive non concessa.'
            : 'Autorizzazione Google Drive non disponibile in background.',
      );
    }

    return headers;
  }

  Future<GoogleSignInAccount> _ensureAuthenticatedUser({
    required bool allowUserPrompt,
  }) async {
    if (_currentUser != null) {
      return _currentUser!;
    }

    final lightweightAuth = _googleSignIn.attemptLightweightAuthentication();
    if (lightweightAuth != null) {
      try {
        _currentUser = await lightweightAuth;
      } on GoogleSignInException {
        _currentUser = null;
      }
    }

    if (_currentUser != null) {
      return _currentUser!;
    }

    if (!allowUserPrompt) {
      throw const DriveSyncException('Account Google non collegato.');
    }

    if (_serverClientId.isEmpty) {
      throw const DriveSyncException(
        'Configura GOOGLE_DRIVE_SERVER_CLIENT_ID in android/gradle.properties prima di collegare Drive.',
      );
    }

    try {
      _currentUser = await _googleSignIn.authenticate(
        scopeHint: const <String>[_driveReadonlyScope],
      );
      return _currentUser!;
    } on GoogleSignInException catch (error) {
      throw DriveSyncException(_describeGoogleSignInError(error));
    }
  }

  Future<File> _cacheFileFor(DriveFileReference file) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final cacheDirectory = Directory('${documentsDirectory.path}/drive_cache');
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }

    return File('${cacheDirectory.path}/${file.id}.${file.preferredExtension}');
  }

  Future<void> _writeCache(DriveFileReference file, Uint8List bytes) async {
    final cachedFile = await _cacheFileFor(file);
    await cachedFile.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> _loadCachedBytes(DriveFileReference file) async {
    final cachedFile = await _cacheFileFor(file);
    if (!await cachedFile.exists()) {
      return null;
    }
    final bytes = await cachedFile.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }

  Map<String, dynamic> _decodeJsonMap(String rawBody) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      throw const FormatException('Risposta Drive non valida.');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  String? _extractAccessToken(Map<String, String> headers) {
    final authorizationHeader = headers['Authorization'];
    if (authorizationHeader == null || !authorizationHeader.startsWith('Bearer ')) {
      return null;
    }
    return authorizationHeader.substring('Bearer '.length).trim();
  }

  String _buildDriveHttpError(http.Response response) {
    try {
      final payload = _decodeJsonMap(response.body);
      final error = payload['error'];
      if (error is Map) {
        final message = error['message']?.toString().trim();
        if (message != null && message.isNotEmpty) {
          return 'Google Drive ha risposto con errore ${response.statusCode}: $message';
        }
      }
    } on Object {
      // Ignore JSON decoding issues and fall back to the HTTP code.
    }

    return 'Google Drive ha risposto con errore ${response.statusCode}.';
  }

  String _describeGoogleSignInError(GoogleSignInException error) {
    return switch (error.code) {
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Configurazione Google Sign-In non valida. Controlla package name, SHA-1 e GOOGLE_DRIVE_SERVER_CLIENT_ID.',
      GoogleSignInExceptionCode.canceled =>
        'Accesso Google annullato. Se il popup si chiude subito dopo aver scelto l’account, di solito è una configurazione OAuth errata: package name, SHA-1, client ID web o utente test.',
      GoogleSignInExceptionCode.interrupted =>
        'Accesso Google interrotto. Riprova.',
      _ => error.description?.trim().isNotEmpty == true
          ? error.description!.trim()
          : 'Accesso Google non riuscito.',
    };
  }

  String _normalizeServerClientId(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty || value.startsWith('INSERISCI_')) {
      return '';
    }
    return value;
  }
}
