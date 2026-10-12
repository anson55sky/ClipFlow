#!/usr/bin/env bash
# rebrand.sh — ClipFlow 全量重品牌补丁
# 用法: ./rebrand.sh <app内容目录>   （即包含 web/ server/ bin/ 的目录，如 ClipFlow.app/Contents/Resources/app）
# 作用: 将内置 web 编辑器（MIT 许可的 @ffclip-com/videocut）的 ffclip/VideoCut 品牌文案
#       全量替换为 ClipFlow 品牌，并替换"关于"弹窗二维码为 GitHub 指向。
# 机制字符串（npm 包名 @ffclip-com/videocut、更新目录 .ffclip-update-）受保护，不会被误改。
set -euo pipefail
trap 'echo "[rebrand] 失败于第 $LINENO 行: $BASH_COMMAND" >&2' ERR

TARGET_DIR="${1:?用法: ./rebrand.sh <包含 web/server/bin 的目录>}"
BRAND="ClipFlow"
REPO_URL="https://github.com/anson55sky/ClipFlow"
PROFILE_URL="https://github.com/anson55sky"
PYTHON="${PYTHON:-/Users/sky/.workbuddy/binaries/python/envs/default/bin/python}"

TARGET_DIR="$TARGET_DIR" BRAND="$BRAND" REPO_URL="$REPO_URL" PROFILE_URL="$PROFILE_URL" \
"$PYTHON" <<'PYEOF'
import os, glob, io, sys

target = os.environ["TARGET_DIR"]; BRAND = os.environ["BRAND"]
REPO_URL = os.environ["REPO_URL"]; PROFILE_URL = os.environ["PROFILE_URL"]

# ---- 受保护的机制字符串（先占位，最后还原）----
PROTECT = ["@ffclip-com/videocut", ".ffclip-update-"]

def protect(s):
    for i, p in enumerate(PROTECT):
        s = s.replace(p, f"\x00P{i}\x00")
    return s

def restore(s):
    for i, p in enumerate(PROTECT):
        s = s.replace(f"\x00P{i}\x00", p)
    return s

# ---- 替换规则：web 前端 bundle（含 i18n 字典与"关于"弹窗）----
WEB_REPL = [
    # ⚠️ 字典键修复：这三个键在压缩产物里是不带引号的属性名，
    #    替换值含空格会破坏语法（黑屏根因），必须连引号一起替换。
    ('微信好友:"', f'"GitHub 仓库":"'),
    ('新身数字人微信公众号二维码:"', f'"作者 GitHub 主页二维码":"'),
    ('新身数字人:"', f'"作者 GitHub":"'),
    # 关于弹窗 标题
    ("关于 ffclip", f"关于 {BRAND}"), ("About ffclip", f"About {BRAND}"),
    # 官网链接 → 仓库
    ("ffclip 官网（在新标签页打开）", f"{BRAND} 仓库（在新标签页打开）"),
    ("https://ffclip.com", REPO_URL),
    ('"ffclip.com"', '"github.com/anson55sky/ClipFlow"'),
    ("ffclip 官网", f"{BRAND} 仓库"),
    # B 站链接 → GitHub 主页
    ("https://space.bilibili.com/98643795", PROFILE_URL),
    ('"bilibili · 98643795"', f'"GitHub · anson55sky"'),
    ("B 站主页（在新标签页打开）", "作者主页（在新标签页打开）"),
    ("B 站主页", "作者主页"),
    ("Bilibili profile (opens in a new tab)", "GitHub profile (opens in a new tab)"),
    ("Bilibili", "GitHub"),
    # 二维码区块一（原微信好友 → GitHub 仓库）
    ("微信好友二维码，扫码添加作者", f"{BRAND} 仓库二维码，扫码访问"),
    ("查看微信好友二维码原图", "查看仓库二维码原图"),
    ("扫一扫，加我微信", "扫码访问开源仓库"),
    ("微信好友", "GitHub 仓库"),
    ("WeChat QR code. Scan to add the creator.", "GitHub repo QR code. Scan to open."),
    ("Connect on WeChat", "Scan to open the repo"),
    ("View full-size WeChat contact QR code", "View repo QR code"),
    ('"WeChat"', '"GitHub"'),
    # 二维码区块二（原公众号 → 作者 GitHub）
    ("新身数字人微信公众号二维码", "作者 GitHub 主页二维码"),
    ("新身数字人", "作者 GitHub"),
    ("微信扫码，关注公众号", "扫码访问作者 GitHub"),
    ("查看微信公众号二维码原图", "查看作者主页二维码原图"),
    ("Xinshen Digital Human WeChat account QR code", "Author's GitHub profile QR code"),
    ("Xinshen Digital Human", "Author's GitHub"),
    ("Follow on WeChat", "Scan to visit author's GitHub"),
    ("View full-size WeChat account QR code", "View profile QR code"),
    # 版权与窗口标题
    ("FFClip", BRAND), ("VideoCut", BRAND),
    # 演示项目名口号
    ("让灵感成为作品", "演示项目"),
    # 顶栏 logo 静态文案与更新提示里的显示名
    ('"ffclip"', f'"{BRAND}"'),
    ("ffclip 服务", f"{BRAND} 服务"),
    ("本机 ffclip 更新", f"本机 {BRAND} 更新"),
]

