import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../backup/backup_store.dart';
import '../config/app_config.dart';

class ExoCloudApiException implements Exception {
  ExoCloudApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ExoCloudApiException($statusCode): $message';
}

/// One row of `exocloud_backups`.
class ExoCloudRow {
  ExoCloudRow.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      objectPath = json['object_path'] as String,
      createdAt = DateTime.parse(json['created_at'] as String).toUtc(),
      deviceId = json['device_id'] as String,
      deviceName = json['device_name'] as String,
      backupModifiedAt = DateTime.parse(
        json['backup_modified_at'] as String,
      ).toUtc(),
      sourceFile = json['source_file'] as String,
      contentSha = json['content_sha'] as String;

  final String id;
  final String objectPath;
  final DateTime createdAt;
  final String deviceId;
  final String deviceName;
  final DateTime backupModifiedAt;
  final String sourceFile;
  final String contentSha;
}

/// ExoCloud over Supabase's REST and Storage APIs, with an access token
/// passed in — the same in the app and in the background job, which has
/// no Supabase client (see `SessionTokens`). Row-level security and the
/// storage policies keep every call inside the signed-in user's folder.
class ExoCloudApi {
  ExoCloudApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const bucket = 'exocloud';
  static String get _rest => '${AppConfig.supabaseUrl}/rest/v1';
  static String get _storage => '${AppConfig.supabaseUrl}/storage/v1';

  Map<String, String> _headers(String token, {String? contentType}) => {
    'apikey': AppConfig.supabaseAnonKey,
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    'Content-Type': ?contentType,
  };

  /// The newest backup, or a given one by id.
  Future<ExoCloudRow?> row(String token, {String? id}) async {
    final res = await _client.get(
      Uri.parse('$_rest/exocloud_backups').replace(
        queryParameters: {
          'select': '*',
          'id': ?(id == null ? null : 'eq.$id'),
          'order': 'created_at.desc',
          'limit': '1',
        },
      ),
      headers: _headers(token),
    );
    _throwIfError(res);
    final rows = jsonDecode(res.body) as List<dynamic>;
    return rows.isEmpty
        ? null
        : ExoCloudRow.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<void> uploadObject(String token, String path, List<int> bytes) async {
    final res = await _client.post(
      Uri.parse('$_storage/object/$bucket/$path'),
      headers: {
        ..._headers(token, contentType: 'application/octet-stream'),
        'x-upsert': 'false',
      },
      body: bytes,
    );
    _throwIfError(res);
  }

  /// Null when the object is gone.
  Future<Uint8List?> downloadObject(String token, String path) async {
    final res = await _client.get(
      Uri.parse('$_storage/object/authenticated/$bucket/$path'),
      headers: _headers(token),
    );
    if (res.statusCode == 404 || _isStorageNotFound(res)) return null;
    _throwIfError(res);
    return res.bodyBytes;
  }

  Future<void> deleteObjects(String token, List<String> paths) async {
    if (paths.isEmpty) return;
    final res = await _client.delete(
      Uri.parse('$_storage/object/$bucket'),
      headers: _headers(token, contentType: 'application/json'),
      body: jsonEncode({'prefixes': paths}),
    );
    _throwIfError(res);
  }

  /// `exocloud_commit`: makes the uploaded object the latest backup, if
  /// the latest is still [replacingId]. Throws [BackupConflictException]
  /// when it isn't. Returns the new row and the paths retention dropped.
  Future<({ExoCloudRow backup, List<String> removed})> commit(
    String token, {
    required String objectPath,
    required String? replacingId,
    required int sizeBytes,
    required String deviceId,
    required String deviceName,
    required DateTime backupModifiedAt,
    required String sourceFile,
    required String contentSha,
  }) async {
    final res = await _client.post(
      Uri.parse('$_rest/rpc/exocloud_commit'),
      headers: _headers(token, contentType: 'application/json'),
      body: jsonEncode({
        'p_object_path': objectPath,
        'p_replacing': replacingId,
        'p_size_bytes': sizeBytes,
        'p_device_id': deviceId,
        'p_device_name': deviceName,
        'p_backup_modified_at': backupModifiedAt.toUtc().toIso8601String(),
        'p_source_file': sourceFile,
        'p_content_sha': contentSha,
      }),
    );
    if (res.statusCode >= 400 && res.body.contains('exocloud_conflict')) {
      throw const BackupConflictException();
    }
    _throwIfError(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      backup: ExoCloudRow.fromJson(json['backup'] as Map<String, dynamic>),
      removed: [for (final p in json['removed'] as List<dynamic>) p as String],
    );
  }

  /// Storage answers some misses with 400 and a 404 inside the body.
  static bool _isStorageNotFound(http.Response res) =>
      res.statusCode == 400 &&
      (res.body.contains('"404"') || res.body.contains('not_found'));

  void _throwIfError(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    var message = res.body;
    try {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      message = (json['message'] ?? json['error'] ?? res.body).toString();
    } catch (_) {
      // Not JSON — keep the raw text.
    }
    throw ExoCloudApiException(res.statusCode, message);
  }
}
