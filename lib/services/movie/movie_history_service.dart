import 'dart:convert';

import 'package:kazutv/modules/movie/movie_history.dart';
import 'package:kazutv/services/storage/storage.dart';

/// 影视播放进度的持久化。
///
/// 存 `Box<String>`（key = `sourceKey:vodId`，value = 记录 JSON），理由与影视源
/// 列表相同：**不引入 Hive adapter 的代码生成步骤** —— 本机跑不了 build_runner
/// （`native_toolchain_c` 在中文代码页下的缺陷），任何需要重新生成 `.g.dart`
/// 的方案都意味着构建直接断掉。
class MovieHistoryService {
  MovieHistoryService._();

  /// 最多保留多少条。
  ///
  /// 影视片数量没有上限，不设闸门这个 Box 会无限长下去。超出就按 updatedAt
  /// 淘汰最旧的。
  static const maxRecords = 200;

  /// 按最近观看排序。
  static List<MoviePlayProgress> all() {
    final records = <MoviePlayProgress>[];
    for (final raw in GStorage.movieHistories.values) {
      final parsed = _decode(raw);
      if (parsed != null) records.add(parsed);
    }
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records;
  }

  static MoviePlayProgress? find(String sourceKey, String vodId) {
    if (sourceKey.isEmpty || vodId.isEmpty) return null;
    return _decode(
      GStorage.movieHistories.get(MoviePlayProgress.keyOf(sourceKey, vodId)),
    );
  }

  /// 写入一条进度。同一个影片重复调用只会覆盖（key 是 source+vodId）。
  static Future<void> save(MoviePlayProgress progress) async {
    if (progress.sourceKey.isEmpty || progress.vodId.isEmpty) return;
    await GStorage.movieHistories
        .put(progress.key, json.encode(progress.toJson()));
    await _pruneIfNeeded();
  }

  static Future<void> remove(String sourceKey, String vodId) async {
    if (sourceKey.isEmpty || vodId.isEmpty) return;
    await GStorage.movieHistories
        .delete(MoviePlayProgress.keyOf(sourceKey, vodId));
  }

  static Future<void> clearAll() async {
    await GStorage.movieHistories.clear();
  }

  static int get count => GStorage.movieHistories.length;

  static Future<void> _pruneIfNeeded() async {
    final box = GStorage.movieHistories;
    if (box.length <= maxRecords) return;

    final entries = <MapEntry<String, int>>[];
    for (final key in box.keys) {
      final parsed = _decode(box.get(key));
      entries.add(MapEntry('$key', parsed?.updatedAt ?? 0));
    }
    entries.sort((a, b) => a.value.compareTo(b.value));

    for (var i = 0; i < entries.length - maxRecords; i++) {
      await box.delete(entries[i].key);
    }
  }

  /// 单条坏数据不该让整个历史读不出来，所以吞掉解析异常返回 null。
  static MoviePlayProgress? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return MoviePlayProgress.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }
}
