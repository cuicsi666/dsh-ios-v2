#!/usr/bin/env bash
# 构建无签名 IPA（侧载用：AltStore / 全能签 / TrollStore 均可）
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="DSH助手"
IPA_NAME="${IPA_NAME:-dsh助手_V2.ipa}"
RES="$ROOT/resources"
DIST="$ROOT/dist"
mkdir -p "$DIST"

echo "=== 1. 生成工程 ==="
xcodegen generate --spec project.yml

echo "=== 2. 编译 ==="
set -o pipefail
xcodebuild -project DashHarness.xcodeproj \
  -scheme DashHarness \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$ROOT/build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  clean build 2>&1 | tail -30

APP=$(find "$ROOT/build/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" | head -1)
[ -d "$APP" ] || { echo "!! 未找到 .app"; exit 1; }
echo "app: $APP"

echo "=== 3. 注入运行资源 ==="
rm -rf "$APP/node" "$APP/dsh"
cp "$RES/node" "$APP/node"
chmod +x "$APP/node"
/usr/bin/ditto "$RES/dsh" "$APP/dsh"
test -f "$APP/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js" || { echo "!! dsh 入口缺失"; exit 1; }
du -sh "$APP"

echo "=== 4. 伪签名全部 Mach-O ==="
if ! command -v ldid >/dev/null 2>&1; then
  brew install ldid >/dev/null 2>&1 || true
fi
command -v ldid >/dev/null 2>&1 || { echo "!! ldid 不可用"; exit 1; }
python3 - "$APP" <<'PY'
import os, sys, subprocess
root = sys.argv[1]
MAGIC = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe'}
signed = 0
for base, dirs, files in os.walk(root):
    for f in files:
        p = os.path.join(base, f)
        try:
            if os.path.islink(p):
                continue
            with open(p, 'rb') as fh:
                m = fh.read(4)
            if m in MAGIC:
                subprocess.run(['ldid', '-S', p], check=True)
                signed += 1
        except Exception as e:
            print('sign skip', p, e)
print('signed Mach-O files:', signed)
PY

echo "=== 5. 打包 IPA ==="
STAGE="$ROOT/build/ipa"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
/usr/bin/ditto "$APP" "$STAGE/Payload/$(basename "$APP")"
( cd "$STAGE" && /usr/bin/zip -qry "$DIST/$IPA_NAME" Payload )

SIZE=$(stat -f%z "$DIST/$IPA_NAME" 2>/dev/null || stat -c%s "$DIST/$IPA_NAME")
echo "IPA: $DIST/$IPA_NAME  size=$SIZE"
if [ "$SIZE" -lt 80000000 ]; then
  echo "!! IPA 体积异常（<80MB），判定构建失败"; exit 1
fi
md5 -q "$DIST/$IPA_NAME" 2>/dev/null || md5sum "$DIST/$IPA_NAME"
