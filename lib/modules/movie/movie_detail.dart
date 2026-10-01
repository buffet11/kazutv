/// 影视详情与播放线路。

/// 单集。电影只有一集，剧集/综艺有多集。
class MovieEpisode {
  /// 「HD国语」/「第01集」
  final String title;

  /// 播放地址。苹果CMS 里没有地址的占位集是空串，已被过滤掉。
  final String url;

  const MovieEpisode({required this.title, required this.url});

  /// 能不能直接被播放器打开。
  ///
  /// 实测：苹果CMS 的线路里混着网页中转页（如电影天堂的 `dytt` 线路给的是
  /// `/share/xxx` 分享页），这种交给播放器只会黑屏。m3u8 才是可靠信号。
  bool get playable =>
      url.startsWith('http') &&
      (url.contains('.m3u8') || url.contains('.mp4') || url.contains('.flv'));

  @override
  String toString() => '$title -> $url';
}

/// 一条播放线路（源站叫 `vod_play_from`）。
///
/// 一个影片通常有多条线路，每条线路的集数/清晰度/可播性都不同。
class MovieRoute {
  /// 源站线路名：`dytt` / `dyttm3u8` / `线路一`
  final String name;

  final List<MovieEpisode> episodes;

  const MovieRoute({required this.name, required this.episodes});

  bool get isEmpty => episodes.isEmpty;

  /// 这条线路上有多少集是可以直接播的
  int get playableCount => episodes.where((e) => e.playable).length;

  /// 只要有一集能播，这条线路就值得展示
  bool get playable => playableCount > 0;

  /// 可播集占比，用于在同为「可播」的线路间排序
  double get playableRatio =>
      episodes.isEmpty ? 0 : playableCount / episodes.length;

  MovieEpisode? get firstPlayable {
    for (final e in episodes) {
      if (e.playable) return e;
    }
    return null;
  }

  @override
  String toString() =>
      'MovieRoute($name, ${episodes.length} 集, $playableCount 可播)';
}

/// 影视详情。
class MovieDetail {
  final String sourceKey;
  final String vodId;
  final String name;
  final String pic;

  /// 已去 HTML 标签的简介
  final String content;

  final String typeName;
  final String year;
  final String area;
  final String remarks;
  final double score;
  final List<String> actors;
  final List<String> directors;

  /// 实测可得（`vod_douban_id`），留给未来扩展
  final String doubanId;

  /// 全部线路，保持源站顺序
  final List<MovieRoute> routes;

  const MovieDetail({
    required this.sourceKey,
    required this.vodId,
    required this.name,
    this.pic = '',
    this.content = '',
    this.typeName = '',
    this.year = '',
    this.area = '',
    this.remarks = '',
    this.score = 0,
    this.actors = const [],
    this.directors = const [],
    this.doubanId = '',
    this.routes = const [],
  });

  /// 按**可播性**排序后的线路。
  ///
  /// 这块是踩过坑的：电影天堂的「流浪地球2」第一条线路 `dytt` 给的是网页分享页，
  /// 播放器打不开；第二条 `dyttm3u8` 才是直链。按源站顺序取第一条 = 用户点了一律播不了。
  ///
  /// 排序依据依次是：可播集数占比 -> 可播集数 -> 线路长度。
  List<MovieRoute> get playableRoutes {
    final list = routes.where((r) => r.playable).toList();
    list.sort((a, b) {
      final byRatio = b.playableRatio.compareTo(a.playableRatio);
      if (byRatio != 0) return byRatio;
      final byCount = b.playableCount.compareTo(a.playableCount);
      if (byCount != 0) return byCount;
      return b.episodes.length.compareTo(a.episodes.length);
    });
    return list;
  }

  /// 默认线路：第一条可播的；全不可播时返回 null（UI 应给出明确提示）
  MovieRoute? get bestRoute {
    final list = playableRoutes;
    return list.isEmpty ? null : list.first;
  }

  /// 一条能播的线路都没有
  bool get hasNoPlayableRoute => playableRoutes.isEmpty;

  @override
  String toString() =>
      'MovieDetail($name, $year, ${routes.length} 线路, ${playableRoutes.length} 可播)';
}
