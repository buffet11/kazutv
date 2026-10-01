import 'package:kazutv/modules/movie/movie_source.dart';

/// 内置影视源。
///
/// 全部为**实测可用**（2026-10-01 探测，搜索「流浪地球」均返回结果），
/// 按延迟排序。源站存活会变，所以：
///   - 每个源都能在设置里单独停用；
///   - 探活失败只影响该源，不会拖垮整体搜索（见 MovieSearchService）；
///   - 用户可自行增删，内置源只是「保证开箱可用」的兜底，不是硬编码依赖。
///
/// 实测备注：
///   - 电影天堂有 `dytt`（网页分享页，**播不了**）和 `dyttm3u8`（直链）两条线路，
///     这正是 MovieDetail.playableRoutes 要按可播性排序的原因；
///   - 其余源基本都有 `xxxm3u8` 形态的直链线路。
const List<({String key, String name, String api})> _builtin = [
  (key: 'builtin_dytt', name: '电影天堂', api: 'http://caiji.dyttzyapi.com'),
  (key: 'builtin_360', name: '360资源', api: 'https://360zy.com'),
  (key: 'builtin_jinying', name: '金鹰资源', api: 'https://jyzyapi.com'),
  (key: 'builtin_lzi', name: '量子资源', api: 'https://cj.lziapi.com'),
  (key: 'builtin_huya', name: '虎牙资源', api: 'https://www.huyaapi.com'),
];

/// 构造内置源列表（每次返回新实例，便于调用方直接改 enabled / order）。
List<MovieSource> builtinMovieSources() {
  return [
    for (var i = 0; i < _builtin.length; i++)
      MovieSource(
        key: _builtin[i].key,
        name: _builtin[i].name,
        api: _builtin[i].api,
        order: i,
      ),
  ];
}

/// 内置源的 key 集合，用于判断某个源是不是内置的（影响能否删除）。
const Set<String> builtinMovieSourceKeys = {
  'builtin_dytt',
  'builtin_360',
  'builtin_jinying',
  'builtin_lzi',
  'builtin_huya',
};
