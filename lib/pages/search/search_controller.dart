import 'dart:async';
import 'dart:io';

import 'package:mobx/mobx.dart';
import 'package:kazutv/modules/bangumi/bangumi_item.dart';
import 'package:kazutv/modules/collect/collect_type.dart';
import 'package:kazutv/modules/search/image_search_module.dart';
import 'package:kazutv/modules/search/search_history_module.dart';
import 'package:kazutv/repositories/collect_repository.dart';
import 'package:kazutv/repositories/search_history_repository.dart';
import 'package:kazutv/request/apis/bangumi_api.dart';
import 'package:kazutv/request/apis/trace_api.dart';
import 'package:kazutv/services/network/bangumi_acceleration_healer.dart';
import 'package:kazutv/utils/search_parser.dart';

part 'search_controller.g.dart';

class SearchPageController = _SearchPageController with _$SearchPageController;

abstract class _SearchPageController with Store {
  static const int _searchPageSize = 20;
  static const int _maxPagesPerSearch = 3;

  _SearchPageController(
    this._collectRepository,
    this._searchHistoryRepository,
  );

  final ICollectRepository _collectRepository;
  final ISearchHistoryRepository _searchHistoryRepository;

  int _searchOffset = 0;
  int _searchGeneration = 0;

  bool hasMoreSearchResults = true;

  @observable
  bool isLoading = false;

  @observable
  bool isTimeOut = false;

  @observable
  bool notShowWatchedBangumis = false;

  @observable
  bool notShowAbandonedBangumis = false;

  @observable
  ObservableList<BangumiItem> bangumiList = ObservableList.of([]);

  @observable
  ObservableList<SearchHistory> searchHistories = ObservableList.of([]);

  @observable
  bool isImageSearching = false;

  @observable
  String imageSearchError = '';

  @observable
  ObservableList<ResultItem> imageSearchResults = ObservableList.of([]);

  @action
  void loadSearchHistories() {
    final histories = _searchHistoryRepository.getAllHistories();
    searchHistories.clear();
    searchHistories.addAll(histories);
  }

  @action
  Future<void> searchBangumi(String input, {String type = 'add'}) async {
    if (type == 'add' && (isLoading || !hasMoreSearchResults)) return;
    final generation = type == 'add' ? _searchGeneration : ++_searchGeneration;
    isLoading = true;
    isTimeOut = false;
    if (type != 'add') {
      bangumiList.clear();
      _searchOffset = 0;
      hasMoreSearchResults = true;
      if (!_collectRepository.getPrivateMode() && input.trim().isNotEmpty) {
        await _searchHistoryRepository.deleteDuplicates(input);
        if (_searchHistoryRepository.isHistoryFull(10)) {
          await _searchHistoryRepository.deleteOldest();
        }
        await _searchHistoryRepository.saveHistory(input);
        loadSearchHistories();
      }
    }
    if (generation != _searchGeneration) return;
    final filterState = SearchParser(input).toFilterState();
    final id = int.tryParse(filterState.id);
    if (id != null) {
      final item = await BangumiApi.getBangumiInfoByID(id);
      if (generation != _searchGeneration) return;
      if (item != null) {
        bangumiList.add(item);
      }
      hasMoreSearchResults = false;
      isLoading = false;
      isTimeOut = bangumiList.isEmpty;
      return;
    }
    var pagesFetched = 0;
    do {
      final page = await BangumiApi.bangumiSearch(filterState.keyword,
          tags: filterState.tags,
          limit: _searchPageSize,
          offset: _searchOffset,
          sort: filterState.sort,
          dateRange: filterState.effectiveDateRange,
          rankRange: filterState.rankRange,
          scoreRange: filterState.scoreRange,
          weekdays: filterState.weekdays);
      // Discard stale responses before mutating the current search.
      if (generation != _searchGeneration) return;
      if (page == null) {
        break;
      }
      pagesFetched++;
      _searchOffset += page.rawCount;
      hasMoreSearchResults = page.rawCount == _searchPageSize;
      final existingIds = bangumiList.map((item) => item.id).toSet();
      final newItems =
          page.items.where((item) => existingIds.add(item.id)).toList();
      if (newItems.isNotEmpty) {
        bangumiList.addAll(newItems);
        break;
      }
    } while (hasMoreSearchResults && pagesFetched < _maxPagesPerSearch);
    isLoading = false;
    // 「请求失败」与「确实没有这部番」必须分开 —— 两者给用户的信息是相反的。
    //
    //   - 第一页就拿到 null（`BangumiApi.bangumiSearch` 出错时返回 null）-> 失败
    //   - 拿到了页、只是内容为空 -> 真的没有
    //
    // 原来写的是 `bangumiList.isEmpty && (pagesFetched == 0 || !hasMoreSearchResults)`，
    // 把两种情况都置成了 true，于是「搜索失败」在界面上被呈现成「没有找到番剧」，
    // 用户会以为这部片子不存在，而其实只是请求被拒了。
    // 2026-10-02 的番剧搜索回归（镜像签名缺凭据 -> 401）就是被这个掩盖掉的。
    isTimeOut = pagesFetched == 0;
    // 失败了不一定真是"没有这片"，也可能是加速模式在本机不通。
    // 让自愈在后台换模式试一遍，成功的话设置会被改好，重试即可。
    if (isTimeOut) {
      unawaited(BangumiAccelerationHealer.heal());
    }
  }

