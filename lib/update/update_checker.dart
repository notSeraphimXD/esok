import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.url,
  });

  final String version;
  final String currentVersion;
  final String url;
}

class UpdateCheckResult {
  const UpdateCheckResult({this.update, this.error});

  final UpdateInfo? update;
  final String? error;

  bool get hasUpdate => update != null;
}

class UpdateChecker {
  UpdateChecker._();

  static const _repository = 'notSeraphimXD/esok';
  static const _lastCheckKey = 'update_last_check';
  static const _promptedKey = 'update_prompted_version';
  static const _checkInterval = Duration(hours: 12);

  static Future<UpdateCheckResult> check({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
    if (!force && now - lastCheck < _checkInterval.inMilliseconds) {
      return const UpdateCheckResult();
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final current = normalizeVersion(package.version);
      final response = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/$_repository/releases/latest',
            ),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Esok/$current',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          error: 'GitHub tidak merespons (${response.statusCode}).',
        );
      }
      await prefs.setInt(_lastCheckKey, now);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const UpdateCheckResult(
          error: 'Format data rilis tidak dikenali.',
        );
      }
      if (decoded['draft'] == true || decoded['prerelease'] == true) {
        return const UpdateCheckResult();
      }

      final tag = decoded['tag_name']?.toString();
      final url = decoded['html_url']?.toString();
      if (tag == null ||
          tag.trim().isEmpty ||
          url == null ||
          url.trim().isEmpty) {
        return const UpdateCheckResult(
          error: 'Data rilis tidak lengkap.',
        );
      }

      final latest = normalizeVersion(tag);
      if (!isNewerVersion(latest, current)) {
        return const UpdateCheckResult();
      }

      final prompted = prefs.getString(_promptedKey);
      if (!force && prompted == latest) {
        return const UpdateCheckResult();
      }

      return UpdateCheckResult(
        update: UpdateInfo(
          version: latest,
          currentVersion: current,
          url: url,
        ),
      );
    } catch (error, stack) {
      debugPrint('Update check failed: $error\n$stack');
      return const UpdateCheckResult(
        error: 'Tidak dapat memeriksa pembaruan.',
      );
    }
  }

  static Future<void> markPrompted(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_promptedKey, version);
  }

  static Future<bool> openRelease(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  static String normalizeVersion(String value) {
    var normalized = value.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }
    normalized = normalized.split('+').first;
    normalized = normalized.split('-').first;
    return normalized;
  }

  static bool isNewerVersion(String latest, String current) {
    final latestParts = _versionParts(latest);
    final currentParts = _versionParts(current);
    final length = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;
    for (var index = 0; index < length; index++) {
      final latestPart = index < latestParts.length ? latestParts[index] : 0;
      final currentPart = index < currentParts.length ? currentParts[index] : 0;
      if (latestPart != currentPart) return latestPart > currentPart;
    }
    return false;
  }

  static List<int> _versionParts(String value) {
    return normalizeVersion(value).split('.').map((part) {
      final match = RegExp(r'^\d+').firstMatch(part);
      return match == null ? 0 : int.parse(match.group(0)!);
    }).toList(growable: false);
  }
}
