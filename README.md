# Kazutv

> 一个把「看番」和「看电影」合在一起的跨平台视频播放器

Kazutv 是开源项目 [**Kazumi**](https://github.com/Predidit/Kazumi) 的**二次开发分支**。
它保留上游的番剧采集、播放与弹幕能力，在其之上新增影视内容（电影 / 剧集 / 综艺）聚合播放，
并对弹幕的自动匹配能力做了增强。

> ### 关于本仓库的性质（重要）
>
> 本仓库是 Kazumi 的**修改版本**，并非官方版本，与上游作者无隶属关系。
> 修改起始日期：**2026-10-01**。
> 依据 GNU GPL-3.0 第 5(a) 条，在此声明本作品已被修改。
> 上游项目：<https://github.com/Predidit/Kazumi>
>
> 许可证、致谢与第三方说明见 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md)。

---

## 当前状态

**早期开发中。** 本仓库目前处于「二开起点」阶段——以上游 Kazumi 源码为基础，
二开功能正在实现中。下方功能表中未勾选的即为尚未实现的部分。

## 功能

### 继承自上游 Kazumi

- 基于自定义 XPath 规则的番剧采集与在线播放
- 弹幕（基于 [弹弹play 开放弹幕网络](https://doc.dandanplay.net/open/)）
- 规则编辑器、规则导入导出与规则商店
- 离线下载、观看历史、追番收藏
- WebDAV 数据同步、DLNA 投屏、一起看（SyncPlay）
- 基于 Anime4K 的实时超分辨率

### 二开新增（规划中）

- [ ] 影视模块：电影 / 剧集 / 综艺聚合搜索与播放（苹果CMS 协议）
- [ ] 自定义影视源管理：增删改、启用停用、探活测速
- [ ] 影视源订阅导入导出（兼容 LibreTV-SourceList 与 TVBOX 配置格式）
- [ ] 影视弹幕**自动检索 + 自动加载**（带独立开关，默认关闭）
- [ ] 弹幕匹配纠错：手动指定后记住选择，下次直接命中
- [ ] 影视收藏与观看历史续播

详细的架构设计见 [`docs/Kazutv-融合设计方案.md`](docs/Kazutv-融合设计方案.md)。

## 支持平台

- Android 10 及以上
- Windows 10 及以上
- macOS 10.15 及以上
- Linux（实验性）
- iOS 13 及以上（需[侧载](https://kazumi.app/docs/misc/how-to-install-in-ios)）

> HarmonyOS 5.0+ 的支持位于上游的[分支仓库](https://github.com/ErBWs/Kazumi)，
> 本分支暂未覆盖。

## 构建

需要 Flutter SDK **3.47.5** 或更高版本。

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 MobX / Hive 代码

flutter build windows        # Windows 桌面
flutter build apk            # Android（可加 --split-per-abi）
```

国内网络建议先配置镜像，可显著加快依赖拉取：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

### 弹幕服务凭据

本项目使用弹弹play 开放弹幕网络。**该服务需要 AppId / AppSecret 签名，未配置时弹幕将不可用。**

请前往[弹弹play 开放弹幕网络开发者中心](https://dev.dandanplay.com)申请自己的凭据（免费，需审核），
然后在构建时注入：

```bash
flutter build windows \
  --dart-define=DANDANAPI_APPID=<你的 AppId> \
  --dart-define=DANDANAPI_KEY=<你的 AppSecret>
```

> 凭据会被编译进客户端二进制，请勿将其提交到公开仓库。

## 免责声明

本项目仅供学习与技术研究使用。所有视频内容均来自第三方采集接口，本项目不存储、
不制作、不托管任何视频内容，也不对第三方内容的合法性负责。

使用本项目需遵守所在地法律法规，不得进行任何侵犯第三方知识产权的行为。
因使用本项目而产生的数据和缓存应在 24 小时内清除，超出 24 小时的使用需获得相关权利人的授权。

## 隐私

不收集任何用户数据，不使用任何遥测组件。

## 致谢

上游 Kazumi 及其全部依赖的致谢名单见 [NOTICE.md](NOTICE.md)。

## 许可证

[GNU General Public License v3.0](LICENSE)

本作品包含基于 [LibreTV](https://github.com/LibreSpark/LibreTV)（AGPL-3.0）协议实现重写的代码，
组合作品整体按 AGPL-3.0 发布。
