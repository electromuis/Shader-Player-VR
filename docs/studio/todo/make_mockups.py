"""The 'after' mockups for the Studio to-do list (VR Studio — Plan.md, *To do*).

Same look as the design mockups in docs/studio/*.svg. Writes one SVG per
group next to this file:  python make_mockups.py
"""
import math
import os

BG = "#0b0d12"
PANEL = "#161a23"
LINE = "#2c3344"
FIELD = "#0f1219"
TEXT = "#e8ebf2"
DIM = "#8c95a8"
ACCENT = "#4cc9f0"
RED = "#ff4d5e"
GREEN = "#5ee08a"
AMBER = "#f0b44c"
PURPLE = "#b15cff"
FONT = "Inter, Segoe UI, Helvetica, Arial, sans-serif"

DEFS = """<defs>
<filter id='shadow' x='-10%' y='-10%' width='130%' height='140%'><feDropShadow dx='0' dy='8' stdDeviation='10' flood-color='#000' flood-opacity='0.55'/></filter>
<linearGradient id='vid' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#ff7a59'/><stop offset='0.5' stop-color='#b83b7a'/><stop offset='1' stop-color='#2b2d7a'/></linearGradient>
<linearGradient id='vid2' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#3ad1c4'/><stop offset='1' stop-color='#2b2d7a'/></linearGradient>
<linearGradient id='vid3' x1='0' y1='1' x2='1' y2='0'><stop offset='0' stop-color='#ffcf4d'/><stop offset='1' stop-color='#d0386b'/></linearGradient>
<linearGradient id='env' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#05060a'/><stop offset='0.55' stop-color='#0d1320'/><stop offset='1' stop-color='#141b2a'/></linearGradient>
<radialGradient id='tunnel' cx='0.5' cy='0.5' r='0.5'><stop offset='0' stop-color='#000'/><stop offset='0.35' stop-color='#2b2d7a'/><stop offset='0.6' stop-color='#b15cff'/><stop offset='0.8' stop-color='#4cc9f0'/><stop offset='1' stop-color='#05060a'/></radialGradient>
<pattern id='hatch' width='8' height='8' patternUnits='userSpaceOnUse' patternTransform='rotate(45)'><rect width='4' height='8' fill='#ffffff' fill-opacity='0.08'/></pattern>
</defs>"""


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class Svg:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.parts = []

    def add(self, s):
        self.parts.append(s)

    def rect(self, x, y, w, h, fill=FIELD, stroke=None, rx=8, sw=1, extra=""):
        st = f" stroke='{stroke}' stroke-width='{sw}'" if stroke else ""
        self.add(f"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='{rx}' fill='{fill}'{st} {extra}/>")

    def text(self, x, y, s, color=TEXT, size=14, anchor="start", weight=400, extra=""):
        self.add(f"<text x='{x}' y='{y}' fill='{color}' font-size='{size}' text-anchor='{anchor}' font-weight='{weight}' {extra}>{esc(s)}</text>")

    def line(self, x1, y1, x2, y2, color=LINE, w=1, extra=""):
        self.add(f"<line x1='{x1}' y1='{y1}' x2='{x2}' y2='{y2}' stroke='{color}' stroke-width='{w}' {extra}/>")

    def panel(self, x, y, w, h, title=None, chrome=True):
        self.add(f"<g filter='url(#shadow)'><rect x='{x}' y='{y}' width='{w}' height='{h}' rx='16' fill='{PANEL}' fill-opacity='0.95' stroke='{LINE}'/></g>")
        if title:
            self.text(x + 22, y + 36, title, TEXT, 18, weight=700)
            if chrome:
                self.panel_chrome(x + w - 22, y + 18)

    def panel_chrome(self, right, top):
        """Minimize and close buttons at a panel's top right."""
        for i, glyph in enumerate(["×", "–"]):
            bx = right - 30 - i * 36
            self.rect(bx, top, 30, 26, FIELD, LINE, 6)
            self.text(bx + 15, top + 19, glyph, DIM, 16, "middle", 700)

    def diamond(self, cx, cy, kind="key", r=7):
        pts = f"{cx},{cy - r} {cx + r},{cy} {cx},{cy + r} {cx - r},{cy}"
        if kind == "key":
            self.add(f"<polygon points='{pts}' fill='{ACCENT}'/>")
        elif kind == "anim":
            self.add(f"<polygon points='{pts}' fill='none' stroke='{ACCENT}' stroke-width='2'/>")
        else:
            self.add(f"<circle cx='{cx}' cy='{cy}' r='2.5' fill='{DIM}'/>")

    def switch(self, x, y, on=True):
        self.rect(x, y, 40, 22, ACCENT if on else "#3a4254", None, 11)
        self.add(f"<circle cx='{x + (29 if on else 11)}' cy='{y + 11}' r='8' fill='{TEXT}'/>")

    def slider(self, x, y, w, frac, color=ACCENT):
        self.rect(x, y - 3, w, 6, "#262c3a", None, 3)
        self.rect(x, y - 3, w * frac, 6, color, None, 3)
        self.add(f"<circle cx='{x + w * frac}' cy='{y}' r='9' fill='{TEXT}'/>")

    def reset(self, x, y):
        """The player's reset button after a setting line."""
        self.rect(x, y, 26, 24, FIELD, LINE, 6)
        self.text(x + 13, y + 17, "↺", DIM, 15, "middle", 700)

    def button(self, x, y, w, h, label, active=False, color=ACCENT, size=13, dashed=False, fill=None):
        extra = "stroke-dasharray='5 4'" if dashed else ""
        self.rect(x, y, w, h, fill or ("#1f2a3a" if active else "#1c212c"), color if (active or dashed) else LINE, 8, 2 if active or dashed else 1, extra)
        self.text(x + w / 2, y + h / 2 + size * 0.36, label, TEXT if active else (color if dashed else DIM), size, "middle", 700 if active or dashed else 500)

    def check(self, x, y, on=True, label=""):
        self.rect(x, y, 18, 18, ACCENT if on else FIELD, ACCENT, 4, 2)
        if on:
            self.add(f"<polyline points='{x + 4},{y + 9} {x + 8},{y + 13} {x + 14},{y + 5}' fill='none' stroke='{BG}' stroke-width='2.5'/>")
        if label:
            self.text(x + 26, y + 14, label, TEXT, 13)

    def new_badge(self, x, y, label="NEW"):
        w = 8 + len(label) * 7
        self.rect(x, y, w, 18, "#3b2a10", AMBER, 9)
        self.text(x + w / 2, y + 13, label, AMBER, 10, "middle", 800)

    def svg(self):
        return (f"<svg xmlns='http://www.w3.org/2000/svg' width='{self.w}' height='{self.h}' viewBox='0 0 {self.w} {self.h}' font-family='{FONT}'>"
                + DEFS + f"<rect width='{self.w}' height='{self.h}' fill='{BG}'/>" + "".join(self.parts) + "</svg>")


