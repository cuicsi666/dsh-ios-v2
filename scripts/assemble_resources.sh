#!/usr/bin/env bash
# 装配 App 运行资源：内嵌 node 运行时 + dsh 全家桶
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
RES="$ROOT/resources"
DSH_VER="${DSH_VER:-0.2.0-rc.2}"

mkdir -p "$RES/dsh"

if [ ! -x "$RES/node" ]; then
  echo "!! resources/node 缺失（应由 workflow 下载预编译 node）"
  exit 1
fi
echo "node: $(python3 -c "import os;print(os.path.getsize('$RES/node'))") bytes"

if [ ! -f "$RES/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js" ]; then
  echo "--- 安装 dsh@$DSH_VER ---"
  cat > "$RES/dsh/package.json" <<EOF
{
  "name": "dsh-bundle",
  "private": true,
  "version": "1.0.0",
  "dependencies": { "@deepseek-ai/dsh": "$DSH_VER" }
}
EOF
  ( cd "$RES/dsh" && npm install --no-audit --no-fund --ignore-scripts=false 2>&1 | tail -5 )
fi

echo "--- 原始体积 ---"
du -sh "$RES/dsh/node_modules"

echo "--- 裁剪 ---"
python3 "$ROOT/scripts/prune_bundle.py" "$RES/dsh/node_modules" || true

echo "--- 裁剪后体积 ---"
du -sh "$RES/dsh/node_modules"
du -sh "$RES/dsh"
