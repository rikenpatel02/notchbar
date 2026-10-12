# dmgbuild settings for the install window: NotchBar beside an Applications shortcut, and
# an illustrated "How to open NotchBar" guide for builds macOS blocks on first open.
# Run through scripts/release.sh, which passes -D app=<path to NotchBar.app>.
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
root = os.path.dirname(os.path.dirname(os.path.abspath(app)))

format = "UDZO"
filesystem = "HFS+"
guide = os.path.join(root, "Resources", "How to open NotchBar.png")
files = [app, guide]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(root, "Resources", "AppIcon.icns")

window_rect = ((200, 120), (640, 470))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
show_icon_preview = True
text_size = 13
icon_locations = {
    "NotchBar.app": (160, 135),
    "Applications": (480, 135),
    "How to open NotchBar.png": (320, 315),
}
