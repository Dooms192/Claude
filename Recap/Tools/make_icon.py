# Draws the Recap app icon (light, dark, and tinted) at 1024x1024.
# Usage: python3 Tools/make_icon.py Recap/Assets.xcassets/AppIcon.appiconset
# Needs Pillow (pip install pillow). Edit the shapes or colors below and run it again.
import math, sys
from PIL import Image, ImageDraw, ImageFilter

S = 4096          # draw large, then shrink for smooth edges
K = S / 1024      # scale from 1024-point design coordinates

def p(v): return int(round(v * K))

def gradient(top_left, bottom_right):
    img = Image.new("RGB", (S, S))
    px = img.load()
    small = Image.new("RGB", (256, 256))
    sp = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            sp[x, y] = tuple(int(a + (b - a) * t) for a, b in zip(top_left, bottom_right))
    return small.resize((S, S), Image.BICUBIC)

def glow(img, center, radius, color, alpha):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([p(cx - radius), p(cy - radius), p(cx + radius), p(cy + radius)], fill=color + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(p(radius * 0.6)))
    return Image.alpha_composite(img.convert("RGBA"), layer)

def round_arc(d, center, r, start, end, width, fill):
    cx, cy = center
    box = [p(cx - r), p(cy - r), p(cx + r), p(cy + r)]
    d.arc(box, start, end, fill=fill, width=p(width))
    for ang in (start, end):
        a = math.radians(ang)
        ex = cx + (r - width / 2) * math.cos(a)
        ey = cy + (r - width / 2) * math.sin(a)
        d.ellipse([p(ex - width / 2), p(ey - width / 2), p(ex + width / 2), p(ey + width / 2)], fill=fill)

def sparkle(d, center, size, fill):
    cx, cy = center
    pts = []
    for i in range(8):
        ang = math.radians(i * 45 - 90)
        r = size if i % 2 == 0 else size * 0.28
        pts.append((p(cx + r * math.cos(ang)), p(cy + r * math.sin(ang))))
    d.polygon(pts, fill=fill)

def draw_symbol(img, mic, wave_near, wave_far, star):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # Microphone head
    d.rounded_rectangle([p(422), p(250), p(602), p(560)], radius=p(90), fill=mic)
    # Holder: a U around the lower half of the head
    round_arc(d, (512, 450), 172, 0, 180, 44, mic)
    for x in (340 + 22, 684 - 22):
        d.rounded_rectangle([p(x - 22), p(400), p(x + 22), p(470)], radius=p(22), fill=mic)
    # Stem and base
    d.rounded_rectangle([p(490), p(616), p(534), p(740)], radius=p(10), fill=mic)
    d.rounded_rectangle([p(404), p(722), p(620), p(768)], radius=p(23), fill=mic)
    # Sound waves on both sides
    for start, end in ((-38, 38), (142, 218)):
        round_arc(d, (512, 405), 262, start, end, 36, wave_near)
        round_arc(d, (512, 405), 340, start + 8, end - 8, 36, wave_far)
    # Move the microphone and waves down a little so the whole mark sits centered.
    shifted = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shifted.paste(layer, (0, p(40)))
    layer = shifted
    # The "AI" sparkle, in the open top-right corner, clear of the sound waves
    if star:
        d = ImageDraw.Draw(layer)
        sparkle(d, (820, 175), 60, star)
        sparkle(d, (895, 265), 28, star)
    return Image.alpha_composite(img.convert("RGBA"), layer)

def finish(img, path):
    img.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(path, optimize=True)

out = sys.argv[1]

# Light (default): indigo gradient, white microphone, warm sparkle
img = gradient((128, 112, 255), (66, 48, 186))
img = glow(img, (330, 220), 380, (255, 255, 255), 60)
img = draw_symbol(img, (255, 255, 255, 255), (255, 255, 255, 220), (255, 255, 255, 130), (255, 214, 102, 255))
finish(img, f"{out}/AppIcon.png")

# Dark: near-black background, indigo-tinted microphone
img = gradient((34, 32, 52), (12, 12, 20))
img = glow(img, (512, 470), 360, (110, 100, 255), 55)
img = draw_symbol(img, (178, 168, 255, 255), (150, 140, 255, 220), (150, 140, 255, 130), (255, 214, 102, 255))
finish(img, f"{out}/AppIcon-Dark.png")

# Tinted: grayscale on black; iOS applies the user's tint color
img = Image.new("RGB", (S, S), (0, 0, 0))
img = draw_symbol(img, (255, 255, 255, 255), (230, 230, 230, 255), (150, 150, 150, 255), (255, 255, 255, 255))
finish(img, f"{out}/AppIcon-Tinted.png")
print("done")
