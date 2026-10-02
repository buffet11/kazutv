import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazutv/bean/appbar/sys_app_bar.dart';
import 'package:kazutv/bean/card/network_img_layer.dart';
import 'package:kazutv/bean/dialog/dialog_helper.dart';
import 'package:kazutv/bean/widget/empty_state_widget.dart';
import 'package:kazutv/bean/widget/loading_indicator.dart';
import 'package:kazutv/modules/movie/movie_detail.dart';
import 'package:kazutv/modules/movie/movie_item.dart';
import 'package:kazutv/modules/movie/movie_source.dart';
import 'package:kazutv/pages/movie/movie_episode_grid.dart';
import 'package:kazutv/pages/movie/movie_route_selector.dart';
import 'package:kazutv/request/apis/apple_cms_api.dart';
import 'package:kazutv/services/movie/movie_source_manager.dart';

/// 影视详情页。
///
/// 从搜索结果进来（动画参数是 [MovieSearchItem]），自己拉详情 —— 不复用
/// 番剧的 InfoPage：那边整套都建立在 Bangumi 元数据上（评分/话数/角色/评论），
/// 影视这边一个都没有。
class MovieDetailPage extends StatefulWidget {
  const MovieDetailPage({super.key, required this.item});

  final MovieSearchItem item;

  @override
  State<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends State<MovieDetailPage> {
  MovieDetail? _detail;
  bool _loading = true;
  String? _error;

  /// 当前选中的线路（在 `playableRoutes` 里的下标）
  int _routeIndex = 0;

  MovieSource? get _source {
    for (final s in MovieSourceManager.all()) {
      if (s.key == widget.item.sourceKey) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final source = _source;
    if (source == null) {
      setState(() {
        _loading = false;
        _error = '这个源已被删除或停用，无法获取详情。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await AppleCmsApi.detail(source, widget.item.vodId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _routeIndex = 0;
        _error = detail == null ? '源站里找不到这部片（可能已下架）。' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '详情加载失败：$e';
      });
    }
  }

  List<MovieRoute> get _routes => _detail?.playableRoutes ?? const [];

  MovieRoute? get _currentRoute {
    final routes = _routes;
    if (routes.isEmpty) return null;
    return routes[_routeIndex.clamp(0, routes.length - 1)];
  }

  /// 播放。
  ///
  /// P3 只做浏览，这里先给提示；P4 会把它换成跳转到播放页
  /// （`MovieVideoPlaybackArgs` + VideoPageController 分派）。
  void _play(MovieEpisode episode) {
    KazumiDialog.showToast(
      message: '播放功能将在下一步接入：${episode.title}',
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: SysAppBar(
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: LoadingIndicator(size: 48));
    }
    if (_error != null) {
      return GeneralEmptyState(
        icon: Icons.error_outline,
        title: _error!,
        actions: [
          FilledButton.tonal(onPressed: _load, child: const Text('重试')),
        ],
      );
    }

    final detail = _detail!;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, detail),
          const SizedBox(height: 12),
          _routesSection(context, detail),
          const Divider(height: 24, indent: 16, endIndent: 16),
          _episodesSection(context),
          const SizedBox(height: 16),
          _introSection(context, detail),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- 头部

  Widget _header(BuildContext context, MovieDetail detail) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: NetworkImgLayer(
              src: detail.pic.isNotEmpty ? detail.pic : widget.item.pic,
              width: 116,
              height: 174,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (_metaLine.isNotEmpty)
                  Text(
                    _metaLine,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                if (detail.remarks.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _tag(context, detail.remarks,
                      colorScheme.secondaryContainer,
                      colorScheme.onSecondaryContainer),
                ],
                const SizedBox(height: 10),
                if (_directorLine.isNotEmpty)
                  _creditLine(context, '导演', _directorLine),
                if (_actorLine.isNotEmpty) _creditLine(context, '主演', _actorLine),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    final route = _currentRoute;
                    final episode = route?.firstPlayable;
                    if (episode == null) {
                      KazumiDialog.showToast(
                        message: '这条线路没有可播的剧集，换一条试试。',
                        context: context,
                      );
                      return;
                    }
                    _play(episode);
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放'),
                ),
                const SizedBox(height: 4),
                Text(
                  '来自 ${widget.item.sourceName}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _metaLine {
    final d = _detail!;
    final parts = <String>[];
    if (d.year.isNotEmpty) parts.add(d.year);
    if (d.area.isNotEmpty) parts.add(d.area);
    if (d.typeName.isNotEmpty) parts.add(d.typeName);
    if (d.score > 0) parts.add('${d.score} 分');
    return parts.join(' · ');
  }

  String get _directorLine => _detail!.directors.join(' / ');

  String get _actorLine {
    final actors = _detail!.actors;
    if (actors.length <= 5) return actors.join(' / ');
    return '${actors.take(5).join(' / ')} 等';
  }

  Widget _creditLine(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label：$value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _tag(
    BuildContext context,
    String text,
    Color background,
    Color foreground,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- 线路

  Widget _routesSection(BuildContext context, MovieDetail detail) {
    final theme = Theme.of(context);
    final routes = _routes;

    if (routes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '这个源给的所有线路都是网页中转地址，播放器打不开。'
            '回上一页换一个源试试。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Text(
                '线路',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                '共 ${detail.routes.length} 条，${routes.length} 条可播',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        MovieRouteSelector(
          routes: routes,
          selectedIndex: _routeIndex.clamp(0, routes.length - 1),
          onSelected: (index) => setState(() => _routeIndex = index),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- 选集

  Widget _episodesSection(BuildContext context) {
    final theme = Theme.of(context);
    final route = _currentRoute;
    if (route == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '选集（${route.episodes.length}）',
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MovieEpisodeGrid(
            // key 带上线路名：换线路时重建，避免复用上一线路的滚动/选中状态
            key: ValueKey('episodes-${route.name}'),
            episodes: route.episodes,
            onSelected: (index) => _play(route.episodes[index]),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- 简介

  Widget _introSection(BuildContext context, MovieDetail detail) {
    if (detail.content.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '简介',
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _ExpandableText(text: detail.content),
        ],
      ),
    );
  }
}

/// 简介默认只显示 3 行，点「展开」看全部。
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
        ),
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(_expanded ? '收起' : '展开'),
        ),
      ],
    );
  }
}
