import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazutv/modules/movie/movie_detail.dart';
import 'package:kazutv/modules/movie/movie_item.dart';
import 'package:kazutv/modules/movie/movie_source.dart';
import 'package:kazutv/request/core/dio_factory.dart';
import 'package:kazutv/request/core/network_error_mapper.dart';

/// 苹果CMS（maccms）采集接口客户端。
///
/// 协议速查：
///   搜索  `{api}?ac=videolist&wd={关键词}&pg={页码}`
///   详情  `{api}?ac=videolist&ids={vodId}`
/// 两者返回同一个信封：`{code, msg, page, pagecount, limit, total, list: [...]}`，
/// `code == 1` 为成功（有的源给字符串 "1"，所以两种都认）。
///
/// 关于 HTML 兜底：`detail` 页抓取暂未实现 —— 实测的 9 个源接口都可用，
/// 等真遇到只开网页不给接口的源再加（见设计文档 §5.1）。
class AppleCmsApi {
  AppleCmsApi._();

  /// 搜索超时。对齐 LibreTV 的 SEARCH_SOURCE_TIMEOUT_MS = 8000。
  static const searchTimeout = Duration(seconds: 8);

  /// 详情超时，给宽一点
  static const detailTimeout = Duration(seconds: 10);

  /// 搜索。
  ///
  /// 失败时抛异常，由调用方（聚合搜索）按源隔离处理。
  static Future<CmsSearchPage> search(
    MovieSource source,
    String keyword,
    int page, {
    CancelToken? cancelToken,
  }) async {
    if (keyword.trim().isEmpty) return CmsSearchPage.empty;

    final data = await _get(
      source,
      {
        'ac': 'videolist',
        'wd': keyword.trim(),
        'pg': page < 1 ? 1 : page,
      },
      searchTimeout,
      cancelToken,
    );

    return parseSearchPage(data, source, page);
  }

  /// 详情。源站找不到该 id 时返回 null。
  static Future<MovieDetail?> detail(
    MovieSource source,
    String vodId, {
    CancelToken? cancelToken,
  }) async {
    if (vodId.trim().isEmpty) return null;

    final data = await _get(
      source,
      {'ac': 'videolist', 'ids': vodId.trim()},
      detailTimeout,
      cancelToken,
    );

    final list = _asList(data['list']);
    if (list.isEmpty) return null;
    return parseDetailItem(list.first, source);
  }

  // ------------------------------------------------------- 纯解析（可离线单测）

  /// 解析搜索响应。纯函数，不碰网络 —— 便于写回归测试与离线验证脚本。
  static CmsSearchPage parseSearchPage(
    Map<String, dynamic> json,
    MovieSource source,
    int page,
  ) {
    final list = _asList(json['list']);
    return CmsSearchPage(
      items: list
          .map((e) => parseSearchItem(e, source))
          .where((e) => e.vodId.isNotEmpty && e.name.isNotEmpty)
          .toList(),
      page: page,
      pageCount: _asInt(json['pagecount']),
      total: _asInt(json['total']),
    );
  }

  /// 解析详情响应；`list` 为空说明源站没有这个 id。
  static MovieDetail? parseDetailResponse(
    Map<String, dynamic> json,
    MovieSource source,
  ) {
    final list = _asList(json['list']);
    if (list.isEmpty) return null;
    return parseDetailItem(list.first, source);
  }

  // ---------------------------------------------------------------- 请求

