import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class DriveApiException implements Exception {
  DriveApiException(this.statusCode, this.reason, this.message);

  final int statusCode;

  /// Google's own reason: `storageQuotaExceeded`, `rateLimitExceeded`, …
  final String? reason;
  final String message;

  @override
  String toString() => 'DriveApiException($statusCode, $reason): $message';
}

/// One Drive file, with the fields Connector asks for.
class DriveFile {
  DriveFile.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      createdTime = json['createdTime'] == null
          ? null
          : DateTime.parse(json['createdTime'] as String).toUtc(),
      trashed = json['trashed'] as bool? ?? false,
      appProperties = {
        for (final e
            in (json['appProperties'] as Map<String, dynamic>? ?? const {})
                .entries)
          e.key: e.value as String,
      };

  final String id;
  final DateTime? createdTime;
  final bool trashed;
  final Map<String, String> appProperties;
}

/// Thin wrapper over the Drive v3 REST API, token passed per call like
/// `GithubApi`. Connector only ever has `drive.file`, so every list sees
/// just the files it created.
class DriveApi {
  DriveApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _files = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';
  static const _fileFields = 'id,createdTime,trashed,appProperties';
  static const folderMime = 'application/vnd.google-apps.folder';

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  static String _tagged(String key, String value) =>
      "appProperties has { key='$key' and value='$value' }";

  /// The oldest untrashed folder tagged [tag], or null.
  Future<String?> findFolder(String token, String tag) async {
    final files = await _list(token, {
      'q':
          "${_tagged('connector', tag)} and mimeType='$folderMime' "
          'and trashed = false',
      'orderBy': 'createdTime',
      'pageSize': '1',
      'fields': 'files(id)',
    });
    return files.files.isEmpty ? null : files.files.first.id;
  }

  Future<String> createFolder(String token, String name, String tag) async {
    final res = await _client.post(
      Uri.parse(_files).replace(queryParameters: {'fields': 'id'}),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'mimeType': folderMime,
        'appProperties': {'connector': tag},
      }),
    );
    _throwIfError(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  }

  /// Null when it's gone.
  Future<DriveFile?> getFile(String token, String id) async {
    final res = await _client.get(
      Uri.parse(
        '$_files/$id',
      ).replace(queryParameters: {'fields': _fileFields}),
      headers: _headers(token),
    );
    if (res.statusCode == 404) return null;
    _throwIfError(res);
    return DriveFile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Untrashed files tagged `connector=[tag]`, newest first by Drive's own
  /// `createdTime`; only those created after [createdAfter] when given.
  /// All pages, or just the first [pageSize] with [firstPageOnly].
  Future<List<DriveFile>> listTagged(
    String token,
    String tag, {
    DateTime? createdAfter,
    int pageSize = 100,
    bool firstPageOnly = false,
  }) async {
    final query = [
      _tagged('connector', tag),
      'trashed = false',
      if (createdAfter != null)
        "createdTime > '${createdAfter.toUtc().toIso8601String()}'",
    ].join(' and ');
    final all = <DriveFile>[];
    String? pageToken;
    do {
      final page = await _list(token, {
        'q': query,
        'orderBy': 'createdTime desc',
        'pageSize': '$pageSize',
        'fields': 'nextPageToken,files($_fileFields)',
        'pageToken': ?pageToken,
      });
      all.addAll(page.files);
      pageToken = page.next;
    } while (pageToken != null && !firstPageOnly);
    return all;
  }

  /// Creates a file with its metadata and content in one resumable upload
  /// session — no size cap, and the file never exists without its tags.
  Future<DriveFile> upload(
    String token, {
    required String name,
    required String parentId,
    required Map<String, String> appProperties,
    required List<int> bytes,
  }) async {
    final start = await _client.post(
      Uri.parse(_upload).replace(
        queryParameters: {'uploadType': 'resumable', 'fields': _fileFields},
      ),
      headers: {
        ..._headers(token),
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/json',
        'X-Upload-Content-Length': '${bytes.length}',
      },
      body: jsonEncode({
        'name': name,
        'parents': [parentId],
        'mimeType': 'application/json',
        'appProperties': appProperties,
      }),
    );
    _throwIfError(start);
    final session = start.headers['location'];
    if (session == null) {
      throw DriveApiException(start.statusCode, null, 'No upload session.');
    }
    final res = await _client.put(
      Uri.parse(session),
      headers: {'Content-Type': 'application/json'},
      body: bytes,
    );
    _throwIfError(res);
    return DriveFile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Null when it's gone.
  Future<Uint8List?> download(String token, String id) async {
    final res = await _client.get(
      Uri.parse('$_files/$id').replace(queryParameters: {'alt': 'media'}),
      headers: _headers(token),
    );
    if (res.statusCode == 404) return null;
    _throwIfError(res);
    return res.bodyBytes;
  }

  /// Permanent — trash would still count against the user's quota. Gone
  /// already is fine.
  Future<void> delete(String token, String id) async {
    final res = await _client.delete(
      Uri.parse('$_files/$id'),
      headers: _headers(token),
    );
    if (res.statusCode == 404) return;
    _throwIfError(res);
  }

  Future<({List<DriveFile> files, String? next})> _list(
    String token,
    Map<String, String> query,
  ) async {
    final res = await _client.get(
      Uri.parse(_files).replace(queryParameters: {...query, 'spaces': 'drive'}),
      headers: _headers(token),
    );
    _throwIfError(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      files: [
        for (final f in json['files'] as List<dynamic>? ?? const [])
          DriveFile.fromJson(f as Map<String, dynamic>),
      ],
      next: json['nextPageToken'] as String?,
    );
  }

  void _throwIfError(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String? reason;
    var message = res.body;
    try {
      final error =
          (jsonDecode(res.body) as Map<String, dynamic>)['error']
              as Map<String, dynamic>;
      message = error['message'] as String? ?? message;
      final errors = error['errors'] as List<dynamic>?;
      if (errors != null && errors.isNotEmpty) {
        reason = (errors.first as Map<String, dynamic>)['reason'] as String?;
      }
    } catch (_) {
      // Not Google's JSON error shape — keep the raw text.
    }
    throw DriveApiException(res.statusCode, reason, message);
  }
}
