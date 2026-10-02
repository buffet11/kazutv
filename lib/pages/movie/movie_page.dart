import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazutv/bean/appbar/sys_app_bar.dart';
import 'package:kazutv/bean/widget/empty_state_widget.dart';
import 'package:kazutv/bean/widget/loading_indicator.dart';
import 'package:kazutv/modules/movie/movie_item.dart';
import 'package:kazutv/pages/movie/movie_controller.dart';
import 'package:kazutv/pages/movie/movie_result_grid.dart';
import 'package:kazutv/pages/movie/movie_source_chips.dart';

/// 影视 Tab：搜索框 + 搜索历史 + 结果网格。
///
/// 与番剧走的是两条完全不同的链路（苹果CMS JSON API vs Bangumi 元数据），
/// 所以做成独立 Tab 而不是并进番剧搜索 —— 并进去两套数据会互相污染排序与筛选。
class MoviePage extends StatefulWidget {
  const MoviePage({super.key, required this.controller});

  final MovieController controller;

  @override
  State<MoviePage> createState() => _MoviePageState();
}

class _MoviePageState extends State<MoviePage> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  MovieController get _controller => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit([String? value]) async {
    final kw = (value ?? _input.text).trim();
    if (kw.isEmpty) {
      _focus.requestFocus();
      return;
    }
    if (_input.text != kw) {
      _input.value = TextEditingValue(
        text: kw,
        selection: TextSelection.collapsed(offset: kw.length),
      );
    }
    _focus.unfocus();
    await _controller.search(kw);
  }

  void _openDetail(MovieSearchItem item) {
    context.pushNamed('/movie-detail/', arguments: item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 72,
        title: Text(
          '影视',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '管理影视源',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => context.pushNamed('/settings/movie-source'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
            children: [
              _searchField(context),
              if (_controller.hasSearched) _filterRow(context),
              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 搜索框

  Widget _searchField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        controller: _input,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        decoration: InputDecoration(
          hintText: '搜索电影、剧集、综艺',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _input.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _input.clear();
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  // ------------------------------------------------------- 筛选条 / 失败提示

  Widget _filterRow(BuildContext context) {
    final sources = _controller.searchedSources;
    if (sources.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        MovieSourceChips(
          sources: sources,
          counts: _controller.countBySource,
          failedKeys: _controller.failures.map((e) => e.sourceKey).toSet(),
          selectedKey: _controller.sourceFilter,
          totalCount: _controller.outcome?.items.length ?? 0,
          onSelected: _controller.setSourceFilter,
        ),
        if (_controller.failures.isNotEmpty) _failuresBar(context),
      ],
    );
  }

  /// 失败的源必须显示出来。
  ///
  /// 否则用户看到「没有结果」会以为这部片不存在，实际可能只是某个源超时了。
  Widget _failuresBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final failures = _controller.failures;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_off_rounded,
              size: 18, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${failures.length} 个源未响应：'
              '${failures.map((f) => f.sourceName).join('、')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- 主体

  Widget _body(BuildContext context) {
    if (_controller.searching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoadingIndicator(size: 44),
            const SizedBox(height: 16),
            Text(
              '正在搜索 ${_controller.sources.length} 个源…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_controller.errorMessage != null) {
      return GeneralEmptyState(
        icon: Icons.error_outline,
        title: '搜索失败\n${_controller.errorMessage}',
        actions: [
          FilledButton.tonal(
            onPressed: () => _submit(_controller.keyword),
            child: const Text('重试'),
          ),
        ],
      );
    }

    if (_controller.noSourceEnabled) {
      return const GeneralEmptyState(
        icon: Icons.dns_outlined,
        title: '没有启用的影视源\n请先到「管理影视源」里启用至少一个。',
      );
    }

    if (!_controller.hasSearched) return _initialState(context);

    final items = _controller.items;
    if (items.isEmpty) {
      return GeneralEmptyState(
        icon: Icons.search_off,
        title: _controller.allFailed
            ? '所有源都没有响应\n可能是网络问题，稍后再试。'
            : '没找到「${_controller.keyword}」\n换个关键词，或到「管理影视源」多启用几个源。',
        actions: [
          FilledButton.tonal(
            onPressed: () => _submit(_controller.keyword),
            child: const Text('重试'),
          ),
        ],
      );
    }

    return MovieResultGrid(items: items, onTap: _openDetail);
  }

  /// 还没搜过：给搜索历史（比一片空白有用得多）
  Widget _initialState(BuildContext context) {
    final theme = Theme.of(context);
    final history = _controller.history;
    if (history.isEmpty) {
      return const GeneralEmptyState(
        icon: Icons.movie_outlined,
        title: '搜一部电影试试\n聚合了多个影视源，同一个片子可以换源播放。',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '搜索历史',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: _controller.clearHistory,
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kw in history)
                ActionChip(
                  label: Text(kw),
                  onPressed: () {
                    _input.text = kw;
                    _submit(kw);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
