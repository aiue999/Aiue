# Generates the app icon (1024x1024 PNG) during CI.
from PIL import Image, ImageDraw
S = 1024
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=(int(30 + 20 * t), int(120 - 40 * t), int(240 - 60 * t)))
cx, cy, r = 512, 420, 230
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255))
d.polygon([(cx - 200, cy + 115), (cx + 200, cy + 115), (cx, cy + 430)], fill=(255, 255, 255))
d.ellipse([cx - 95, cy - 95, cx + 95, cy + 95], fill=(230, 60, 60))
img.save("PitaLoc/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
