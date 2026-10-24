import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class GithubApiException implements Exception {
  GithubApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'GithubApiException($statusCode): $message';
}

class GithubFile {
  GithubFile({required this.sha, required this.contentBytes});

  final String sha;
  final Uint8List contentBytes;
}

/// Thin wrapper over the GitHub REST API (Contents API + repo creation).
/// Every call takes the caller's own OAuth token explicitly rather than
/// holding one internally — [AuthService]/[SecureStore] own the token's
/// lifetime, this class is stateless.
class GithubApi {
  static const _baseUrl = 'https://api.github.com';

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<String> getAuthenticatedLogin(String token) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/user'),
      headers: _headers(token),
    );
    _throwIfError(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['login'] as String;
  }

  Future<bool> repoExists(String token, String owner, String repo) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/repos/$owner/$repo'),
      headers: _headers(token),
    );
    if (res.statusCode == 404) return false;
    _throwIfError(res);
    return true;
  }

  Future<void> createPrivateRepo(
    String token,
    String repoName, {
    String description = 'XPENC backup data. Managed by the Connector app.',
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/user/repos'),
      headers: _headers(token),
      body: jsonEncode({
        'name': repoName,
        'private': true,
        'description': description,
        'auto_init': false,
      }),
    );
    _throwIfError(res);
  }

  /// Returns null if the file doesn't exist yet (fresh repo, first backup).
  ///
  /// The Contents API only inlines `content` for files up to 1 MB; past
  /// that it comes back empty with `encoding: none`, so the bytes are
  /// fetched again via the raw media type (good up to 100 MB). Without this
  /// a large XPENC backup would "restore" as an empty file.
  Future<GithubFile?> getFile(
    String token,
    String owner,
    String repo,
    String path,
  ) async {
    final uri = Uri.parse('$_baseUrl/repos/$owner/$repo/contents/$path');
    final res = await http.get(
      uri,
      headers: {
        ..._headers(token),
        'Accept': 'application/vnd.github.object+json',
      },
    );
    if (res.statusCode == 404) return null;
    _throwIfError(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final sha = json['sha'] as String;
    if (json['encoding'] == 'base64') {
      final base64Content = (json['content'] as String).replaceAll('\n', '');
      return GithubFile(sha: sha, contentBytes: base64Decode(base64Content));
    }
    final raw = await http.get(
      uri,
      headers: {
        ..._headers(token),
        'Accept': 'application/vnd.github.raw+json',
      },
    );
    _throwIfError(raw);
    return GithubFile(sha: sha, contentBytes: raw.bodyBytes);
  }

  /// Creates or updates [path] in [owner]/[repo]. Pass [existingSha] (from
  /// a prior [getFile]) when overwriting — GitHub's Contents API rejects an
  /// update without it as a conflict-prevention measure.
  Future<void> putFile(
    String token,
    String owner,
    String repo,
    String path, {
    required List<int> contentBytes,
    required String commitMessage,
    String? existingSha,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/repos/$owner/$repo/contents/$path'),
      headers: _headers(token),
      body: jsonEncode({
        'message': commitMessage,
        'content': base64Encode(contentBytes),
        'sha': ?existingSha,
      }),
    );
    _throwIfError(res);
  }

  void _throwIfError(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String message = res.body;
    try {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      message = json['message'] as String? ?? res.body;
    } catch (_) {
      // Body wasn't JSON — fall back to the raw text above.
    }
    throw GithubApiException(res.statusCode, message);
  }
}