def save(name, s):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s.svg())
    print("wrote", path)


# ---------------------------------------------------------------- 1. menu
def menu():
    s = Svg(900, 700)
    s.panel(20, 20, 860, 600, None)
    s.text(44, 58, "Studio menu", TEXT, 20, weight=700)
    s.text(172, 58, "F2 · ≡ on either controller", DIM, 13)
    s.panel_chrome(858, 36)
    tabs = ["Config", "Controls", "Studio", "Camera"]
    x = 44
    for i, t in enumerate(tabs):
        w = 20 + len(t) * 9
        s.button(x, 76, w, 32, t, i == 0)
        x += w + 8
    s.line(44, 122, 836, 122)
    rows = [
        ("UI scale", "dropdown", "125 %", True),
        ("FPS", "switch", "Show frames per second", False),
        ("Skybox", "dropdown", "Night gradient", True),
        ("Floor", "switch", "Show floor", False),
        ("Camera effects", "switch", "Allow full-view effects", False),
        ("Effects at most", "slider", 0.8, True),
        ("Volume", "slider", 0.65, True),
        ("Video decoder", "dropdown", "FFmpeg — every format, network streams", False),
        ("Renderer", "dropdown", "Direct3D 12", False),
    ]
    y = 140
    for label, kind, val, changed in rows:
        s.text(44, y + 22, label, TEXT, 15)
        if kind == "dropdown":
            s.rect(250, y + 2, 520, 32, "#1c212c", LINE, 8)
            s.text(264, y + 23, val, TEXT, 14)
            s.text(756, y + 23, "▾", DIM, 14, "end")
        elif kind == "switch":
            s.switch(250, y + 7, label in ("FPS", "Camera effects"))
            s.text(302, y + 23, val, DIM, 14)
        else:
            s.slider(262, y + 18, 440, val)
            s.text(770, y + 23, f"{round(val * 100)} %", DIM, 14, "end")
        if changed:
            s.reset(790, y + 6)
        y += 46
    s.line(44, y + 6, 836, y + 6)
    s.text(44, y + 34, "↺ puts a setting back to its default (as in the player). These settings are shared with the player.", DIM, 13)
    s.text(44, y + 56, "Controls: remap Studio's keys and buttons, Left-handed.  Studio: auto-key mode, haptics, autosave, grid.", DIM, 13)
    # FPS readout in the corner of the desktop window
    s.rect(20, 640, 96, 30, "#10141c", LINE, 6)
    s.text(68, 660, "72 fps", GREEN, 13, "middle", 700)
    s.text(128, 660, "FPS on: the readout in the desktop window's corner (and on the wrist in the headset)", DIM, 13)
    return s


