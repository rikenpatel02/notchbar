"""Draws the "If NotchBar won't open" guide shipped inside the DMG, plus the large icon
Finder shows for it (a shrunken preview of the guide would be unreadable).

Releases that aren't notarized are blocked by macOS on first open; this walks users
through the three screens they will see. Requires Pillow.
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = "/System/Library/Fonts/SFNS.ttf"
W, H = 1800, 1000

INK = (28, 28, 36)
MUTED = (100, 102, 116)
ACCENT = (217, 119, 87)
BLUE = (10, 122, 255)
PANEL = (236, 236, 236)
WEIGHTS = {"Regular": 400, "Medium": 510, "Semibold": 590, "Bold": 700}


def font(size, weight="Regular"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([100, min(max(size / 2, 17), 96), 400, WEIGHTS[weight]])
    return f


def centered(d, xy, text, f, fill):
    d.text(xy, text, font=f, fill=fill, anchor="mm")


def shadowed_card(canvas, box, radius, fill=(255, 255, 255)):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((box[0], box[1] + 14, box[2], box[3] + 14), radius, fill=(30, 20, 60, 60))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(22)))
    ImageDraw.Draw(canvas).rounded_rectangle(box, radius, fill=fill, outline=(222, 222, 230), width=2)


def highlight(d, box, radius):
    d.rounded_rectangle((box[0] - 8, box[1] - 8, box[2] + 8, box[3] + 8), radius + 8, outline=ACCENT, width=6)


def button(d, box, label, primary=False):
    d.rounded_rectangle(box, 14, fill=BLUE if primary else (226, 226, 230))
    centered(d, ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2), label, font(26, "Medium"), (255, 255, 255) if primary else INK)


def step_badge(d, cx, cy, n):
    d.ellipse((cx - 26, cy - 26, cx + 26, cy + 26), fill=ACCENT)
    centered(d, (cx, cy), str(n), font(30, "Bold"), (255, 255, 255))


def app_icon(size):
    icon = Image.open(os.path.join(ROOT, "docs", "images", "icon.png")).convert("RGBA")
    return icon.resize((size, size), Image.LANCZOS)


def main():
    canvas = Image.new("RGBA", (W, H), (246, 245, 251, 255))
    d = ImageDraw.Draw(canvas)
    canvas.alpha_composite(app_icon(96), (90, 60))
    d.text((210, 88), "How to open NotchBar", font=font(54, "Bold"), fill=INK, anchor="lm")
    d.text((210, 138), "macOS blocks the first open of apps that aren't notarized by Apple yet. Allow it once:",
           font=font(28), fill=MUTED, anchor="lm")

    cards = [(90, 220, 620, 885), (635, 220, 1165, 885), (1180, 220, 1710, 885)]
    for box in cards:
        shadowed_card(canvas, box, 28)
    d = ImageDraw.Draw(canvas)

    # 1. The warning dialog.
    x0, y0, x1, _ = cards[0]
    cx = (x0 + x1) / 2
    dialog = (x0 + 50, y0 + 50, x1 - 50, y0 + 450)
    d.rounded_rectangle(dialog, 24, fill=PANEL)
    canvas.alpha_composite(app_icon(68), (int(cx - 34), dialog[1] + 22))
    d = ImageDraw.Draw(canvas)
    centered(d, (cx, dialog[1] + 118), "“NotchBar” Not Opened", font(28, "Bold"), INK)
    for i, line in enumerate(["Apple could not verify “NotchBar”", "is free of malware that may harm", "your Mac or compromise your privacy."]):
        centered(d, (cx, dialog[1] + 158 + i * 30), line, font(21), MUTED)
    done = (dialog[0] + 30, dialog[1] + 260, dialog[2] - 30, dialog[1] + 302)
    trash = (dialog[0] + 30, dialog[1] + 322, dialog[2] - 30, dialog[1] + 364)
    button(d, done, "Done", primary=True)
    button(d, trash, "Move to Trash")
    highlight(d, done, 14)
    step_badge(d, x0 + 70, y0 + 520, 1)
    d.text((x0 + 112, y0 + 520), "Click Done", font=font(32, "Bold"), fill=INK, anchor="lm")
    d.text((x0 + 70, y0 + 575), "Not Move to Trash.", font=font(26), fill=MUTED, anchor="lm")

    # 2. System Settings sidebar.
    x0, y0, x1, _ = cards[1]
    side = (x0 + 50, y0 + 50, x1 - 50, y0 + 450)
    d.rounded_rectangle(side, 24, fill=PANEL)
    items = [("General", (142, 142, 147)), ("Appearance", (60, 60, 67)), ("Control Center", (142, 142, 147)),
             ("Privacy & Security", BLUE), ("Desktop & Dock", (60, 60, 67)), ("Displays", BLUE)]
    for i, (label, color) in enumerate(items):
        top = side[1] + 34 + i * 60
        row = (side[0] + 20, top, side[2] - 20, top + 48)
        selected = label == "Privacy & Security"
        if selected:
            d.rounded_rectangle(row, 12, fill=BLUE)
        d.rounded_rectangle((row[0] + 14, top + 9, row[0] + 44, top + 39), 8, fill=(255, 255, 255) if selected else color)
        d.text((row[0] + 62, top + 24), label, font=font(25, "Semibold" if selected else "Regular"),
               fill=(255, 255, 255) if selected else INK, anchor="lm")
        if selected:
            highlight(d, row, 12)
    step_badge(d, x0 + 70, y0 + 520, 2)
    d.text((x0 + 112, y0 + 520), "Privacy & Security", font=font(32, "Bold"), fill=INK, anchor="lm")
    d.text((x0 + 70, y0 + 575), "Open System Settings, choose", font=font(26), fill=MUTED, anchor="lm")
    d.text((x0 + 70, y0 + 610), "Privacy & Security, scroll down.", font=font(26), fill=MUTED, anchor="lm")

    # 3. The Security section with Open Anyway.
    x0, y0, x1, _ = cards[2]
    sec = (x0 + 50, y0 + 50, x1 - 50, y0 + 450)
    d.rounded_rectangle(sec, 24, fill=PANEL)
    d.text((sec[0] + 30, sec[1] + 50), "Security", font=font(28, "Bold"), fill=INK, anchor="lm")
    box = (sec[0] + 24, sec[1] + 90, sec[2] - 24, sec[1] + 330)
    d.rounded_rectangle(box, 16, fill=(255, 255, 255))
    for i, line in enumerate(["“NotchBar” was blocked to", "protect your Mac."]):
        d.text((box[0] + 26, box[1] + 50 + i * 34), line, font=font(24), fill=INK, anchor="lm")
    anyway = (box[2] - 210, box[3] - 80, box[2] - 26, box[3] - 32)
    button(d, anyway, "Open Anyway")
    highlight(d, anyway, 14)
    step_badge(d, x0 + 70, y0 + 520, 3)
    d.text((x0 + 112, y0 + 520), "Click Open Anyway", font=font(32, "Bold"), fill=INK, anchor="lm")
    d.text((x0 + 70, y0 + 575), "Confirm with your password.", font=font(26), fill=MUTED, anchor="lm")
    d.text((x0 + 70, y0 + 610), "NotchBar then opens.", font=font(26), fill=MUTED, anchor="lm")

    d.text((W / 2, 948), "You only do this once for each new version.  Questions: github.com/rikenpatel02/notchbar",
           font=font(24), fill=MUTED, anchor="mm")

    canvas.convert("RGB").save(os.path.join(ROOT, "Resources", "open-guide.png"), dpi=(120, 120), optimize=True)
    guide_icon().save(os.path.join(ROOT, "Resources", "open-guide-icon.png"))
    print("Wrote Resources/open-guide.png and Resources/open-guide-icon.png")


def guide_icon():
    """A bold question-mark tile that stays legible at Finder icon sizes."""
    size = 1024
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((110, 130, 914, 934), 190, fill=(60, 30, 20, 90))
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(icon)
    d.rounded_rectangle((100, 100, 924, 924), 190, fill=ACCENT)
    centered(d, (512, 470), "?", font(560, "Bold"), (255, 255, 255))
    centered(d, (512, 790), "HOW TO OPEN", font(96, "Bold"), (255, 255, 255))
    return icon


if __name__ == "__main__":
    main()
