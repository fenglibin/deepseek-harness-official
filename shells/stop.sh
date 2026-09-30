#!/bin/sh
# 只停官方版 dsh（监听 13080）。改造版在 3080，由另一套脚本负责，这里刻意不碰。
#
# 别改用 `pkill -f "bin.ts web"`：那个模式会同时命中改造版的进程（两套都是
# `node --import tsx/esm apps/cli/src/bin.ts`），一次误杀会打断正在跑的任务。
lsof -t -i:13080 | xargs kill 2>/dev/null
