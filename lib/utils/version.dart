import 'dart:math';

/// 把版本号拆成可比较的数字段。
///
/// 上游原实现直接 `int.parse`，遇到 `v1.4`、`1.0.0-beta` 这类写法会抛
/// [FormatException]。这里做容错处理：
///   - 去掉前缀 `v` / `V`
///   - 去掉构建元数据（`+` 之后）与预发布标记（`-` 之后）
///   - 无法解析的段按 0 处理
///
/// 注意：本函数同时服务于两处调用，语义需保持兼容 ——
///   1. 应用自身的更新检查（`auto_updater.dart`），远端是 GitHub tag，
///      常带 `v` 前缀；
///   2. 规则插件版本比较（`plugins_controller.dart`），两端都是规则里的
///      纯数字版本号。
List<int> _versionSegments(String version) {
  var normalized = version.trim();
  if (normalized.isEmpty) {
    return const [0];
  }

  if (normalized.startsWith('v') || normalized.startsWith('V')) {
    normalized = normalized.substring(1);
  }

  // 0.1.0+1        -> 0.1.0
  // 1.0.0-beta.1   -> 1.0.0
  for (final separator in const ['+', '-']) {
    final index = normalized.indexOf(separator);
    if (index >= 0) {
      normalized = normalized.substring(0, index);
    }
  }

  return normalized
      .split('.')
      .map((segment) => int.tryParse(segment.trim()) ?? 0)
      .toList();
}

/// 远端版本是否比本地版本新。
bool needUpdate(String localVersion, String remoteVersion) {
  final localVersionList = _versionSegments(localVersion);
  final remoteVersionList = _versionSegments(remoteVersion);
  final maxLength = max(localVersionList.length, remoteVersionList.length);
  for (var i = 0; i < maxLength; i++) {
    final localSegment = i < localVersionList.length ? localVersionList[i] : 0;
    final remoteSegment = i < remoteVersionList.length
        ? remoteVersionList[i]
        : 0;
    if (remoteSegment > localSegment) {
      return true;
    } else if (remoteSegment < localSegment) {
      return false;
    }
  }
  return false;
}