# ------------------------------------------------------------ 2. inspector
def inspector():
    s = Svg(560, 1250)
    s.panel(20, 20, 520, 1210, None)
    s.text(42, 58, "main_screen", TEXT, 22, weight=700)
    s.text(42, 80, "Screen · in screen_split · 00:00 → 55.00", DIM, 13)
    s.panel_chrome(518, 34)
    s.diamond(360, 104, "key", 5); s.text(370, 108, "key here", DIM, 11)
    s.diamond(430, 104, "anim", 5); s.text(440, 108, "animated", DIM, 11)
    s.line(42, 118, 518, 118)

    y = 144
    s.text(42, y, "▾ Transform", TEXT, 15, weight=700)
    # position: number fields
    y += 16
    def xyz(y, label, vals, kind, active=False):
        s.text(42, y + 22, label, TEXT if not active else ACCENT, 14, weight=600 if active else 400)
        for i, (ax, v) in enumerate(zip("xyz", vals)):
            bx = 132 + i * 114
            s.rect(bx, y, 106, 32, FIELD, ACCENT if active else LINE, 8, 2 if active else 1)
            s.text(bx + 10, y + 21, ax, ACCENT, 13, weight=700)
            s.text(bx + 96, y + 21, v, TEXT, 14, "end")
        s.diamond(490, y + 16, kind)
    xyz(y, "Position", ["-2.00", "1.70", "0.00"], "key")
    y += 42
    xyz(y, "Rotation", ["0", "35", "0"], "anim", True)
    y += 40
    # folded-out sliders for rotation
    s.rect(42, y, 476, 118, "#121620", LINE, 10)
    for i, (ax, frac, val) in enumerate([("x", 0.5, "0°"), ("y", 0.6, "35°"), ("z", 0.5, "0°")]):
        yy = y + 24 + i * 36
        s.text(58, yy + 5, ax, ACCENT, 13, weight=700)
        s.slider(84, yy, 330, frac)
        s.text(470, yy + 5, val, DIM, 13, "end")
        s.reset(480, yy - 12)
    y += 128
    xyz(y, "Scale", ["0.12", "0.12", "0.12"], "dot")
    y += 40
    s.check(132, y, True, "Uniform (one value for x, y and z)")
    y += 32
    s.text(42, y, "Click a row for its sliders · type a number · grab to move", DIM, 12)
    y += 14
    s.line(42, y, 518, y)

    y += 26
    s.text(42, y, "▾ Display", TEXT, 15, weight=700)
    y += 14
    s.text(42, y + 22, "Surface", TEXT, 14)
    s.rect(160, y + 2, 290, 32, "#1c212c", LINE, 8)
    s.text(174, y + 23, "Pillow (curved both ways)", TEXT, 14)
    s.text(438, y + 23, "▾", DIM, 14, "end")
    s.reset(458, y + 6); s.diamond(500, y + 18, "dot")
    y += 42
    for label, frac, val, kind, ch in [("Arc across", 0.55, "70°", "dot", True), ("Arc up", 0.2, "20°", "dot", True), ("Opacity", 1.0, "1.00", "anim", False)]:
        s.text(42, y + 20, label, TEXT, 14)
        s.slider(160, y + 16, 240, frac)
        s.text(446, y + 21, val, DIM, 13, "end")
        if ch:
            s.reset(458, y + 4)
        s.diamond(500, y + 16, kind)
        y += 38
    s.line(42, y, 518, y)

    y += 26
    s.text(42, y, "▾ Shader · wobble", TEXT, 15, weight=700)
    y += 12
    s.text(42, y + 20, "amount", TEXT, 14); s.slider(160, y + 16, 240, 0.3); s.text(446, y + 21, "0.30", DIM, 13, "end"); s.reset(458, y + 4); s.diamond(500, y + 16, "anim")
    y += 36
    s.line(42, y, 518, y)

    def stack(y, title, items, add_label, master_on=True):
        s.text(42, y, "▾ " + title, TEXT, 15, weight=700)
        s.switch(430, y - 16, master_on)
        s.text(422, y, "all", DIM, 12, "end")
        s.new_badge(200 if title.startswith("Pixel") else 212, y - 13, "MASTER SWITCH")
        y += 12
        for name, on, kind, sel, detail in items:
            h = 38 if not sel else 84
            s.rect(42, y, 476, h, "#1f2a3a" if sel else FIELD, ACCENT if sel else LINE, 10, 1.5 if sel else 1)
            for k in range(3):
                s.line(54, y + 14 + k * 5, 68, y + 14 + k * 5, DIM, 2)
            s.text(80, y + 24, name, TEXT if on else DIM, 14, weight=600)
            s.switch(398, y + 8, on)
            s.diamond(456, y + 19, kind)
            s.text(492, y + 24, "×", DIM, 16, "middle", 700)
            if sel:
                s.text(80, y + 62, detail[0], DIM, 13)
                s.slider(170, y + 58, 220, detail[1])
                s.text(440, y + 63, detail[2], DIM, 12, "end")
            y += h + 6
        s.button(42, y, 170, 32, add_label, dashed=True)
        return y + 48

    y += 26
    y = stack(y, "Pixel effects", [
        ("Padding (auto)", True, "dot", False, None),
        ("Glow", True, "anim", True, ("intensity", 0.6, "0.60")),
        ("Oval mask", False, "dot", False, None),
    ], "+ Add effect")
    s.line(42, y - 8, 518, y - 8)
    y += 18
    y = stack(y, "Vertex effects", [
        ("Ripple · follows the bass", True, "key", False, None),
        ("Twist", True, "dot", False, None),
    ], "+ Add vertex effect")
    s.line(42, y - 8, 518, y - 8)
    y += 18
    s.text(42, y, "▸ Modifiers", TEXT, 15, weight=700)
    s.text(518, y, "tint · flash · speed", DIM, 12, "end")
    y += 24
    s.text(42, y, "Reactive is gone: spin and pulse are vertex effects that follow the music.", DIM, 12)
    return s


