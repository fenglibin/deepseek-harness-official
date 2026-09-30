#!/bin/sh
# Local `dsh web` launcher —— **官方 dsh 专用实例**。
#
# 本机同时跑两套 dsh，靠 HOME 与端口两条线隔离，缺一条就会互相抢配置或抢端口：
#   官方版（本仓库）          : DSH_HOME=~/.dsh-official   端口 13080
#   改造版（../deepseek-harness）: DSH_HOME=~/.dsh          端口 3080（缺省值）
#
# 为什么用 DSH_HOME 而不是改 profile：dsh 的所有可变状态（profiles、sessions、logs、
# credentials、storages、用户层 cordis 配置）都从 resolveDshHome() 派生
# （见 packages/util/home-paths/src/index.ts），换 home 即彻底分家，两套互不可见。
#
# 为什么端口用命令行参数：packages/boot/cmdline/src/index.ts 的
# `ctx.webStartup.port ?? 3080` —— 命令行 --port 覆盖配置值，所以隔离端口不需要动
# 任何配置文件（也就不需要在两边同步配置）。
#
# The heap ceiling is explicit so `session-controller heap watermark` has a
# ceiling to report against; the default 4 GB is a Node default, not a policy.
#
# Do NOT add `--heapsnapshot-near-heap-limit` here. V8 builds the snapshot graph
# synchronously on the main thread before it streams anything, so at a
# multi-gigabyte heap the process stops answering HTTP for as long as the graph
# takes to build — and the graph itself costs multiples of the heap. A near-limit
# capture therefore turns a crash that leaves a FATAL ERROR and a watermark curve
# into an unbounded stall that leaves neither. Capture a snapshot deliberately
# (from a live inspector session, or with a small heap in a reproduction).
cd ..
DSH_HOME="$HOME/.dsh-official" NODE_OPTIONS="--max-old-space-size=12288" pnpm dsh --profile web --port 13080
