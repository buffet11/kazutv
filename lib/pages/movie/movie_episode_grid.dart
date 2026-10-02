import 'package:flutter/material.dart';
import 'package:kazutv/modules/movie/movie_detail.dart';

/// 剧集网格。
///
/// 电影通常只有一集（标题类似「HD国语」），剧集/综艺会有几十集。
/// 不可播的集（源站给的是网页地址）保留展示但禁用 —— 直接藏起来会让用户以为
/// 「这部剧只有 5 集」，而实际上后面 20 集只是这个源没有直链，换个源就有。
class MovieEpisodeGrid extends StatelessWidget {
  const MovieEpisodeGrid({
    super.key,
    required this.episodes,
    this.currentIndex,
    required this.onSelected,
    this.playableOnly = false,
  });

  final List<MovieEpisode> episodes;
  final int? currentIndex;
  final ValueChanged<int> onSelected;

  /// 只看可播的（线路整体不可播时用不上，但筛选时有用）
  final bool playableOnly;

  @override
  Widget build(BuildContext context) {
    final visible = playableOnly
        ? [
            for (var i = 0; i < episodes.length; i++)
              if (episodes[i].playable) i,
          ]
        : [for (var i = 0; i < episodes.length; i++) i];

    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          '这条线路没有可直接播放的剧集，换一条线路试试。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final i in visible)
          _episodeChip(context, i, episodes[i], i == currentIndex),
      ],
    );
  }

  Widget _episodeChip(
    BuildContext context,
    int index,
    MovieEpisode episode,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 96,
      child: OutlinedButton(
        onPressed: episode.playable ? () => onSelected(index) : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          backgroundColor: selected ? colorScheme.primaryContainer : null,
          side: selected
              ? BorderSide(color: colorScheme.primary, width: 1.5)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          episode.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colorScheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }
}