# ----------------------------------------------------- 3. wrist and panels
def wrist():
    s = Svg(1180, 900)

    def page(ox, title, cells, footer, dots):
        s.panel(ox, 20, 540, 440, None)
        # play / edit switch
        s.rect(ox + 22, 42, 200, 40, FIELD, LINE, 20)
        s.rect(ox + 122, 45, 97, 34, ACCENT, None, 17)
        s.text(ox + 72, 68, "Play", DIM, 15, "middle", 700)
        s.text(ox + 170, 68, "Edit", BG, 15, "middle", 800)
        s.text(ox + 518, 72, "01:23.40", TEXT, 30, "end", 800)
        s.text(ox + 518, 92, "of 03:05.00 · bar 42.3", DIM, 12, "end")
        y = 110
        for r, row in enumerate(cells):
            for c, (icon, label, state) in enumerate(row):
                x = ox + 22 + c * 126
                col = RED if state == "red" else ACCENT
                act = state in ("on", "red")
                s.rect(x, y, 116, 80, "#233044" if act else "#1c212c", col if act else LINE, 10, 2 if act else 1)
                s.text(x + 58, y + 36, icon, col if act or state == "new" else TEXT, 22, "middle", 700)
                s.text(x + 58, y + 64, label, TEXT if act else DIM, 13, "middle", 700 if act else 500)
                if state == "new":
                    s.new_badge(x + 72, y + 6)
            y += 90
        s.line(ox + 22, y + 2, ox + 518, y + 2)
        footer(ox, y + 14)
        for i in range(2):
            s.add(f"<circle cx='{ox + 262 + i * 16}' cy='{448}' r='4' fill='{ACCENT if i == dots else '#3a4254'}'/>")
        s.text(ox + 270, 492, title, DIM, 13, "middle")

    def footer_main(ox, y):
        s.rect(ox + 22, y, 200, 42, "#1c212c", LINE, 8)
        s.text(ox + 44, y + 27, "💾", TEXT, 15)
        s.text(ox + 70, y + 27, "Save", TEXT, 15, weight=700)
        s.text(ox + 118, y + 27, "autosaved 12 s ago", DIM, 11)
        s.add(f"<circle cx='{ox + 250}' cy='{y + 22}' r='5' fill='{RED}'/>")
        s.text(ox + 262, y + 27, "Auto-key on: drags write keys", DIM, 13)

    def footer_more(ox, y):
        s.add(f"<circle cx='{ox + 32}' cy='{y + 22}' r='5' fill='{RED}'/>")
        s.text(ox + 44, y + 19, "Ride armed: the next take (● Record) also records", DIM, 13)
        s.text(ox + 44, y + 37, "where you fly, as the viewer's path.", DIM, 13)

    page(20, "Page 1: what you use all the time (swipe or ▸ for more)", [
        [("◆◀", "Prev key", "new"), ("▶", "Play", ""), ("●", "Record", ""), ("▶◆", "Next key", "new")],
        [("◆", "Auto-key", "red"), ("⋮⋮", "Snap", "on"), ("↻", "Loop", ""), ("↶", "Undo", "")],
        [("▦", "Shelf", ""), ("☰", "Inspector", "on"), ("🗂", "Outliner", "new"), ("▥", "Timeline", "on")],
    ], footer_main, 0)
    page(620, "Page 2: the rest, each with its line of help", [
        [("↷", "Redo", ""), ("⌂", "Seat", ""), ("⌖", "Go to it", ""), ("↩", "Back", "")],
        [("[", "Loop in", ""), ("]", "Loop out", ""), ("◆", "Key viewer", ""), ("✂", "Cut here", "")],
        [("● ⤳", "Arm ride", "red"), ("◱", "Miniature", ""), ("🗑", "Delete", ""), ("≡", "Menu", "new")],
    ], footer_more, 1)
    s.text(590, 540, "Every panel gets – (minimize to a tab on the wrist) next to ×.", DIM, 13, "middle")

    # panels carried with you (top down): a title bar to grab, and where they go as you fly
    s.panel(20, 580, 1140, 300, None, False)
    s.text(44, 614, "Panels in VR: grab the title bar to move one; they come along as you fly", TEXT, 16, weight=700)
    # a panel's title bar, close up
    s.rect(44, 640, 380, 44, "#1c212c", ACCENT, 10, 2)
    s.text(60, 668, "⋮⋮", DIM, 16, weight=700)
    s.text(86, 668, "Inspector", TEXT, 15, weight=700)
    s.panel_chrome(412, 649)
    s.text(44, 708, "Grip or trigger on the bar carries it; letting go leaves it", DIM, 13)
    s.text(44, 726, "where you put it, relative to you.", DIM, 13)
    s.text(44, 756, "–  folds it to a tab on the wrist; tap the tab to bring it back.", DIM, 13)

    def you(cx, cy, label):
        s.add(f"<circle cx='{cx}' cy='{cy}' r='14' fill='{ACCENT}'/>")
        s.add(f"<polygon points='{cx - 8},{cy - 12} {cx + 8},{cy - 12} {cx},{cy - 28}' fill='{ACCENT}'/>")
        s.text(cx, cy + 34, label, DIM, 12, "middle")

    def panels(cx, cy, col, dashed=False):
        extra = "stroke-dasharray='5 4'" if dashed else ""
        for dx, dy, rot in [(-70, -60, -30), (0, -80, 0), (70, -60, 30)]:
            s.add(f"<g transform='rotate({rot} {cx + dx} {cy + dy})'><rect x='{cx + dx - 26}' y='{cy + dy - 5}' width='52' height='10' rx='3' fill='{col}' fill-opacity='{0.25 if dashed else 0.9}' stroke='{col}' {extra}/></g>")

    # before / after, top down
    s.text(560, 660, "today", DIM, 13, weight=700)
    panels(620, 800, "#8c95a8", False)
    you(620, 800, "")
    s.line(640, 800, 760, 800, DIM, 2, "stroke-dasharray='4 4'")
    you(790, 800, "you fly on; the panels stay behind")
    s.text(850, 660, "after", ACCENT, 13, weight=700)
    panels(900, 800, "#4cc9f0", True)
    you(900, 800, "")
    s.line(920, 800, 1040, 800, ACCENT, 2, "stroke-dasharray='4 4'")
    panels(1070, 800, "#4cc9f0", False)
    you(1070, 800, "they keep their place around you")
    return s


