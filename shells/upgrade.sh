#!/bin/sh
# 官方 dsh 的一次完整升级 —— 把「升级后实例起不来」这件事提前到本脚本里做完。
#
# 为什么需要它：宿主的 rc 版本是按**精确 peer** 判兼容的（`@deepseek-ai/dsh-scope: 0.2.0-rc.1`
# 这类写法），而 profile 里已装的插件不会因为 `git pull` 自己跟着走。于是升级 + 重启会得到
# 一片 `disabling profile plugin row …` 和一句 `startup failed: 1 required plugin did not
# activate`，而排查要从 startup 日志里逐条找被禁的行（本机 2026-09-30 实际发生过）。
#
# 一次升级要做的事，按顺序：
#   1) 拉代码（--ff-only，避免把 fork 的提交历史搅乱）
#   2) 装依赖 + 编译（客户端产物不重新构建的话，实例起来也是空页面）
#   3) 停实例（带着旧代码跑着的实例会一直持有旧服务）
#   4) profile 对齐到新宿主版本（插件仓库的 scripts/align-host.mjs）：
#        · 同步发布年龄豁免名单 —— 新版本刚发布时会被 pnpm 的 supply-chain 策略拒绝，
#          不同步的话每一步 `dsh plugin add` 都失败；
#        · 把 `@deepseek-ai/dsh-*` 全部钉回新版本 —— 只改直接依赖不够，其余靠 peer 图解析；
#        · 迁移第三方插件的精确版本豁免（可用 --no-third-party 关掉）。
#   5) 插件仓库重装 + 三层验证（install-or-update.sh，可用 --no-plugins 跳过）
#   6) 启动，并自检启动日志里没有门禁禁用 / 启动失败
#
# 默认目标与 run.sh、stop.sh 一致：home=~/.dsh-official  profile=web  端口=13080。
# 改动其中任意一个时，本脚本不再调用 stop.sh / run.sh（它们把目标写死），改用内建启停，
# 否则会去重启另一个 profile。改造版（~/.dsh :3080）永远不碰。
#
# 用法：
#   ./upgrade.sh                        # 完整升级（拉代码 → 编译 → 对齐 → 装插件 → 启动自检）
#   ./upgrade.sh --no-pull              # 代码已手动更新，跳过 git pull
#   ./upgrade.sh --no-build             # 跳过 pnpm install 与编译
#   ./upgrade.sh --no-plugins           # 不重装插件仓库（只做宿主侧对齐）
#   ./upgrade.sh --no-third-party       # 不迁移第三方插件的版本豁免
#   ./upgrade.sh --no-restart           # 只升级不启动
#   ./upgrade.sh --dry-run              # 只打印将要执行的动作
#   ./upgrade.sh --allow-dirty          # 工作区有未提交改动也继续（默认中止）
#   ./upgrade.sh --plugins-repo <path>  # 指定插件仓库（默认 ../deepseek-harness-plugins）
#   ./upgrade.sh --profile <name> --dsh-home <home> --port <port>
#
# 每次运行都会把各步的输出落到 /tmp/dsh-upgrade-*.log，失败时给出完整日志路径。
set -eu

# `$0` 在下面的 `cd` 之后就不再是有效路径了（它是相对调用时写的），所以先把绝对路径存下来：
# usage() 会在 cd 之后被调用，用 $0 去 sed 只会得到 "No such file or directory"。
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh-official}"
PROFILE='web'
PORT='13080'
PLUGINS_REPO="$REPO/../deepseek-harness-plugins"
DO_PULL=1
DO_BUILD=1
DO_PLUGINS=1
DO_THIRD_PARTY=1
DO_RESTART=1
DRY_RUN=0
ALLOW_DIRTY=0

usage() {
  sed -n '2,/^set -eu/p' "$SELF" | grep '^#' | sed 's/^#\{1,\} \{0,1\}//'
  exit 0
}
fail() { echo "✗ $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --dsh-home) DSH_HOME_DIR="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --plugins-repo) PLUGINS_REPO="$2"; shift 2 ;;
    --no-pull) DO_PULL=0; shift ;;
    --no-build) DO_BUILD=0; shift ;;
    --no-plugins) DO_PLUGINS=0; shift ;;
    --no-third-party) DO_THIRD_PARTY=0; shift ;;
    --no-restart) DO_RESTART=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    -h|--help) usage ;;
    *) fail "未知参数：$1（用 --help 看用法）" ;;
  esac
done

command -v node >/dev/null 2>&1 || fail '缺 node'
command -v pnpm >/dev/null 2>&1 || fail '缺 pnpm'
command -v git >/dev/null 2>&1 || fail '缺 git'

# 本机 IDE 会给 node 注入 safe-delete 钩子，它在 pnpm 释放锁删文件时抛异常、让整条命令崩掉，
# 而真正的安装其实已经完成。前置这个变量即可绕开（插件仓库 changes/0017 记过同源问题）。
export CODEBUDDY_SAFE_DELETE_ENABLED=0

