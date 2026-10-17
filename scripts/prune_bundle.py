#!/usr/bin/env python3
"""裁剪 dsh 依赖包：删掉运行时用不到的文档/类型/测试/源码映射，显著缩小 IPA。
只删确定安全的内容；删完由 CI 做冒烟测试兜底。"""
import os
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "resources/dsh/node_modules"

# 只删「确定不是运行时代码」的目录：泛化名字（doc/docs/test）可能是真实模块，
# 上一版就踩了 ../doc/directives.js 被误删导致 dsh 起不来。
DROP_DIRS = {"__tests__", "__mocks__", ".github", "coverage", ".nyc_output"}
DROP_EXT = {".map", ".md", ".markdown", ".flow", ".coffee",
            ".d.ts.map", ".tgz", ".zip"}

removed = 0
freed = 0

for base, dirs, files in os.walk(ROOT, topdown=True):
    # 不进入嵌套的 node_modules（npm 的扁平化已足够）
    if base != ROOT and "node_modules" in base[len(ROOT):].split(os.sep):
        dirs[:] = []
        continue
    keep = []
    for d in dirs:
        if d in DROP_DIRS:
            p = os.path.join(base, d)
            for r, _, fs in os.walk(p):
                for f in fs:
                    try:
                        freed += os.path.getsize(os.path.join(r, f))
                    except OSError:
                        pass
            import shutil
            shutil.rmtree(p, ignore_errors=True)
            removed += 1
        else:
            keep.append(d)
    dirs[:] = keep
    for f in files:
        ext = os.path.splitext(f)[1].lower()
        drop = ext in DROP_EXT
        # 保留许可证与 package.json
        if f.upper().startswith(("LICENSE", "LICENCE", "NOTICE", "COPYING")):
            drop = False
        if f.endswith(".d.ts"):
            drop = True
        if drop:
            p = os.path.join(base, f)
            try:
                freed += os.path.getsize(p)
                os.remove(p)
            except OSError:
                pass

print(f"prune: removed {removed} dirs, freed {freed/1024/1024:.1f} MB")