# ------------------------------------------------------------- 4. timeline
def timeline():
    s = Svg(1400, 470)
    s.panel(20, 20, 1360, 430, None)
    # toolbar
    x = 40
    s.text(x, 62, "01:23.40", TEXT, 16, weight=700)
    x = 170
    for lab, w, act in [("◆◀", 44, False), ("▶◆", 44, False), ("−", 34, False), ("+", 34, False), ("Fit", 50, False), ("Loop", 60, False), ("[ In", 52, False), ("Out ]", 58, False), ("Grid…", 64, False)]:
        s.button(x, 42, w, 30, lab, act)
        x += w + 8
    s.new_badge(170, 22, "PREV / NEXT KEY")
    # key mode
    s.text(x + 20, 62, "Keys on change:", DIM, 13)
    for i, (lab, act) in enumerate([("Off", False), ("Animated", True), ("All (auto-key)", False)]):
        w = 40 + len(lab) * 7
        s.button(x + 132 + sum(40 + len(l) * 7 + 6 for l, _ in [("Off", 0), ("Animated", 0), ("All (auto-key)", 0)][:i]), 42, w, 30, lab, act)
    s.new_badge(x + 132, 22, "OPTION")
    s.panel_chrome(1360, 44)
    # ruler
    L, R = 200, 1350
    s.rect(40, 88, 1310, 24, "#121620", None, 4)
    for i in range(0, 11):
        tx = L + i * (R - L) / 10
        s.line(tx, 100, tx, 112, DIM)
        s.text(tx + 4, 106, f"1:{10 + i * 2:02d}", DIM, 11)
    # rows
    rows = [("screen_split", "group", ACCENT), ("left", "", ACCENT), ("middle", "", ACCENT), ("tunnel", "layer", PURPLE), ("viewer", "", AMBER)]
    y = 122
    for i, (name, kind, col) in enumerate(rows):
        s.rect(40, y, 1310, 40, "#121620" if i % 2 == 0 else "#141925", None, 4)
        s.text(50 + (16 if i in (1, 2) else 0), y + 25, name, TEXT, 13, weight=700 if kind == "group" else 400)
        if kind:
            s.text(190, y + 25, kind, DIM, 11, "end")
        if i == 0:
            s.rect(260, y + 8, 560, 24, ACCENT, None, 6, extra="fill-opacity='0.25'")
        elif i in (1, 2):
            s.rect(260, y + 8, 560, 24, ACCENT, None, 6, extra="fill-opacity='0.15'")
            for kx in (300, 470 + i * 40, 760):
                s.diamond(kx, y + 20, "key", 6)
        elif i == 3:
            # the block being dragged as a whole
            s.rect(560, y + 8, 420, 24, PURPLE, None, 6, extra="fill-opacity='0.12' stroke-dasharray='5 4' stroke='#b15cff'")
            s.rect(680, y + 8, 420, 24, PURPLE, "#ffffff", 6, 1.5, "fill-opacity='0.45'")
            s.text(890, y + 25, "⇔  tunnel 1:18.4 → 1:25.7", TEXT, 12, "middle", 700)
        else:
            for kx in (280, 520, 900, 1210):
                s.diamond(kx, y + 20, "key", 6)
            s.line(280, y + 20, 1210, y + 20, AMBER, 1.5, "stroke-dasharray='3 4'")
        y += 44
    # playhead
    s.line(640, 88, 640, y, TEXT, 2)
    # scroll bar over an overview
    y += 34
    s.rect(40, y, 1310, 44, "#10141c", LINE, 8)
    import random
    random.seed(4)
    for i in range(0, 260):
        xx = 48 + i * 5
        hgt = 4 + abs(math.sin(i * 0.21)) * 12 + random.random() * 8
        s.line(xx, y + 22 - hgt / 2, xx, y + 22 + hgt / 2, "#3a4254", 2)
    s.rect(340, y + 2, 300, 40, ACCENT, ACCENT, 8, 2, "fill-opacity='0.18'")
    s.text(490, y + 27, "⟷ the view: drag to scroll, pull its ends to zoom", TEXT, 12, "middle", 600)
    s.new_badge(40, y - 22, "SCROLL BAR")
    s.text(1350, y - 8, "the whole piece: 0:00 → 3:05", DIM, 12, "end")
    s.text(700, y - 8, "tunnel: drag the middle of a block to move it whole (was 1:14.4 → 1:21.7); its ends still stretch", DIM, 12, "middle")
    return s