PULL_LOG=/tmp/dsh-upgrade-pull.log
REVERT_LOG=/tmp/dsh-upgrade-revert.log
INSTALL_LOG=/tmp/dsh-upgrade-install.log
BUILD_LOG=/tmp/dsh-upgrade-build.log
ALIGN_LOG=/tmp/dsh-upgrade-align.log
PLUGINS_LOG=/tmp/dsh-upgrade-plugins.log
RUN_LOG=/tmp/dsh-official-$PROFILE.log

current_version() { node -p "require('$REPO/package.json').version" 2>/dev/null || echo ''; }

# 一步一个日志文件：失败时给出完整路径，而不是让构建的长输出把失败原因冲走。
run_step() {
  label="$1"; log_file="$2"; shift 2
  echo ""
  echo "── ${label} ──"
  if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] $*"
    echo "[dry-run] 日志将写入 ${log_file}"
    return 0
  fi
  status=0
  "$@" >"$log_file" 2>&1 || status=$?
  tail -n 15 "$log_file"
  [ "$status" -eq 0 ] || fail "${label} 失败（退出码 ${status}），完整日志：${log_file}"
}

# 只停**监听方**且命令行像 dsh 的进程：两套 dsh 的命令行相同，按名字杀会误伤改造版。
stop_instance() {
  echo ""
  echo '── 停止官方实例 ──'
  for pid in $(lsof -t -i:"$PORT" -sTCP:LISTEN 2>/dev/null || true); do
    if ps -p "$pid" -o command= 2>/dev/null | grep -q 'bin\.ts'; then
      if [ "$DRY_RUN" = 1 ]; then
        echo "[dry-run] 将停止 PID ${pid}"
      else
        kill "$pid" 2>/dev/null || true
        echo "已停止官方实例（PID ${pid}）"
      fi
    else
      echo "端口 ${PORT} 被非 dsh 进程占用（PID ${pid}），不杀"
    fi
  done
}

start_instance() {
  echo ""
  echo '── 启动官方实例 ──'
  if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] 将启动 home=${DSH_HOME_DIR} profile=${PROFILE} 端口=${PORT}"
    return 0
  fi
  if [ "$PROFILE" = 'web' ] && [ "$PORT" = '13080' ] && [ "$DSH_HOME_DIR" = "$HOME/.dsh-official" ]; then
    (cd "$REPO/shells" && nohup ./run.sh >>"$RUN_LOG" 2>&1 &)
  else
    # 目标被改过，stop.sh / run.sh 会去动另一个 profile，因此走内建启动。
    (cd "$REPO" && DSH_HOME="$DSH_HOME_DIR" NODE_OPTIONS="--max-old-space-size=12288" \
      nohup pnpm dsh --profile "$PROFILE" --port "$PORT" >>"$RUN_LOG" 2>&1 &)
  fi
  waited=0
  while [ "$waited" -lt 60 ]; do
    if lsof -t -i:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then break; fi
    waited=$((waited + 1))
    sleep 1
  done
  lsof -t -i:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || fail "实例没起来（等了 60 秒），看日志：${RUN_LOG}"
  echo "✓ 已监听 ${PORT}（日志 ${RUN_LOG}）"
}

check_startup_log() {
  # 版本门禁的三类输出任一出现都意味着这次升级没真正生效——直接失败，不要留给用户在页面上发现。
  if grep -qE 'disabling profile plugin row|skipping profile bundle|Plugins waiting for services|startup failed' "$RUN_LOG"; then
    echo ""
    echo '✗ 启动日志里仍有版本门禁的禁用项：'
    grep -E 'disabling profile plugin row|skipping profile bundle|Plugins waiting for services|startup failed' "$RUN_LOG" | head -20
    fail "完整日志：${RUN_LOG}"
  fi
  url=$(grep -E '^dsh web: http' "$RUN_LOG" | tail -1 || true)
  [ -n "$url" ] && echo "  ${url#dsh web: }"
}

echo "官方 dsh 升级：${REPO}"
echo "  home=${DSH_HOME_DIR}  profile=${PROFILE}  端口=${PORT}"
echo "  插件仓库=${PLUGINS_REPO}"

VERSION_BEFORE=$(current_version)
echo "  当前宿主版本：${VERSION_BEFORE:-（读不到）}"

