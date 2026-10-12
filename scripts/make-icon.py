"""Draws Resources/AppIcon.icns: a gradient squircle with the island and Claude's spark.

Requires Pillow (pip install pillow) and macOS iconutil.
"""
import math
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 2048  # drawn at 2x the 1024 master, then downsampled


def gradient(size, top, bottom):
    img = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        img.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img.resize(size, Image.BICUBIC)


def spark(draw, cx, cy, r, fill):
    points = []
    for i in range(8):
        angle = math.pi / 2 + i * math.pi / 4
        radius = r if i % 2 == 0 else r * 0.28
        points.append((cx + radius * math.cos(angle), cy - radius * math.sin(angle)))
    draw.polygon(points, fill=fill)


def master():
    margin, radius = int(S * 0.098), int(S * 0.185)
    box = (margin, margin, S - margin, S - margin)
    side = box[2] - box[0]

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)

    body = gradient((side, side), (30, 30, 70), (16, 16, 34)).convert("RGBA")
    glow = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-side * 0.35, side * 0.5, side * 0.75, side * 1.5), fill=(124, 72, 210, 210))
    ImageDraw.Draw(glow).ellipse((side * 0.4, side * 0.6, side * 1.4, side * 1.55), fill=(226, 120, 86, 190))
    ImageDraw.Draw(glow).ellipse((side * 0.55, -side * 0.4, side * 1.4, side * 0.35), fill=(60, 90, 200, 120))
    body.alpha_composite(glow.filter(ImageFilter.GaussianBlur(side * 0.12)))

    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(body, box[:2])
    icon.putalpha(mask)

    # Menu bar hairline (clipped to the squircle) and the island dropping below it.
    line = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(line).rectangle((box[0], margin + side * 0.2, box[2], margin + side * 0.2 + S * 0.003), fill=(255, 255, 255, 60))
    line.putalpha(Image.composite(line.split()[3], Image.new("L", (S, S), 0), mask))
    icon.alpha_composite(line)
    pill_w, pill_h = side * 0.62, side * 0.25
    px, py = S / 2 - pill_w / 2, margin + side * 0.29
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((px, py + S * 0.03, px + pill_w, py + pill_h + S * 0.03), pill_h / 2, fill=(0, 0, 0, 170))
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.03)))
    d = ImageDraw.Draw(icon)
    d.rounded_rectangle((px, py, px + pill_w, py + pill_h), pill_h / 2, fill=(0, 0, 0, 255))
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((px, py, px + pill_w, py + pill_h), pill_h / 2, outline=(255, 255, 255, 40), width=int(S * 0.004))
    icon.alpha_composite(edge)

    cy = py + pill_h / 2
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse((px + pill_h * 0.5 - S * 0.07, cy - S * 0.07, px + pill_h * 0.5 + S * 0.07, cy + S * 0.07), fill=(217, 119, 87, 110))
    icon.alpha_composite(halo.filter(ImageFilter.GaussianBlur(S * 0.03)))
    d = ImageDraw.Draw(icon)
    spark(d, px + pill_h * 0.5, cy, pill_h * 0.33, (217, 119, 87, 255))
    # Status dot and a short "activity" bar.
    d.ellipse((px + pill_w - pill_h * 0.62, cy - S * 0.022, px + pill_w - pill_h * 0.62 + S * 0.044, cy + S * 0.022), fill=(80, 210, 110, 255))
    d.rounded_rectangle((px + pill_h * 0.95, cy - S * 0.018, px + pill_w * 0.62, cy + S * 0.018), S * 0.018, fill=(255, 255, 255, 215))
    return icon.resize((1024, 1024), Image.LANCZOS)


def main():
    art = master()
    iconset = tempfile.mkdtemp(suffix=".iconset")
    try:
        for size in (16, 32, 128, 256, 512):
            art.resize((size, size), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}.png")
            art.resize((size * 2, size * 2), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}@2x.png")
        os.makedirs(f"{ROOT}/Resources", exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", f"{ROOT}/Resources/AppIcon.icns"], check=True)
        art.save(f"{ROOT}/docs/images/icon.png")
    finally:
        shutil.rmtree(iconset)
    print("Wrote Resources/AppIcon.icns and docs/images/icon.png")


if __name__ == "__main__":
    main()