# ---------------------------------------------- 5. placing: grid + new piece
def placing():
    s = Svg(1280, 720)
    s.rect(0, 0, 1280, 720, "url(#env)", None, 0)
    # perspective floor grid
    hy = 330  # horizon
    cx = 640
    for i in range(-14, 15):
        x_far = cx + i * 22
        x_near = cx + i * 260
        s.line(x_far, hy + 10, x_near, 720, "#4cc9f0", 1 if i % 5 else 1.6, "stroke-opacity='0.28'")
    for d in [1, 2, 3, 4, 5, 6, 8, 10, 14]:
        yy = hy + 10 + 390 / d * 0.95
        if yy > 720:
            continue
        s.line(0, yy, 1280, yy, "#4cc9f0", 1.4 if d in (1, 2, 5, 10) else 0.8, "stroke-opacity='0.3'")
        if d in (1, 2, 3, 5, 10):
            s.text(28, yy - 4, f"{d} m", ACCENT, 12, weight=600, extra="fill-opacity='0.8'")
    # the new piece's screen (from the template)
    s.rect(470, 150, 340, 190, "url(#vid)", "#ffffff", 4, 1, "fill-opacity='0.95'")
    s.text(640, 250, "clip.mp4", "#ffffff", 16, "middle", 700, "fill-opacity='0.8'")
    s.add("<ellipse cx='640' cy='372' rx='120' ry='10' fill='#000' fill-opacity='0.45'/>")
    s.text(640, 136, "main_screen · from the new-piece template", TEXT, 13, "middle", 600)
    # the card being dropped, close, with footprint
    s.rect(900, 470, 170, 100, "url(#vid2)", ACCENT, 4, 2, "fill-opacity='0.55' stroke-dasharray='6 4'")
    s.add("<ellipse cx='985' cy='620' rx='95' ry='16' fill='none' stroke='#4cc9f0' stroke-width='2'/>")
    s.line(985, 570, 985, 620, ACCENT, 1.5, "stroke-dasharray='3 3'")
    s.rect(1020, 604, 112, 28, "#10141c", ACCENT, 8, 1.5)
    s.text(1076, 623, "2.4 m away", ACCENT, 13, "middle", 700)
    s.text(985, 458, "Screen (dropping)", TEXT, 13, "middle", 600)
    # status line
    s.rect(20, 20, 520, 76, PANEL, LINE, 12)
    s.text(40, 50, "EDIT", BG, 14, weight=800, extra="")
    s.add(f"<rect x='34' y='33' width='56' height='24' rx='6' fill='{ACCENT}'/>")
    s.text(62, 50, "EDIT", BG, 14, "middle", 800)
    s.text(104, 51, "clip", TEXT, 16)
    s.text(40, 82, "New piece clip.json: it starts with a screen showing the video.", DIM, 13)
    s.rect(900, 20, 360, 66, PANEL, LINE, 12)
    s.text(920, 46, "The floor grid shows distance (1 m lines).", TEXT, 13)
    s.text(920, 68, "A card lands where the floor under the cursor is.", DIM, 13)
    return s


