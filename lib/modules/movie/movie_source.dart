/// 影视源配置。
///
/// 字段与 LibreTV 的 `{name, url, detail, isAdult}` 对齐（本类的 `api` 对应它的 `url`），
/// 这样它的 `LibreTV-SourceList` JSON 和 TVBOX 配置都能直接导入导出。
class MovieSource {
  /// 唯一标识：`builtin_dytt` / `custom_0` / `sub_<hash>`
  final String key;

  /// 显示名
  final String name;

  /// 采集接口根地址，形如 `https://x.com/api.php/provide/vod`（不带尾斜杠）。
  /// 只给域名也能用 —— [normalizedApi] 会补全路径。
  final String api;

  /// 详情页根地址，可选。用于接口失败时的 HTML 兜底抓取。
  final String detail;

  /// 成人内容标记（参与过滤）
  final bool isAdult;

  /// 是否参与聚合搜索
  final bool enabled;

  /// 展示顺序
  final int order;

  /// 最近一次探活成功时间戳（0 = 从未）
  final int lastOkAt;

  /// 最近一次探活耗时毫秒（-1 = 失败）
  final int lastLatencyMs;

  const MovieSource({
    required this.key,
    required this.name,
    required this.api,
    this.detail = '',
    this.isAdult = false,
    this.enabled = true,
    this.order = 0,
    this.lastOkAt = 0,
    this.lastLatencyMs = -1,
  });

  /// 补齐 `api` 到可请求的完整路径。
  ///
  /// 兼容两种写法：
  ///   - 只给域名          `https://x.com`            -> `https://x.com/api.php/provide/vod`
  ///   - 给到接口根        `https://x.com/api.php/provide/vod`
  ///   - 带尾斜杠/完整查询  `https://x.com/api.php/provide/vod/` -> 去掉尾斜杠
  String get normalizedApi {
    var base = api.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.contains('://') && !base.substring(base.indexOf('://') + 3).contains('/')) {
      return '$base/api.php/provide/vod';
    }
    return base;
  }

  /// 是否已配齐最小可用字段
  bool get isUsable => key.isNotEmpty && name.isNotEmpty && api.trim().isNotEmpty;

  MovieSource copyWith({
    String? key,
    String? name,
    String? api,
    String? detail,
    bool? isAdult,
    bool? enabled,
    int? order,
    int? lastOkAt,
    int? lastLatencyMs,
  }) {
    return MovieSource(
      key: key ?? this.key,
      name: name ?? this.name,
      api: api ?? this.api,
      detail: detail ?? this.detail,
      isAdult: isAdult ?? this.isAdult,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      lastOkAt: lastOkAt ?? this.lastOkAt,
      lastLatencyMs: lastLatencyMs ?? this.lastLatencyMs,
    );
  }

  /// 从 LibreTV 源列表的条目构造。
  ///
  /// LibreTV 的字段名是 `url`（不是 `api`），这里做一次映射；
  /// TVBOX 配置里同样是 `url` 或 `api`，两种都认。
  factory MovieSource.fromSourceListJson(
    Map<String, dynamic> json, {
    required String key,
    int order = 0,
  }) {
    String pick(List<String> names) {
      for (final n in names) {
        final v = json[n];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    return MovieSource(
      key: key,
      name: pick(['name', 'title']),
      api: pick(['api', 'url']),
      detail: pick(['detail', 'ext']),
      isAdult: json['isAdult'] == true || json['adult'] == true,
      enabled: json['enabled'] != false,
      order: order,
    );
  }

  /// 导出成 LibreTV / TVBOX 都能吃的格式。
  Map<String, dynamic> toSourceListJson() => {
        'name': name,
        'url': api,
        if (detail.isNotEmpty) 'detail': detail,
        if (isAdult) 'isAdult': true,
      };

  @override
  String toString() => 'MovieSource($key, $name, $api)';
}