  static Future<Map<String, dynamic>> _get(
    MovieSource source,
    Map<String, dynamic> query,
    Duration timeout,
    CancelToken? cancelToken,
  ) async {
    final headers = <String, dynamic>{
      'Accept': 'application/json',
      // 部分源要求 Referer 才放行
      if (source.detail.trim().isNotEmpty) 'referer': source.detail.trim(),
    };

    try {
      final response = await DioFactory.apiDio.get<dynamic>(
        source.normalizedApi,
        queryParameters: query,
        options: Options(
          responseType: ResponseType.json,
          headers: headers,
          receiveTimeout: timeout,
          sendTimeout: timeout,
        ),
        cancelToken: cancelToken,
      );

      final raw = response.data;
      Map<String, dynamic>? json;
      if (raw is Map) {
        json = Map<String, dynamic>.from(raw);
      } else if (raw is String) {
        final decoded = _tryDecode(raw);
        if (decoded != null) json = decoded;
      }

      if (json == null) {
        throw AppleCmsException('响应不是合法 JSON（${source.name}）');
      }

      // code 可能是 int 1 也可能是 "1"；有的源干脆不给 code
      final code = json['code'];
      if (code != null && _asInt(code) != 1) {
        throw AppleCmsException(
          '源站返回失败：${json['msg'] ?? code}（${source.name}）',
        );
      }

      return json;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  static Map<String, dynamic>? _tryDecode(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 源站偶尔会在 JSON 前后带 BOM / 提示文字，退一步找第一个 {
    }
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(trimmed.substring(start, end + 1));
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  // ---------------------------------------------------------------- 解析

  static MovieSearchItem parseSearchItem(
    Map<String, dynamic> vod,
    MovieSource source,
  ) {
    return MovieSearchItem(
      sourceKey: source.key,
      sourceName: source.name,
      vodId: _asString(vod['vod_id']),
      name: _asString(vod['vod_name']),
      pic: _asString(vod['vod_pic']),
      typeName: _asString(vod['type_name'] ?? vod['vod_class']),
      year: _asString(vod['vod_year']),
      area: _asString(vod['vod_area']),
      remarks: _asString(vod['vod_remarks']),
      score: _asString(vod['vod_score']),
      isAdult: source.isAdult,
    );
  }

  static MovieDetail parseDetailItem(Map<String, dynamic> vod, MovieSource source) {
    return MovieDetail(
      sourceKey: source.key,
      vodId: _asString(vod['vod_id']),
      name: _asString(vod['vod_name']),
      pic: _asString(vod['vod_pic']),
      content: stripHtml(_asString(vod['vod_content'])),
      typeName: _asString(vod['type_name'] ?? vod['vod_class']),
      year: _asString(vod['vod_year']),
      area: _asString(vod['vod_area']),
      remarks: _asString(vod['vod_remarks']),
      score: double.tryParse(_asString(vod['vod_score'])) ?? 0,
      actors: _splitNames(_asString(vod['vod_actor'])),
      directors: _splitNames(_asString(vod['vod_director'])),
      doubanId: _asString(vod['vod_douban_id']),
      routes: parseRoutes(
        _asString(vod['vod_play_from']),
        _asString(vod['vod_play_url']),
      ),
    );
  }

  /// 解析播放地址。
  ///
  /// 结构：`vod_play_from` 与 `vod_play_url` 都按 `$$$` 切分，**按下标一一对应**；
  /// 每条线路内部按 `#` 切集；每集再按 `$` 切「标题 / 地址」。
  ///
  /// 两个必须做的过滤（实测会踩）：
  ///   1. 地址不以 http 开头的一律丢弃 —— 电影天堂的 `dytt` 线路给的是
  ///      `/share/xxx` 分享页，交给播放器只会黑屏；
  ///   2. 空段丢弃 —— 源站常有多余的 `#`。
  static List<MovieRoute> parseRoutes(String playFrom, String playUrl) {
    if (playUrl.trim().isEmpty) return const [];

    final froms = playFrom.split(r'$$$');
    final groups = playUrl.split(r'$$$');
    final routes = <MovieRoute>[];

    for (var i = 0; i < groups.length; i++) {
      final rawName = i < froms.length ? froms[i].trim() : '';
      final name = rawName.isEmpty ? '线路${i + 1}' : rawName;

      final episodes = <MovieEpisode>[];
      for (final segment in groups[i].split('#')) {
        final seg = segment.trim();
        if (seg.isEmpty) continue;

        final parts = seg.split(r'$');
        final url = (parts.length > 1 ? parts[1] : parts[0]).trim();
        if (!url.startsWith('http')) continue;

        final title = parts.length > 1 ? parts[0].trim() : '';
        episodes.add(MovieEpisode(
          title: title.isEmpty ? '第${episodes.length + 1}集' : title,
          url: url,
        ));
      }

      if (episodes.isNotEmpty) {
        routes.add(MovieRoute(name: name, episodes: episodes));
      }
    }

    return routes;
  }

  // ---------------------------------------------------------------- 工具

  /// 去 HTML 标签。源站的 `vod_content` 基本都带 `<p>` 之类。
  static String stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static List<String> _splitNames(String raw) {
    if (raw.trim().isEmpty) return const [];
    return raw
        .split(RegExp(r'[,，/、]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  static String _asString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}

/// 苹果CMS 协议层的错误（区别于网络异常）。
class AppleCmsException implements Exception {
  final String message;
  const AppleCmsException(this.message);

  @override
  String toString() => message;
}