# ------------------------------------ 6. animation: groups, outliner, paths
def animation():
    s = Svg(1280, 720)
    s.rect(0, 0, 1280, 720, "url(#env)", None, 0)
    hy = 360
    for i in range(-12, 13):
        s.line(640 + i * 26, hy, 640 + i * 200, 720, "#4cc9f0", 0.8, "stroke-opacity='0.15'")
    # three-screen split inside a group box
    xs = [(470, 180, -8), (640, 170, 0), (810, 180, 8)]
    s.rect(380, 150, 520, 170, "none", ACCENT, 10, 1.5, "stroke-dasharray='8 5'")
    s.text(390, 142, "screen_split (group) · moves, turns and scales as one", ACCENT, 13, weight=700)
    for cx, w, rot in xs:
        s.add(f"<g transform='rotate({rot} {cx} 235)'><rect x='{cx - w / 2 + 6}' y='170' width='{w - 12}' height='130' rx='3' fill='url(#vid)' stroke='#fff' stroke-opacity='0.6'/></g>")
    # motion path of the group
    pts = [(640, 330), (720, 420), (900, 470), (1080, 430), (1150, 330)]
    d = "M " + " ".join(f"{x},{y}" for x, y in pts)
    s.add(f"<path d='M 640,330 C 690,420 820,480 900,470 S 1060,450 1080,430 S 1140,370 1150,330' fill='none' stroke='{AMBER}' stroke-width='3' stroke-dasharray='2 7' stroke-linecap='round'/>")
    for (x, y), t in zip(pts, ["1:20", "1:24", "1:28", "1:32", "1:36"]):
        s.diamond(x, y, "key", 8)
        s.text(x + 12, y - 8, t, AMBER, 12, weight=700)
    s.text(1000, 520, "motion path: always drawn for the selection,", TEXT, 13, "middle")
    s.text(1000, 538, "faintly for other animated things; grab a key to move it", DIM, 13, "middle")
    # outliner panel
    s.panel(20, 90, 300, 420, "Outliner")
    s.new_badge(130, 108)
    tree = [
        ("▾ screen_split", "group", True, 0),
        ("left", "screen", False, 1),
        ("middle", "screen", False, 1),
        ("right", "screen", False, 1),
        ("tunnel", "layer", False, 0),
        ("cube", "object", False, 0),
        ("viewer", "path", False, 0),
    ]
    y = 140
    for name, kind, sel, depth in tree:
        if sel:
            s.rect(34, y - 4, 272, 34, "#1f2a3a", ACCENT, 8, 1.5)
        s.text(50 + depth * 22, y + 18, name, TEXT, 14, weight=700 if sel else 400)
        s.text(292, y + 18, kind, DIM, 11, "end")
        y += 38
    s.line(34, y + 4, 306, y + 4)
    s.button(34, y + 16, 130, 32, "Group (Ctrl+G)")
    s.button(174, y + 16, 132, 32, "Ungroup")
    s.text(40, y + 72, "Click to select · drag onto a", DIM, 12)
    s.text(40, y + 90, "group to put it in", DIM, 12)
    # opacity bug note
    s.rect(20, 600, 700, 90, PANEL, LINE, 12)
    s.text(40, 630, "Keys on change: Animated", TEXT, 14, weight=700)
    s.text(40, 652, "A setting that already has keys gets a key at the playhead when you change it;", DIM, 13)
    s.text(40, 672, "a still one is just set. (And a shader layer's opacity animates: the bug is fixed.)", DIM, 13)
    return s