  /// 搜索 + 失败自愈。
  ///
  /// 单独包一层而不是改 `searchBangumi`：后者是 `@action`，签名一动
  /// `search_controller.g.dart` 里生成的 override 就对不上了，而本机跑不了
  /// build_runner（见 git 历史的 tools 那条）。
  Future<void> searchWithRecovery(String input, {String type = 'init'}) async {
    await searchBangumi(input, type: type);
    if (!isTimeOut) return;
    // 自愈成功就直接替用户重试一次 —— 用户不需要知道刚才换过模式。
    if (await BangumiAccelerationHealer.heal()) {
      await searchBangumi(input, type: type);
    }
  }

  @action
  Future<void> deleteSearchHistory(SearchHistory history) async {
    await _searchHistoryRepository.deleteHistory(history);
    loadSearchHistories();
  }

  @action
  Future<void> clearSearchHistory() async {
    await _searchHistoryRepository.clearAllHistories();
    loadSearchHistories();
  }

  @action
  void clearImageSearchState() {
    isImageSearching = false;
    imageSearchError = '';
    imageSearchResults.clear();
  }

  @action
  Future<void> searchImageByFile(File imageFile) async {
    isImageSearching = true;
    imageSearchError = '';
    imageSearchResults.clear();
    try {
      final result = await TraceApi.searchAnimeByImageFile(imageFile);
      imageSearchResults.addAll(result.result ?? []);
      if (result.error != null && result.error!.isNotEmpty) {
        imageSearchError = result.error!;
      } else if (imageSearchResults.isEmpty) {
        imageSearchError = '未找到匹配结果';
      }
    } catch (e) {
      imageSearchError = '图片搜索失败，请稍后重试';
    } finally {
      isImageSearching = false;
    }
  }

  @action
  Future<void> searchImageByUrl(String imageUrl) async {
    isImageSearching = true;
    imageSearchError = '';
    imageSearchResults.clear();
    try {
      final result = await TraceApi.searchAnimeByImageUrl(imageUrl);
      imageSearchResults.addAll(result.result ?? []);
      if (result.error != null && result.error!.isNotEmpty) {
        imageSearchError = result.error!;
      } else if (imageSearchResults.isEmpty) {
        imageSearchError = '未找到匹配结果';
      }
    } catch (e) {
      imageSearchError = '图片搜索失败，请检查图片地址或稍后重试';
    } finally {
      isImageSearching = false;
    }
  }

  @action
  Future<void> setNotShowWatchedBangumis(bool value) async {
    notShowWatchedBangumis = value;
  }

  @action
  Future<void> setNotShowAbandonedBangumis(bool value) async {
    notShowAbandonedBangumis = value;
  }

  Set<int> loadWatchedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.watched);
  }

  Set<int> loadAbandonedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.abandoned);
  }
}
