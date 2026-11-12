#!/bin/bash
# ============================================================
# Hermes Agent 完全离线安装脚本
# ------------------------------------------------------------
# 用法：
#   tar xzf hermes-offline-*.tar.gz
#   cd hermes-offline
#   sudo ./install.sh                              # 默认装到 /opt/hermes
#   sudo HERMES_PREFIX=/data/hermes ./install.sh   # 自定义路径
#
# 全程不需要网络，不需要 uv，不需要系统里装 Python 3.11。
# ============================================================
set -euo pipefail

PREFIX="${HERMES_PREFIX:-/opt/hermes}"
BINDIR="${HERMES_BINDIR:-/usr/local/bin}"
PWROOT="${HERMES_PLAYWRIGHT_DIR:-$HOME/.cache/ms-playwright}"
SRCDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GRN=$'\033[0;32m'; YEL=$'\033[1;33m'; CYN=$'\033[1;36m'; RED=$'\033[0;31m'; RST=$'\033[0m'
say()  { echo -e "\n${CYN}[$1]${RST} $2"; }
ok()   { echo -e "  ${GRN}✓${RST} $*"; }
warn() { echo -e "  ${YEL}!${RST} $*"; }
die()  { echo -e "\n${RED}✗ 安装中止：$*${RST}\n" >&2; exit 1; }

cat <<'BANNER'
============================================================
  Hermes Agent —— 完全离线安装
============================================================
BANNER

# ---------------- 1. 环境检查 ----------------
say "1/7" "环境检查"

[ "$(id -u)" -eq 0 ] || die "请用 root 运行（需要写 $BINDIR 和 $PREFIX）"

ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] || die "本包是 x86_64 架构，当前机器是 $ARCH。ARM 机器（鲲鹏/飞腾）需要重新构建。"
ok "架构 $ARCH"

GLIBC=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $NF}')
[ -n "$GLIBC" ] || GLIBC=$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1)
[ -n "$GLIBC" ] || die "无法识别 glibc 版本"
need="2.28"
if [ "$(printf '%s\n%s\n' "$need" "$GLIBC" | sort -V | head -1)" != "$need" ]; then
    die "glibc $GLIBC 太旧，需要 >= $need（CentOS 7 是 2.17，跑不了）"
fi
ok "glibc $GLIBC"

