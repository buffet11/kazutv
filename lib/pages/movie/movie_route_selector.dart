import 'package:flutter/material.dart';
import 'package:kazutv/modules/movie/movie_detail.dart';

/// 线路选择器。
///
/// 传入的 [routes] 应当已经按可播性排序（`MovieDetail.playableRoutes`），
/// 所以第一个就是默认该选的那条。顺序不能按源站给的来 —— 实测电影天堂的
/// 「流浪地球2」第一条线路是网页分享页，交给播放器只会黑屏。
class MovieRouteSelector extends StatelessWidget {
  const MovieRouteSelector({
    super.key,
    required this.routes,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<MovieRoute> routes;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: routes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _routeChip(context, index),
      ),
    );
  }

  Widget _routeChip(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final route = routes[index];
    final selected = index == selectedIndex;

    // 不可播的线路仍然展示（用户可能想看它有哪些集），但要一眼看出区别
    final foreground = route.playable
        ? (selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant)
        : colorScheme.outline;

    return Center(
      child: InkWell(
        onTap: () => onSelected(index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: route.playable
                ? null
                : Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: route.playable
                      ? (selected ? colorScheme.onPrimary : null)
                      : colorScheme.outline,
                  decoration:
                      route.playable ? null : TextDecoration.lineThrough,
                ),
              ),
              Text(
                route.playable
                    ? '${route.episodes.length} 集'
                    : '来源页 · 不可播',
                style: theme.textTheme.labelSmall?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