# ---------------------------------------------------------------- 7. shelf
def shelf():
    s = Svg(900, 560)
    s.panel(20, 20, 860, 520, "Shelf")
    tabs = [("Objects", False), ("Layers", False), ("Effects", False), ("Vertex", False), ("Looks", False), ("Shadertoy", True), ("Open…", False)]
    x = 110
    for t, act in tabs:
        w = 22 + len(t) * 8
        s.button(x, 34, w, 30, t, act)
        if t in ("Vertex", "Shadertoy"):
            s.new_badge(x + w - 24, 20)
        x += w + 6
    s.panel_chrome(858, 36)
    s.rect(42, 82, 600, 34, FIELD, LINE, 8)
    s.text(56, 104, "🔍  Search Shadertoy (or paste a link)", DIM, 14)
    s.button(654, 82, 204, 34, "Open the browser ↗")
    cards = [("Seascape", "url(#vid2)"), ("Tunnel of lights", "url(#tunnel)"), ("Warp speed", "url(#vid)"), ("Plasma bars", "url(#vid3)"),
             ("Fractal pyramid", "url(#vid)"), ("Clouds", "url(#vid2)"), ("Synthwave", "url(#vid3)"), ("Kaleido", "url(#tunnel)")]
    for i, (name, fill) in enumerate(cards):
        cx = 42 + (i % 4) * 206
        cy = 134 + (i // 4) * 170
        s.rect(cx, cy, 194, 156, "#1c212c", ACCENT if i == 1 else LINE, 10, 2 if i == 1 else 1)
        s.rect(cx + 8, cy + 8, 178, 100, fill, None, 6)
        # a short loop: frame ticks and a progress bar
        s.rect(cx + 8, cy + 102, 178, 6, "#000", None, 0, "fill-opacity='0.5'")
        s.rect(cx + 8, cy + 102, 178 * ((i * 0.23 + 0.3) % 1), 6, ACCENT, None, 0)
        s.text(cx + 174, cy + 26, "▶", "#ffffff", 14, "end", 700, "fill-opacity='0.85'")
        s.text(cx + 12, cy + 132, name, TEXT, 13, weight=600)
        s.text(cx + 12, cy + 148, "layer · effect", DIM, 11)
    s.text(42, 492, "Pick a shader: it becomes a layer, or an effect on a screen (as in the player). Cards on every tab", DIM, 13)
    s.text(42, 512, "play a short loop instead of a still (on hover on the desktop; in the headset while the shelf is open).", DIM, 13)
    return s


# ---------------------------------------------------------- 8. performance
def performance():
    s = Svg(900, 560)
    s.panel(20, 20, 860, 520, "GPU cost")
    s.new_badge(128, 22)
    s.panel_chrome(858, 36)
    s.text(44, 84, "This frame: 11.2 ms of 13.9 ms (72 Hz on the Quest 3)", TEXT, 15, weight=600)
    s.rect(44, 96, 812, 16, "#262c3a", None, 8)
    s.rect(44, 96, 812 * 11.2 / 13.9, 16, AMBER, None, 8)
    s.text(856, 130, "72 fps", GREEN, 14, "end", 700)
    items = [
        ("tunnel", "layer · shader", 3.8, PURPLE),
        ("main_screen · Glow", "effect", 1.9, ACCENT),
        ("camera · Kaleidoscope", "camera effect", 1.6, ACCENT),
        ("screen_split · Ripple", "vertex effect", 1.1, ACCENT),
        ("video decode", "", 0.9, DIM),
        ("cube", "object", 0.3, DIM),
        ("the rest", "", 1.6, DIM),
    ]
    y = 156
    for name, kind, ms, col in items:
        s.text(44, y + 18, name, TEXT, 14, weight=600)
        s.text(300, y + 18, kind, DIM, 12)
        s.rect(420, y + 5, 360, 16, "#1c212c", None, 6)
        s.rect(420, y + 5, 360 * ms / 4.0, 16, col, None, 6, extra="fill-opacity='0.8'")
        s.text(856, y + 18, f"{ms:.1f} ms", TEXT, 13, "end")
        y += 36
    s.line(44, y + 6, 856, y + 6)
    s.button(44, y + 22, 210, 36, "▶ Benchmark the piece", True)
    s.text(270, y + 45, "plays it through at full speed and lists the heaviest moments:", DIM, 13)
    s.text(270, y + 65, "1:28–1:43 (tunnel + Kaleidoscope) 15.8 ms · over budget", RED, 13, weight=600)
    s.text(44, y + 100, "Click a line to select it. Each cost is how much faster the frame gets with that one switched off (the GPU frame time, measured in turn).", DIM, 12)
    return s


if __name__ == "__main__":
    for name, fn in [("1_menu", menu), ("2_inspector", inspector), ("3_wrist", wrist), ("4_timeline", timeline),
                     ("5_placing", placing), ("6_animation", animation), ("7_shelf", shelf), ("8_performance", performance)]:
        save(name + ".svg", fn())
