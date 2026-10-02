import 'package:kazutv/request/apis/bangumi_api.dart';
import 'package:kazutv/services/logging/logger.dart';
import 'package:kazutv/services/network/bangumi_acceleration.dart';
import 'package:kazutv/services/storage/storage.dart';

/// 番剧加速模式的「自愈」。
///
/// ## 为什么需要它
///
/// 加速模式选错时（比如本机到 api.bgm.tv 直连不通），**所有**番剧请求都会失败：
/// 推荐空着、时间表空着、搜索说「没有找到番剧」。而用户手上没有任何线索指向
/// 「去设置里换一种加速方式」—— 现象看起来完全像「这软件坏了」或「这片子没有」。
/// 这个坑我们自己踩过一次（2026-10-02），不该让每个用户再踩一遍。
///
/// ## 探测为什么直接用真实请求
///
/// 不另发一个「探测请求」，而是拿真实调用当探测：
///   - 不用挑一个"必定存在"的 subject id（那种 id 会随内容变动而失效）
///   - 测的就是用户真正要走的那条链路
///   - 不多花流量，也不多一次往返
class BangumiAccelerationHealer {
  BangumiAccelerationHealer._();

  /// 同一时刻只允许一次自愈在跑；并发调用直接等这一份结果。
  static Future<bool>? _inflight;

  static int _lastAttemptAtMs = 0;

  /// 冷却时间。
  ///
  /// 每种模式都要等到超时才判定失败，一次自愈最坏是「候选数 × 超时」。
  /// 不加冷却的话，一次网络抖动会让每个请求都触发一轮，越试越慢。
  static const _cooldownMs = 60000;

  /// 失败后调用（可以 fire-and-forget）。
  ///
  /// 返回是否换到了可用模式 —— 拿到 true 就可以放心把刚才那次操作重试一遍。
  static Future<bool> heal() {
    // 已有一次在进行中：直接等它，别同时开两轮。
    // （这条同时解决了一个竞态：失败点触发的那次自愈与调用方紧接着请求的
    //   重试，会撞在一起 —— 后者必须搭上前者的车，而不是被冷却挡掉。）
    final inflight = _inflight;
    if (inflight != null) return inflight;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAttemptAtMs < _cooldownMs) return Future.value(false);
    _lastAttemptAtMs = now;

    final future = _attempt();
    _inflight = future;
    return future.whenComplete(() {
      _inflight = null;
    });
  }

  static Future<bool> _attempt() async {
    final current = BangumiAcceleration.current;
    for (final mode in BangumiAcceleration.candidates) {
      if (mode == current) continue;

      final ok = await BangumiAcceleration.withMode(mode, _probe);
      KazumiLogger().i(
        'Bangumi heal: ${mode.label} -> ${ok ? 'OK' : 'fail'}',
      );
      if (!ok) continue;

      // 只有确认能通的那一个才写回设置。
      await GStorage.putSetting(
        SettingsKeys.bangumiAcceleration,
        mode.name,
      );
      KazumiLogger().i('Bangumi heal: switched to ${mode.label}');
      return true;
    }
    return false;
  }

  /// 最小搜索：能拿到页就说明这条链路通。
  static Future<bool> _probe() async {
    try {
      return await BangumiApi.bangumiSearch('bgm', limit: 1) != null;
    } catch (_) {
      return false;
    }
  }
}