# ── 1) 拉代码 ────────────────────────────────────────────────────────────────
if [ "$DO_PULL" = 1 ]; then
  # 插件仓库给宿主源码打的两处兼容补丁（会话事件 ignorable / 空闲取消落日志）会让工作区变 dirty，
  # 而 pull 撞上被改过的源码轻则冲突、重则把补丁连同官方改动一起搅乱。补丁是可重建的（幂等、
  # 有备份、可撤销），所以 pull 之前先撤掉，升级后由插件安装流程重新打上。
  if [ -f "$PLUGINS_REPO/scripts/patch-dsh-host-compat.mjs" ]; then
    run_step '撤销宿主兼容补丁（升级后由插件安装流程重新打上）' "$REVERT_LOG" \
      sh -c "cd '$PLUGINS_REPO' && DSH_REPO='$REPO' node scripts/patch-dsh-host-compat.mjs --revert"
  fi
  echo ""
  echo '── 检查工作区 ──'
  if [ "$(git status --porcelain)" != '' ]; then
    if [ "$ALLOW_DIRTY" = 1 ]; then
      echo '工作区有未提交改动，按 --allow-dirty 继续（git pull 若与这些改动冲突会失败）'
    else
      git status --porcelain | head -10
      fail '工作区不干净，`git pull` 会被拒绝或产生冲突。
  常见来源：本仓库跑测试留下的快照（snapshots/**）、插件仓库的宿主补丁（上面已撤销）。
  处理：提交或丢弃这些改动后重跑；确认无碍时加 --allow-dirty。'
    fi
  else
    echo '✓ 工作区干净'
  fi
  run_step '拉取代码（--ff-only）' "$PULL_LOG" git pull --ff-only
else
  echo ''
  echo '── 拉取代码：按 --no-pull 跳过 ──'
fi

VERSION_AFTER=$(current_version)
if [ "$VERSION_BEFORE" = "$VERSION_AFTER" ]; then
  echo "  宿主版本未变：${VERSION_AFTER:-（读不到）}（本次仍会编译与重装，代码可能有新提交）"
else
  echo "  宿主版本：${VERSION_BEFORE} → ${VERSION_AFTER}"
fi

# ── 2) 依赖与编译 ────────────────────────────────────────────────────────────
if [ "$DO_BUILD" = 1 ]; then
  run_step '安装依赖' "$INSTALL_LOG" pnpm install
  run_step '编译（含客户端产物）' "$BUILD_LOG" pnpm run build
else
  echo ''
  echo '── 依赖与编译：按 --no-build 跳过 ──'
fi

# ── 3) 停实例 ────────────────────────────────────────────────────────────────
stop_instance

# ── 4) profile 对齐到新宿主版本 ──────────────────────────────────────────────
ALIGN_ARGS="--dsh-home $DSH_HOME_DIR --profile $PROFILE --dsh $REPO"
[ "$DO_THIRD_PARTY" = 1 ] && ALIGN_ARGS="$ALIGN_ARGS --allow-third-party"
[ "$DRY_RUN" = 1 ] && ALIGN_ARGS="$ALIGN_ARGS --dry-run"
if [ -f "$PLUGINS_REPO/scripts/align-host.mjs" ]; then
  run_step 'profile 对齐到新宿主版本' "$ALIGN_LOG" \
    sh -c "cd '$PLUGINS_REPO' && node scripts/align-host.mjs $ALIGN_ARGS"
else
  echo ''
  echo "── profile 对齐：插件仓库里没有 scripts/align-host.mjs（${PLUGINS_REPO}），跳过 ──"
  echo '   宿主升级后这一步不能省：它会把 profile 里的宿主包钉回新版本，'
  echo '   否则重启时官方版本门禁会禁用整片挂载行、实例起不来。'
fi

# ── 5) 插件仓库重装 + 三层验证 ───────────────────────────────────────────────
if [ "$DO_PLUGINS" = 1 ]; then
  if [ -f "$PLUGINS_REPO/install-or-update.sh" ]; then
    PLUGIN_ARGS="--dsh $REPO --dsh-home $DSH_HOME_DIR --profile $PROFILE --port $PORT --no-restart"
    # 重启由本脚本统一负责（它还要做启动自检），这里只装与验证。
    run_step '插件仓库重装 + 三层验证' "$PLUGINS_LOG" \
      sh -c "cd '$PLUGINS_REPO' && DSH_RESTART=no ./install-or-update.sh $PLUGIN_ARGS"
  else
    echo ''
    echo "── 插件仓库重装：没找到 ${PLUGINS_REPO}/install-or-update.sh，跳过 ──"
  fi
else
  echo ''
  echo '── 插件仓库重装：按 --no-plugins 跳过 ──'
fi

# ── 6) 启动与自检 ────────────────────────────────────────────────────────────
if [ "$DO_RESTART" = 1 ]; then
  # dry-run 不能清空 RUN_LOG：那是上一次启动的日志，清空等于让一次"什么都不做"的运行产生了副作用。
  if [ "$DRY_RUN" = 1 ]; then
    echo ''
    echo "[dry-run] 将清空 ${RUN_LOG} 重新记录，并自检其中没有版本门禁的禁用项"
  else
    : >"$RUN_LOG" 2>/dev/null || true
    start_instance
    echo ''
    echo '── 启动自检 ──'
    check_startup_log
    echo '✓ 启动日志里没有版本门禁的禁用项'
  fi
else
  echo ''
  echo '── 启动：按 --no-restart 跳过 ──'
  echo "  手动启动：cd ${REPO}/shells && ./run.sh"
fi

echo ''
echo "✓ 升级完成。宿主版本：${VERSION_AFTER:-（读不到）}"
