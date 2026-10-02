import 'package:kazutv/modules/bangumi/bangumi_item.dart';
import 'package:kazutv/modules/download/download_module.dart';
import 'package:kazutv/modules/movie/movie_detail.dart';
import 'package:kazutv/modules/roads/road_module.dart';
import 'package:kazutv/plugins/plugins.dart';

/// Route arguments for '/video/'. Entry points hand playback context over
/// through the route instead of pre-filling a shared controller, which lets
/// [VideoPageController] live and die with the route.
///
/// `bangumiItem` deliberately lives on the two anime variants rather than on
/// this base class: movie playback has no Bangumi metadata at all, and forcing
/// a fake one through the shared field would make "is this really a bangumi?"
/// unanswerable at every use site.
sealed class VideoPlaybackArgs {
  const VideoPlaybackArgs();
}

class OnlineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OnlineVideoPlaybackArgs({
    required this.bangumiItem,
    required this.plugin,
    required this.title,
    required this.src,
    required this.roads,
  });

  final BangumiItem bangumiItem;
  final Plugin plugin;
  final String title;
  final String src;
  final List<Road> roads;
}

class OfflineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OfflineVideoPlaybackArgs({
    required this.bangumiItem,
    required this.pluginName,
    required this.episodeNumber,
    required this.road,
    required this.downloadedEpisodes,
  });

  final BangumiItem bangumiItem;
  final String pluginName;
  final int episodeNumber;
  final int road;
  final List<DownloadEpisode> downloadedEpisodes;
}

/// 影视播放参数（来自苹果CMS 采集源）。
///
/// 与在线番剧的关键区别：**播放地址是现成的直链，不需要 WebView 去解析**。
/// 番剧要给插件一个网页地址、让规则把真实视频流从页面里挖出来；苹果CMS 的
/// `vod_play_url` 本身就是 m3u8/mp4 直链，拿到即可播。所以影视走一条完全独立
/// 的换集路径（`_changeMovieEpisode`），不碰 WebView。
class MovieVideoPlaybackArgs extends VideoPlaybackArgs {
  const MovieVideoPlaybackArgs({
    required this.sourceKey,
    required this.vodId,
    required this.movieName,
    required this.sourceName,
    required this.routeName,
    required this.episodes,
    required this.startIndex,
    this.coverUrl = '',
    this.year = '',
    this.startOffsetSeconds = 0,
  });

  /// 来源源 key —— 与 [vodId] 一起作为播放进度的身份
  /// （`MoviePlayProgress.keyOf`）。同一个片在不同源里各存一份进度。
  final String sourceKey;

  /// 源站内的影片 id
  final String vodId;

  /// 片名（画中画标题、播放器面板都用它）
  final String movieName;

  /// 来源源名，仅用于展示
  final String sourceName;

  /// 线路名（源站的 `vod_play_from`）
  final String routeName;

  /// 这条线路**可播**的剧集，保持源站顺序。电影通常只有一集。
  ///
  /// 调用方必须先把不可播的集滤掉（`MovieEpisode.playable`）。原因：这里会被
  /// 构造成 [Road] 交给播放页，而播放页的「自动连播」是按 Road 的长度往下走的
  /// —— 混进不可播的集（源站给的是网页中转地址），连播就会跳到一个 HTML 页面上
  /// 必然报错。展示「不可播的集」是详情页选集列表的职责，不是播放页的。
  final List<MovieEpisode> episodes;

  /// 从第几集开始播（**0 基下标**）
  final int startIndex;

  final String coverUrl;
  final String year;

  /// 从第几秒开始播（续播用）。0 表示从头开始。
  final int startOffsetSeconds;

  @override
  String toString() =>
      'MovieVideoPlaybackArgs($movieName / $routeName / ${episodes.length} 集, 起始 $startIndex)';
}
