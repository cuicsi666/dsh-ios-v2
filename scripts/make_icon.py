#!/usr/bin/env python3
"""生成 1024x1024 App 图标（无外部素材依赖）。"""
import sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "DashHarness/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
S = 1024

img = Image.new("RGB", (S, S), "#1B2A6B")
d = ImageDraw.Draw(img)

# 背景对角渐变
c1 = (24, 34, 92)
c2 = (76, 100, 255)
for y in range(S):
    t = y / (S - 1)
    # 叠加水平渐变，做斜向效果
    row = Image.new("RGB", (S, 1))
    rd = ImageDraw.Draw(row)
    for x in range(0, S, 8):
        u = (x / (S - 1)) * 0.6 + t * 0.4
        col = tuple(int(c1[i] + (c2[i] - c1[i]) * u) for i in range(3))
        rd.rectangle([x, 0, x + 7, 0], fill=col)
    img.paste(row, (0, y))
d = ImageDraw.Draw(img)

# 柔光圆
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([S*0.08, -S*0.28, S*0.92, S*0.56], fill=(255, 255, 255, 26))
img = Image.alpha_composite(img.convert("RGBA"), glow)
d = ImageDraw.Draw(img)

# 对话气泡
bx0, by0, bx1, by1 = S*0.16, S*0.22, S*0.84, S*0.70
d.rounded_rectangle([bx0, by0, bx1, by1], radius=S*0.11, fill=(255, 255, 255, 255))
# 气泡尾巴
d.polygon([(S*0.33, S*0.69), (S*0.33, S*0.82), (S*0.47, S*0.69)], fill=(255, 255, 255, 255))

# 终端符号 >_
def font(size):
    for p in ["/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
              "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
              "/usr/share/fonts/ttf-dejavu/DejaVuSans-Bold.ttf"]:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()

f = font(int(S*0.30))
text = ">_"
tb = d.textbbox((0, 0), text, font=f)
tw, th = tb[2]-tb[0], tb[3]-tb[1]
d.text(((S-tw)/2 - tb[0], (S*0.46)-th/2 - tb[1]), text, font=f, fill=(27, 42, 107, 255))

# 右下亮点
d.ellipse([S*0.70, S*0.74, S*0.86, S*0.90], fill=(255, 176, 32, 255))
d.ellipse([S*0.745, S*0.785, S*0.815, S*0.855], fill=(255, 245, 220, 255))

img.convert("RGB").save(OUT, "PNG")
print("wrote", OUT, img.size)