AVAIL=$(df -Pk "$(dirname "$PREFIX")" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
NEED_KB=$(du -sk "$SRCDIR" 2>/dev/null | awk '{print $1}')
if [ "${AVAIL:-0}" -lt $((NEED_KB * 11 / 10)) ]; then
    die "磁盘空间不足：需要约 $((NEED_KB/1024/1024))GB，可用 $((AVAIL/1024/1024))GB"
fi
ok "磁盘余量 $((AVAIL/1024/1024))GB"

for d in app/venv/bin/python3 app/hermes_cli python; do
    # 注意用 -e 或 -L：venv 里的 python 是指向构建机绝对路径的符号链接，
    # 在目标机上它是断链，-e 会返回假，误判成"包不完整"
    [ -e "$SRCDIR/$d" ] || [ -L "$SRCDIR/$d" ] || die "安装包不完整，缺少 $d（是不是没解压全？）"
done
ok "安装包完整"

# ---------------- 2. 落盘 ----------------
say "2/7" "释放文件到 $PREFIX"
if [ -e "$PREFIX" ]; then
    if [ -e "$PREFIX/app/hermes_cli" ]; then
        BAK="$PREFIX.bak.$(date +%Y%m%d_%H%M%S)"
        warn "检测到已有安装，先备份到 $BAK"
        mv "$PREFIX" "$BAK"
    else
        warn "$PREFIX 已存在但不是 Hermes 安装，清理掉"
        rm -rf "$PREFIX"
    fi
fi
mkdir -p "$PREFIX"
cp -a "$SRCDIR/app" "$PREFIX/app"
cp -a "$SRCDIR/python" "$PREFIX/python"
[ -d "$SRCDIR/node" ] && cp -a "$SRCDIR/node" "$PREFIX/node"
ok "已释放 $(du -sh "$PREFIX" | awk '{print $1}')"

# ---------------- 3. venv 重定位 ----------------
say "3/7" "修正 Python 虚拟环境路径"
VENV="$PREFIX/app/venv"

# ⚠️ 这里不能用 [ -x "$VENV/bin/python3" ] 做前置检查。
# venv/bin/python3 是符号链接，最终指向包内 CPython；在重建链接之前，
# 它要么是构建机的绝对路径死链，要么依赖 python/ 目录的链接链完整。
# -x 遇到断链直接返回假，会把"还没重建"误报成"包有问题"。
# 正确做法：先确认包内解释器本体在，再重建链接，最后才验可执行。

PYBIN="$PREFIX/python/cpython-3.11-linux-x86_64-gnu/bin/python3.11"
[ -e "$PYBIN" ] || [ -L "$PYBIN" ] || die "包内解释器缺失：$PYBIN（检查 python/ 目录是否完整拷过来了）"
[ -f "$PYBIN" ] || die "包内解释器不是普通文件：$PYBIN"

cat > "$VENV/pyvenv.cfg" <<EOF
home = $PREFIX/python/cpython-3.11-linux-x86_64-gnu/bin
implementation = CPython
version_info = 3.11
include-system-site-packages = false
EOF

# ⚠️ venv/bin/python 原本指向构建机的绝对路径（/usr/local/share/uv/python/...），
# 在目标机上这是断链，必须先重建成包内解释器，否则整个 venv 起不来。
ln -sfn "$PYBIN" "$VENV/bin/python"
ln -sfn "python" "$VENV/bin/python3"
ln -sfn "python" "$VENV/bin/python3.11"

# 链接重建之后 -x 才有意义：此时 python3 已经指向确实存在的包内解释器
[ -x "$VENV/bin/python3" ] || die "venv/bin/python3 不可执行（解析为：$(readlink -f "$VENV/bin/python3" 2>/dev/null || echo '断链')）"
ok "解释器链接已重建 → $PYBIN"

n_fixed=0
for f in "$VENV"/bin/*; do
    [ -f "$f" ] || continue
    head -c 2 "$f" 2>/dev/null | grep -q '#!' || continue
    if head -1 "$f" | grep -qE '^#!.*python'; then
        sed -i "1s|^#!.*python[0-9.]*|#!$VENV/bin/python3|" "$f"
        n_fixed=$((n_fixed+1))
    fi
done
ok "pyvenv.cfg 指向 $PREFIX/python"
ok "修正了 $n_fixed 个可执行脚本的 shebang"

# editable 安装的模块路径映射里有硬编码的旧安装路径，必须一起改，
# 否则目标机上 import 会指向一个不存在的目录（而构建机上测试却正常）。
FINDERS=$(ls "$VENV"/lib/python3.11/site-packages/__editable___*_finder.py 2>/dev/null || true)
if [ -n "$FINDERS" ]; then
    OLD_APP=$(grep -ohE "/[A-Za-z0-9_./-]+/hermes_cli" $FINDERS 2>/dev/null | head -1 | sed 's|/hermes_cli$||')
    if [ -n "$OLD_APP" ] && [ "$OLD_APP" != "$PREFIX/app" ]; then
        sed -i "s|$OLD_APP|$PREFIX/app|g" $FINDERS
        ok "模块路径映射：$OLD_APP → $PREFIX/app"
    else
        ok "模块路径映射已指向 $PREFIX/app"
    fi
fi

"$VENV/bin/python3" -c 'import sys; assert sys.version_info[:2]==(3,11), sys.version' \
    || die "venv 里的 Python 起不来，检查 $PREFIX/python 是否完整"
ok "解释器自检通过：$("$VENV/bin/python3" --version)"

# ---------------- 4. 依赖校验 ----------------
say "4/7" "校验 Python 依赖（提前暴露 glibc 不兼容）"
SITE="$VENV/lib/python3.11/site-packages"
NSPKG=$(find "$SITE" -maxdepth 1 -name '*.dist-info' -type d 2>/dev/null | wc -l)
"$VENV/bin/python3" - <<'PYEOF' || die "关键依赖导入失败（多为目标机 glibc 与构建机差异过大）"
import importlib, sys
mods = ['openpyxl','yaml','httpx','aiohttp','pydantic','prompt_toolkit','rich','jinja2','click','playwright']
fail = []
for m in mods:
    try:
        importlib.import_module(m)
    except Exception as e:
        fail.append(f'{m}: {type(e).__name__}: {e}')
if fail:
    print('\n'.join(fail)); sys.exit(1)
print('关键模块全部导入成功')
PYEOF
ok "已安装 $NSPKG 个依赖包，关键模块导入正常"

# ---------------- 5. Playwright ----------------
say "5/7" "部署 Playwright 浏览器"
if [ -d "$SRCDIR/playwright" ] && [ -n "$(ls -A "$SRCDIR/playwright" 2>/dev/null)" ]; then
    mkdir -p "$PWROOT"
    cp -a "$SRCDIR/playwright"/* "$PWROOT"/
    ok "浏览器已放到 $PWROOT（$(du -sh "$PWROOT" | awk '{print $1}')）"
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        chown -R "$SUDO_USER":"$SUDO_USER" "$PWROOT" 2>/dev/null || true
        warn "已把浏览器目录属主改为 $SUDO_USER"
    fi
else
    warn "包内没有浏览器缓存，浏览器自动化不可用（其余功能不受影响）"
fi

# ---------------- 6. 命令入口 ----------------
say "6/7" "安装命令入口"
mkdir -p "$BINDIR"
ln -sfn "$VENV/bin/hermes" "$BINDIR/hermes"
ok "$BINDIR/hermes -> $VENV/bin/hermes"

if [ -x "$PREFIX/node/bin/node" ]; then
    ln -sfn "$PREFIX/node/bin/node" "$BINDIR/node-hermes"
    ln -sfn "$PREFIX/node/bin/npm"  "$BINDIR/npm-hermes"
    ok "Node $("$PREFIX/node/bin/node" --version) 已可用（node-hermes / npm-hermes）"
fi

# ---------------- 7. 自检 ----------------
say "7/7" "端到端自检"
VER=$("$VENV/bin/hermes" --version 2>&1 | head -1) || true
[ -n "$VER" ] || die "hermes 命令跑不起来"
ok "hermes --version → $VER"

cat > "$PREFIX/hermes-env.sh" <<EOF
# 把下面一行加进 ~/.bashrc 即可直接使用 hermes
export PATH="$PREFIX/node/bin:\$PATH"
export PATH="$BINDIR:\$PATH"
export PLAYWRIGHT_BROWSERS_PATH="$PWROOT"
EOF

"$VENV/bin/hermes" doctor >/dev/null 2>&1 \
    && ok "hermes doctor 通过" \
    || warn "hermes doctor 有提示项（首次使用需跑 hermes setup，属正常）"

cat <<EOF

${GRN}============================================================${RST}
${GRN}  安装完成${RST}
${GRN}============================================================${RST}

  安装路径 : $PREFIX
  命令     : $BINDIR/hermes
  Python   : $PREFIX/python（自带 3.11，与系统 Python 无关）
  依赖     : $NSPKG 个包，全部离线内置

  下一步：

    hermes setup        # 配置模型和 API key（需要网络，一次性）
    hermes              # 进入对话
    hermes gateway      # 启动消息平台网关
    hermes --tui        # 终端界面

  想直接跑命令，把环境串进来：

    source $PREFIX/hermes-env.sh

${YEL}注意${RST}：本包不含任何配置文件、密钥和历史会话，
      首次使用需要 hermes setup 自行配置。

EOF
