"""为带 native assets 构建钩子的依赖预置「预编译包」，绕过 GitHub 下载。

背景
----
项目里有三个包带 native assets 钩子（`hook/build.dart`）：

| 包 | 钩子要下载什么 | 来源 |
|---|---|---|
| `ech_http` | curl + BoringSSL + zlib 的预编译 SDK（4.8 MB zip） | GitHub Releases |
| `media_kit` | mpv 的 dev 包（10.5 MB 7z） | GitHub Releases |
| `objective_c` | 无（纯编译，不下载） | — |

国内从 GitHub Releases 拉这些包会超时或龟速（实测 media_kit 那个只有 **6.5 KB/s**，
10.5 MB 要下好几天），而**这是 Dart 的 `HttpClient` 下载，不是 git** ——
`git config url.*.insteadOf` 那套代理规则对它完全无效。

解法
----
两个钩子的缓存逻辑是一样的（都是内容寻址 + SHA256 校验）：

    final archive = File(p.join(cache, '<key>.<format>'));
    if (!await archive.exists() || await digest(archive) != expected) {
        ... 才去下载 ...
    }

所以只要把包按期望的文件名放进缓存目录、哈希对得上，就会**完全跳过下载**。

⚠️ 缓存位于 `<项目>/.dart_tool/hooks_runner/shared/` 下，**会被 `flutter clean` 清掉**，
所以 build_windows.py 每次构建前都会调用本模块兜底。

命令行用法：
    python tools\\hooks_prebuilt.py                    # 补全部（按当前平台）
    python tools\\hooks_prebuilt.py windows-x64        # 只补指定目标
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------- 路径常量

HOME = Path.home()
PUB_CACHE_HOSTED = HOME / "AppData/Local/Pub/Cache/hosted"
PUB_GIT = HOME / "AppData/Local/Pub/Cache/git"


def _resolve_hosted_root() -> Path:
    """pub 缓存里的宿主目录名随镜像而变（pub.dev / pub.flutter-io.cn ...）。

    不写死：谁在就用谁，都没有就按官方源返回。
    """
    if PUB_CACHE_HOSTED.is_dir():
        for p in sorted(PUB_CACHE_HOSTED.iterdir()):
            if p.is_dir():
                return p
    return PUB_CACHE_HOSTED / "pub.dev"


def _resolve_package_dir(name: str, fallback: str) -> Path:
    """找包目录。优先精确匹配，找不到就按前缀取第一个（容忍版本号变化）。"""
    exact = PUB_HOSTED / fallback
    if exact.is_dir():
        return exact
    if PUB_HOSTED.is_dir():
        for p in sorted(PUB_HOSTED.glob(f"{name}-*")):
            if p.is_dir():
                return p
    return exact


TOOLS_DIR = Path(__file__).resolve().parent   # <app>/tools
APP_DIR = TOOLS_DIR.parent                    # <app>
SHARED = APP_DIR / ".dart_tool/hooks_runner/shared"

PUB_HOSTED = _resolve_hosted_root()

# ech_http
ECH_PKG = _resolve_package_dir("ech_http", "ech_http-0.2.1")
ECH_MANIFEST = ECH_PKG / "lib/src/build_support/dependencies.json"
ECH_CACHE = SHARED / "ech_http/build/prebuilt"

# media_kit（路径带 commit hash，需要动态找）
MEDIA_MANIFEST_REL = "media_kit/hook/native_bundles.json"
MEDIA_CACHE = SHARED / "media_kit/build/prebuilt"

# 走这个通道下载 GitHub Releases（实测 2.8~4.7 MB/s）
PROXY_PREFIX = "https://gh-proxy.com/"

# 走代理时的下载超时；直连只给短超时（太慢，不值得等）
DOWNLOAD_TIMEOUT = 900
DIRECT_TIMEOUT = 120


# ---------------------------------------------------------------- 通用工具


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _proxied(url: str) -> str:
    return PROXY_PREFIX + url if url.startswith("https://github.com/") else url


def _download(url: str, dest: Path, log, timeout: int = DOWNLOAD_TIMEOUT) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    log(f"       下载 {url}")
    t0 = time.time()
    r = subprocess.run(
        ["curl", "-L", "--fail", "--max-time", str(timeout),
         "-o", str(dest), url],
        capture_output=True,
    )
    dt = max(time.time() - t0, 0.1)
    if r.returncode != 0:
        log(f"       失败 rc={r.returncode} "
            f"{r.stderr.decode('utf-8', 'replace')[:120]}")
        return False
    size = dest.stat().st_size
    log(f"       完成 {size / 1048576:.1f} MB / {dt:.1f}s "
        f"({size / 1048576 / dt:.1f} MB/s)")
    return True


def _fetch_verified(url: str, digest: str, dest: Path, log) -> bool:
    """下载并校验 SHA256。

    **优先走 gh-proxy.com**：本机直连 GitHub 大文件实测只有 6.5 KB/s
    （media_kit 那个 10.5 MB 的包要下 27 分钟），代理则有 2.8~4.7 MB/s。
    代理失败再退回直连（给较短超时，免得又卡住）。
    """
    attempts: list[tuple[str, str]] = []
    if url.startswith("https://github.com/"):
        attempts.append(("gh-proxy.com", _proxied(url)))
    attempts.append(("直连", url))

    for label, target_url in attempts:
        if dest.exists():
            dest.unlink()
        log(f"       尝试 {label}")
        timeout = DOWNLOAD_TIMEOUT if label != "直连" else DIRECT_TIMEOUT
        if _download(target_url, dest, log, timeout) and sha256_of(dest) == digest:
            return True
        if dest.exists():
            dest.unlink()
        log(f"       {label} 不可用")

    log("       [X] 所有通道都失败")
    return False


# ---------------------------------------------------------------- ech_http


def ensure_ech_http(target: str, log=print) -> bool:
    if not ECH_MANIFEST.is_file():
        log(f"  [!] 找不到 ech_http 清单（可能还没跑 pub get）：{ECH_MANIFEST}")
        return False
    try:
        entry = json.loads(ECH_MANIFEST.read_text(encoding="utf-8"))["targets"][target]
    except (KeyError, json.JSONDecodeError):
        log(f"  [!] ech_http 清单里没有目标 {target}")
        return False

    digest = entry["sha256"]
    dest = ECH_CACHE / f"{target}-{digest}.zip"
    if dest.is_file() and sha256_of(dest) == digest:
        return True

    log(f"  → ech_http 预编译依赖 [{target}]")
    if not _fetch_verified(entry["url"], digest, dest, log):
        return False
    log(f"  ✓ ech_http [{target}] 就绪（{dest.stat().st_size / 1048576:.1f} MB）")
    return True


# ---------------------------------------------------------------- media_kit


def _find_media_manifest() -> Path | None:
    if not PUB_GIT.is_dir():
        return None
    for d in sorted(PUB_GIT.iterdir()):
        if d.is_dir() and d.name.startswith("media-kit-"):
            m = d / MEDIA_MANIFEST_REL
            if m.is_file():
                return m
    return None


def ensure_media_kit(target: str, log=print) -> bool:
    """target 形如 windows_x64（注意是下划线，与 native_bundles.json 的键一致）。"""
    manifest = _find_media_manifest()
    if manifest is None:
        log("  [!] 找不到 media_kit 的 native_bundles.json（可能还没跑 pub get）")
        return False

    try:
        bundle = json.loads(manifest.read_text(encoding="utf-8"))["bundles"][target]
    except (KeyError, json.JSONDecodeError):
        log(f"  [!] media_kit 清单里没有目标 {target}")
        return False

    digest = bundle["sha256"]
    fmt = bundle["format"]
    dest = MEDIA_CACHE / digest / f"archive.{fmt}"
    if dest.is_file() and sha256_of(dest) == digest:
        return True

    log(f"  → media_kit 原生包 [{target}]  ({bundle.get('library', '')})")
    if not _fetch_verified(bundle["url"], digest, dest, log):
        return False
    log(f"  ✓ media_kit [{target}] 就绪（{dest.stat().st_size / 1048576:.1f} MB）")
    return True


# ---------------------------------------------------------------- 对外接口

# 平台 → 两个包各自的 target 命名对照
TARGETS = {
    "windows": {"ech": "windows-x64", "media": "windows_x64"},
    "windows-arm64": {"ech": "windows-arm64", "media": "windows_arm64"},
    "android": {"ech": "android-arm64", "media": "android_arm64"},
    "linux": {"ech": "linux-x64", "media": "linux_x64"},
}


def ensure_all(platform: str = "windows", log=print) -> bool:
    spec = TARGETS.get(platform)
    if spec is None:
        log(f"  [!] 未知平台 {platform}，可选：{', '.join(TARGETS)}")
        return False
    ok = ensure_ech_http(spec["ech"], log)
    ok = ensure_media_kit(spec["media"], log) and ok
    return ok


def main() -> int:
    args = sys.argv[1:]
    platform = "windows"
    if args:
        # 支持直接传 ech/media 的目标名
        if args[0] in TARGETS:
            platform = args[0]
        else:
            print(f"未知参数 {args[0]}")
            return 2

    print("=" * 70)
    print(f" 预置 native assets 依赖（平台：{platform}）")
    print("=" * 70)
    print(f" 缓存根目录: {SHARED}")
    print()
    ok = ensure_all(platform)
    print()
    print("=" * 70)
    print(" 就绪（无需下载）" if ok else " 有项目未就绪")
    print("=" * 70)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
