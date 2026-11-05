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

/// A write refused because the file changed since it was last looked at —
/// another phone uploaded in between.
class GithubConflictException extends GithubApiException {
  GithubConflictException(super.statusCode, super.message);
}

/// GitHub refused a request (401) but, asked straight after, says the
/// token itself is fine — so there's nothing to reconnect. Retried on the
/// next run.
class GithubAuthGlitchException implements Exception {}

class GithubFile {
  GithubFile({required this.sha, required this.contentBytes});

  final String sha;
  final Uint8List contentBytes;
}

class GithubCommit {
  GithubCommit({required this.sha, required this.message, required this.date});

  final String sha;
  final String message;
  final DateTime date;
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

  /// Whether GitHub still accepts [token] at all — the one question that
  /// decides "Reconnect GitHub". Throws on anything but a clear yes or no
  /// (offline, GitHub down), which answers neither.
  Future<bool> tokenWorks(String token) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/user'),
      headers: _headers(token),
    );
    if (res.statusCode == 401) return false;
    _throwIfError(res);
    return true;
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
  ///
  /// [ref] reads it as of that commit instead of the branch's latest.
  Future<GithubFile?> getFile(
    String token,
    String owner,
    String repo,
    String path, {
    String? ref,
  }) async {
    final uri = Uri.parse('$_baseUrl/repos/$owner/$repo/contents/$path')
        .replace(queryParameters: ref == null ? null : {'ref': ref});
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

  /// The blob sha of [path] as of commit [ref] — never its content, so a
  /// large backup isn't downloaded just to learn it. Null if the file
  /// didn't exist there.
  Future<String?> getFileSha(
    String token,
    String owner,
    String repo,
    String path, {
    required String ref,
  }) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/repos/$owner/$repo/contents/$path')
          .replace(queryParameters: {'ref': ref}),
      headers: {
        ..._headers(token),
        'Accept': 'application/vnd.github.object+json',
      },
    );
    if (res.statusCode == 404) return null;
    _throwIfError(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['sha'] as String;
  }

  /// The newest commit touching [path] — one small request, which is what
  /// keeps hourly "anything new?" checks cheap. Null when there's none: no
  /// such file yet, an empty repo (GitHub answers 409 for those), or no
  /// repo at all.
  Future<GithubCommit?> getLatestCommit(
    String token,
    String owner,
    String repo,
    String path,
  ) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/repos/$owner/$repo/commits')
          .replace(queryParameters: {'path': path, 'per_page': '1'}),
      headers: _headers(token),
    );
    if (res.statusCode == 404 || res.statusCode == 409) return null;
    _throwIfError(res);
    final commits = jsonDecode(res.body) as List<dynamic>;
    if (commits.isEmpty) return null;
    final latest = commits.first as Map<String, dynamic>;
    final commit = latest['commit'] as Map<String, dynamic>;
    final committer = commit['committer'] as Map<String, dynamic>;
    return GithubCommit(
      sha: latest['sha'] as String,
      message: commit['message'] as String,
      date: DateTime.parse(committer['date'] as String),
    );
  }

  /// Creates or updates [path] in [owner]/[repo] and returns the new
  /// commit's sha. [existingSha] is the blob being replaced (null to
  /// create): GitHub only writes if the file is still exactly that, and
  /// otherwise this throws [GithubConflictException].
  Future<String> putFile(
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
    try {
      _throwIfError(res);
    } on GithubApiException catch (e) {
      // 409: the file isn't at existingSha any more. 422 naming the sha:
      // it was created meanwhile, so a create without one is refused.
      final conflict =
          e.statusCode == 409 ||
          (e.statusCode == 422 && e.message.contains('sha'));
      if (conflict) throw GithubConflictException(e.statusCode, e.message);
      rethrow;
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['commit'] as Map<String, dynamic>)['sha'] as String;
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
