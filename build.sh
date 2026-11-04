#!/bin/bash
# ============================================================
# Hermes Agent 离线安装包 —— 构建脚本
# ------------------------------------------------------------
# 在「已经装好 Hermes 且能联网」的机器上运行，产出可直接离线安装的包。
# 用法：./build.sh
# ============================================================
set -euo pipefail

# ---------- 源路径（按需修改）----------
SRC_APP="${SRC_APP:-/usr/local/lib/hermes-agent}"
SRC_PY="${SRC_PY:-/usr/local/share/uv/python/cpython-3.11.15-linux-x86_64-gnu}"
SRC_NODE="${SRC_NODE:-$HOME/.hermes/node}"
SRC_PW="${SRC_PW:-$HOME/.cache/ms-playwright}"

# ---------- 输出 ----------
STAMP=$(date +%Y%m%d)
BUILD="${BUILD:-$(pwd)/build}"
PKG="$BUILD/hermes-offline"
OUT="$BUILD/hermes-offline-${STAMP}-x86_64"

say() { echo -e "\n\033[1;36m[$(date +%H:%M:%S)] $*\033[0m"; }

say "0/7 环境检查"
command -v rsync >/dev/null || { echo "缺少 rsync，请先安装"; exit 1; }
for p in "$SRC_APP" "$SRC_PY"; do
    [ -e "$p" ] || { echo "源路径不存在: $p"; exit 1; }
done
echo "  Hermes : $SRC_APP"
echo "  Python : $SRC_PY"
[ -d "$SRC_NODE" ] && echo "  Node   : $SRC_NODE" || echo "  Node   : 未找到（TUI/desktop 将不可用）"
[ -d "$SRC_PW" ]   && echo "  Browser: $SRC_PW"   || echo "  Browser: 未找到（浏览器自动化将不可用）"

rm -rf "$PKG"
mkdir -p "$PKG"/{app,python,node}

say "1/7 复制 Hermes 源码"
rsync -a \
    --exclude='.git/' --exclude='.venv/' --exclude='tests/' \
    --exclude='website/' --exclude='node_modules/' \
    --exclude='__pycache__/' --exclude='*.pyc' \
    "$SRC_APP"/ "$PKG/app"/
du -sh "$PKG/app"

say "2/7 复制 Python 虚拟环境"
rsync -a --exclude='__pycache__/' "$SRC_APP/venv"/ "$PKG/app/venv"/
du -sh "$PKG/app/venv"

if [ -d "$SRC_APP/node_modules" ]; then
    say "3/7 复制 node_modules"
    rsync -a "$SRC_APP/node_modules"/ "$PKG/app/node_modules"/
    [ -f "$SRC_APP/package-lock.json" ] && cp "$SRC_APP/package-lock.json" "$PKG/app/"
    du -sh "$PKG/app/node_modules"
else
    say "3/7 跳过 node_modules（源环境没有）"
fi

say "4/7 复制独立 Python 解释器"
rsync -a "$SRC_PY"/ "$PKG/python/cpython-3.11.15-linux-x86_64-gnu"/
# venv 的 pyvenv.cfg 指向不带小版本号的软链，保留这个结构
ln -sfn "cpython-3.11.15-linux-x86_64-gnu" "$PKG/python/cpython-3.11-linux-x86_64-gnu"
du -sh "$PKG/python"

if [ -d "$SRC_NODE" ]; then
    say "5/7 复制 Node.js 运行时"
    rsync -a --exclude='CHANGELOG.md' --exclude='share/doc/' "$SRC_NODE"/ "$PKG/node"/
    du -sh "$PKG/node"
else
    say "5/7 跳过 Node.js"
    rmdir "$PKG/node" 2>/dev/null || true
fi

say "6/7 复制 Playwright 浏览器"
if [ -d "$SRC_PW" ]; then
    mkdir -p "$PKG/playwright"
    rsync -a "$SRC_PW"/ "$PKG/playwright"/
    du -sh "$PKG/playwright"
else
    echo "  跳过"
fi

say "7/7 打包"
cp "$(dirname "$0")/install.sh" "$PKG/install.sh"
chmod +x "$PKG/install.sh"

cat > "$PKG/BUILD-INFO.txt" <<EOF
Hermes Agent 离线安装包
构建时间: $(date '+%Y-%m-%d %H:%M:%S')
构建主机: $(hostname) / $(uname -m)
系统: $(cat /etc/redhat-release 2>/dev/null || grep PRETTY /etc/os-release | cut -d= -f2-)
glibc: $(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $NF}')
Python: $("$SRC_APP/venv/bin/python3" --version 2>/dev/null)
Node: $("$SRC_NODE/bin/node" --version 2>/dev/null || echo 'N/A')

安装: tar xzf <包名>.tar.gz && cd hermes-offline && sudo ./install.sh
EOF

cd "$BUILD"
tar czf "${OUT}.tar.gz" hermes-offline

echo
echo "============================================"
echo " 打包完成"
ls -lh "${OUT}.tar.gz"
echo "============================================"