# ---- 替换规则：server / bin（源码里为 \xXX / \uXXXX 转义，按字面替换）----
ESC_DEMO_NAME = "\\u8BA9\\u7075\\u611F\\u6210\\u4E3A\\u4F5C\\u54C1"   # 让灵感成为作品
ESC_DEMO_NEW  = "\\u6F14\\u793A\\u9879\\u76EE"                        # 演示项目
SERVER_REPL = [
    ("ffclip \\xB7", f"{BRAND} \\xB7"),
    (ESC_DEMO_NAME, ESC_DEMO_NEW),
    ("Ideas into stories", "Demo project"),
    (',"ffclip",64,48', f',"{BRAND}",64,48'),
    ("VideoCut", BRAND),
]

def apply(path, repls, final_sweep=True):
    s = io.open(path, encoding="utf-8").read()
    orig = s
    s = protect(s)
    hits = []
    for old, new in repls:
        n = s.count(old)
        if n:
            s = s.replace(old, new)
            hits.append((old[:40], n))
    if final_sweep:  # 兜底：残余的 ffclip/FFclip 一律换掉（受保护串已占位）
        for k in ("ffclip", "FFclip"):
            n = s.count(k)
            if n:
                s = s.replace(k, BRAND); hits.append((f"<兜底>{k}", n))
    s = restore(s)
    if s != orig:
        io.open(path, "w", encoding="utf-8", newline="").write(s)
    return hits

report = []
def g(*parts):
    """同时匹配 <target>/ 与 <target>/dist/ 两种布局，去重"""
    out = []
    for base in (target, os.path.join(target, "dist")):
        out.extend(sorted(glob.glob(os.path.join(base, *parts))))
    return list(dict.fromkeys(out))

# 1) web 前端 bundle
for f in g("web", "assets", "*.js"):
    h = apply(f, WEB_REPL)
    if h: report.append((f, h))
# 2) index.html 标题
for f in g("web", "index.html"):
    h = apply(f, [("<title>VideoCut</title>", f"<title>{BRAND}</title>")])
    if h: report.append((f, h))
# 3) starter 页 + 演示字幕里的品牌名
for f in g("web", "starter", "*.html"):
    h = apply(f, [])
    if h: report.append((f, h))
for f in g("web", "starter", "captions-*.json"):
    h = apply(f, [])
    if h: report.append((f, h))
# 4) server / bin
for pat in ("server", "bin"):
    for f in g(pat, "*.mjs"):
        h = apply(f, SERVER_REPL)
        if h: report.append((f, h))

for f, h in report:
    print(f"[rebrand] {os.path.relpath(f, target)}")
    for old, n in h: print(f"    {n:3d} × {old}")

# ---- 二维码替换 ----
def make_qr(url, path):
    try:
        import qrcode
        img = qrcode.make(url).convert("RGB")
        img.save(path, "JPEG", quality=92)
        return True
    except Exception as e:
        print(f"[rebrand] ⚠️ 生成二维码失败({e})，跳过 {path}")
        return False

qr_jobs = [("wechat-qr-*.jpg", REPO_URL), ("wechat-official-qr-*.jpg", PROFILE_URL)]
for pattern, url in qr_jobs:
    for f in g("web", "assets", pattern):
        if make_qr(url, f):
            print(f"[rebrand] 二维码已替换: {os.path.basename(f)} → {url}")

# ---- 残留检查 ----
left = 0
files = []
for root, dirs, names in os.walk(target):
    dirs[:] = [d for d in dirs if d not in ("licenses", "node_modules")]
    for n in names:
        if not n.endswith((".js", ".mjs", ".html", ".json", ".css")): continue
        p = os.path.join(root, n)
        try: c = protect(io.open(p, encoding="utf-8", errors="ignore").read()).lower().count("ffclip")
        except Exception: continue
        if c: left += c; files.append((os.path.relpath(p, target), c))
if left:
    print(f"[rebrand] ⚠️ 仍有 {left} 处 ffclip 残留（多为受保护的 npm 包名等机制字符串）:")
    for f, c in files[:10]: print(f"    {f}: {c}")
else:
    print("[rebrand] ✅ 无 ffclip 残留")
# ---- 语法校验（黑屏兜底：任何 JS 改坏都在这里拦下）----
import subprocess, shutil
node = shutil.which("node")
if node:
    bad = []
    for f in g("web", "assets", "*.js") + g("server", "*.mjs") + g("bin", "*.mjs"):
        r = subprocess.run([node, "--check", f], capture_output=True, text=True)
        if r.returncode != 0:
            bad.append((f, (r.stderr or "").strip().splitlines()[-1] if r.stderr else "unknown"))
    if bad:
        for f, err in bad: print(f"[rebrand] ❌ 语法校验失败: {os.path.relpath(f, target)}\n    {err}")
        sys.exit(1)
    print(f"[rebrand] ✅ 全部 JS 语法校验通过")
else:
    print("[rebrand] ⚠️ 未找到 node，跳过语法校验")
print("[rebrand] 完成")
PYEOF
