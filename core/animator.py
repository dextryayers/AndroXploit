#!/usr/bin/env python3
import time
import os
import sys
import random
import re
import math
from rich.console import Console
from rich.progress import (
    Progress, SpinnerColumn, BarColumn, TextColumn,
    TimeElapsedColumn, TimeRemainingColumn, MofNCompleteColumn,
)
from rich.live import Live
from rich.table import Table
from rich.panel import Panel
from rich.text import Text
from rich.align import Align
from yaspin import yaspin
from yaspin.spinners import Spinners

console = Console()

SPINNER_STYLES = {
    "premium": Spinners.arc, "dots": Spinners.dots12, "moon": Spinners.moon,
    "earth": Spinners.earth, "clock": Spinners.clock, "arrow": Spinners.arrow3,
    "toggle": Spinners.toggle7, "pulse": Spinners.earth, "bounce": Spinners.bouncingBar,
}

RST = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
WHT = "\033[38;5;255m"
BRT = "\033[38;5;15m"
YLW = "\033[38;5;226m"
RED = "\033[38;5;196m"
BLU = "\033[38;5;39m"
CYN = "\033[38;5;51m"
CYL = "\033[38;5;87m"
MGT = "\033[38;5;201m"
ORG = "\033[38;5;214m"
PNK = "\033[38;5;213m"
G1 = "\033[38;5;82m"
G2 = "\033[38;5;46m"
G3 = "\033[38;5;28m"
G4 = "\033[38;5;22m"
DOR = "\033[38;5;166m"
GRY = "\033[38;5;240m"
SLV = "\033[38;5;249m"
PPL = "\033[38;5;141m"
NRB = "\033[38;5;117m"
DPU = "\033[38;5;61m"
CLR = "\033[2J\033[H"

def strip(s):
    return re.sub(r'\033\[[0-9;]*m', '', s)

def ease_in_out(t):
    return t * t * (3 - 2 * t) if t < 1 else 1

def ease_out(t):
    return 1 - (1 - t) ** 3 if t < 1 else 1

def ease_in(t):
    return t ** 3 if t < 1 else 1

def lerp(a, b, t):
    return a + (b - a) * t

def lerp_int(a, b, t):
    return int(round(lerp(a, b, t)))

GRADIENT_CYAN = [CYL, CYN, BLU, NRB, WHT]
GRADIENT_GOLD = [YLW, ORG, DOR, WHT]
GRADIENT_LAVA = [RED, ORG, YLW, BRT, WHT]
GRADIENT_GLOW = [CYN, CYL, BRT, WHT, WHT]

def gradient_pick(grad, t):
    t = max(0, min(1, t))
    idx = t * (len(grad) - 1)
    i = int(idx)
    if i >= len(grad) - 1:
        return grad[-1]
    return grad[i]

def _ufo_cells(ux, uy, blink, tilt, pulse, glow=0):
    cells = {}
    tilt_off = tilt * 2
    p = pulse % 8
    beacon = ["◉","◎","◈","◎","◉","◎"][p // 2 % 6]
    S = SLV; D = CYL; R = CYN; L = YLW; G = G1; g = G4

    def p15(s):
        return s + " " * (15 - len(strip(s)))

    all_lines = [
        (0,  p15(f"{S}╔═════════════╗{RST}")),
        (1,  p15(f" {S}║{L} {beacon} {beacon} {beacon} {beacon} {beacon} ║{RST}")),
        (2,  p15(f"{S}╚╗           ╔╝{RST}")),
        (3,  p15(f"{S}╚╤═══════════╤╝{RST}")),
        (4,  p15(f"{S}╔══╝       ╚══╗{RST}")),
        (5,  p15(f" {S}║{R}┌───────┐{S}║{RST}")),
        (6,  p15(f" {S}║{R}│{S}       {R}│{S}║{RST}")),
        (7,  p15(f" {S}║{R}│{S} {L}{beacon}{S}   {R}│{S}║{RST}")),
    ]
    if blink:
        all_lines[7] = (7, p15(f" {S}║{R}│{S} {RED}✕{S}   {R}│{S}║{RST}"))
    all_lines += [
        (8,  p15(f" {S}║{R}│{S}       {R}│{S}║{RST}")),
        (9,  p15(f" {S}║{R}└───────┘{S}║{RST}")),
        (10, p15(f"{S}╚╗           ╔╝{RST}")),
        (11, p15(f"╚══╗     ╔══╝{RST}")),
        (12, p15(f"{G}███████████████{RST}")),
        (13, p15(f"{G}███████{CYN}◈{G}███████{RST}")),
        (14, p15(f"{G}███████████████{RST}")),
        (15, p15(f"{g}╚═════════════╝{RST}")),
    ]

    for dy, line in all_lines:
        ly = uy + dy
        if ly < 0: continue
        for ci, ch in enumerate(line):
            x = ux + ci + tilt_off
            if x >= 0:
                cells[(ly, int(x))] = ch

    if glow > 1:
        for g in range(min(glow, 4)):
            gy = uy + 16 + g
            if gy < 0: continue
            w = g + 1 + glow
            gc = ux + 7 + tilt_off
            for gx in range(gc - w, gc + w + 1):
                if (gy, gx) in cells: continue
                d = abs(gx - gc) / (w + 1)
                if d < 0.25:
                    cells[(gy, gx)] = CYL + "▓" + RST
                elif d < 0.5:
                    cells[(gy, gx)] = CYN + "▒" + RST if random.random() < 0.7 else ""
    return cells

def _ufo_exhaust(ux, uy, frame):
    cells = {}
    for i in range(6):
        ex = ux + 7 + random.randint(-6, 6)
        ey = uy + 16 + random.randint(0, 3)
        if ey >= 0:
            cells[(ey, ex)] = gradient_pick(GRADIENT_LAVA, random.random()) + random.choice(["▓","▒","░"]) + RST
    return cells

def _alien_cells(ax, ay, frame):
    cells = {}
    g = G2
    blink = frame % 18 > 15
    happy = frame % 30 > 25
    eyes = "◉◉" if not blink else "××"
    mouth = "∪" if happy else "‿"
    lines = [
        (0, f" {g}╔═══╗{RST}"),
        (1, f" {g}║{g}{eyes}{g}║{RST}"),
        (2, f" {g}║ {G1}{mouth}{g} ║{RST}"),
        (3, f" {g}╚═╤═╝{RST}"),
    ]
    for dy, line in lines:
        y = ay + dy
        if y < 0: continue
        for dx, ch in enumerate(line):
            x = ax + dx
            if x >= 0:
                cells[(y, x)] = ch
    return cells

def _comet_cells(fr, cols, rows):
    cells = {}
    if fr < 0 or fr > 40: return cells, 0, 0
    p = fr / 40
    sx = cols + 5
    sy = 1
    ex = cols // 3
    ey = rows // 2
    cx = lerp_int(sx, ex, ease_in(p))
    cy = lerp_int(sy, ey, ease_in(p))
    tail_len = int(8 + p * 12)
    for i in range(tail_len):
        tx = cx - i * 2
        ty = cy + i // 2
        if 0 <= ty < rows and 0 <= tx < cols and (ty, tx) not in cells:
            a = 1.0 - i / tail_len
            if a > 0.6:
                cells[(ty, tx)] = gradient_pick(GRADIENT_LAVA, a) + "*" + RST
            elif a > 0.3:
                cells[(ty, tx)] = ORG + "·" + RST
            else:
                cells[(ty, tx)] = DOR + "." + RST
    if 0 <= cy < rows and 0 <= cx < cols:
        cells[(cy, cx)] = BRT + "✦" + RST
        if cy + 1 < rows and cx + 1 < cols:
            cells[(cy+1, cx)] = gradient_pick(GRADIENT_LAVA, 0.8) + "▓" + RST
            cells[(cy, cx+1)] = gradient_pick(GRADIENT_LAVA, 0.8) + "▓" + RST
        if cy - 1 >= 0:
            cells[(cy-1, cx)] = BRT + "·" + RST
            cells[(cy, cx-1)] = BRT + "·" + RST
    return cells, cx, cy

def _explosion_cells(cx, cy, frame):
    cells = {}
    if frame < 0 or frame >= 50: return cells
    p = frame / 50
    if frame < 8:
        r = frame * 2 + 1
        for dy in range(-r-1, r+2):
            for dx in range(-r-1, r+2):
                d = math.sqrt(dx*dx + dy*dy)
                y, x = cy+dy, cx+dx
                if y < 0 or x < 0: continue
                if d <= r*0.4:
                    cells[(y, x)] = BRT + "█" + RST
                elif d <= r*0.65:
                    cells[(y, x)] = gradient_pick(GRADIENT_LAVA, 0.8) + "▓" + RST
                elif d <= r*0.9:
                    cells[(y, x)] = ORG + "▒" + RST
                elif d <= r:
                    cells[(y, x)] = RED + "▒" + RST if random.random() < 0.5 else ""
    elif frame < 16:
        r = int(p * 16) + 1
        for dy in range(-r-2, r+3):
            for dx in range(-r-2, r+3):
                d = math.sqrt(dx*dx + dy*dy)
                y, x = cy+dy, cx+dx
                if y < 0 or x < 0: continue
                if d < r*0.15:
                    cells[(y, x)] = YLW + random.choice(["█","▓"]) + RST
                elif d < r*0.35:
                    cells[(y, x)] = ORG + random.choice(["▓","▒"]) + RST
                elif d < r*0.55:
                    cells[(y, x)] = RED + random.choice(["▒","░"]) + RST
                elif d < r*0.75 and random.random() < 0.3:
                    cells[(y, x)] = ORG + "░" + RST
                elif d < r and random.random() < 0.15:
                    cells[(y, x)] = DOR + "." + RST
    elif frame < 26:
        r = int(p * 14) + 1
        for dy in range(-r-3, r+4):
            for dx in range(-r-3, r+4):
                d = math.sqrt(dx*dx + dy*dy)
                y, x = cy+dy, cx+dx
                if y < 0 or x < 0: continue
                if d < r*0.15 and random.random() < 0.4:
                    cells[(y, x)] = YLW + random.choice(["▓","▒"]) + RST
                elif d < r*0.4 and random.random() < 0.25:
                    cells[(y, x)] = ORG + random.choice(["▒","░"]) + RST
                elif d < r*0.65 and random.random() < 0.1:
                    cells[(y, x)] = RED + "░" + RST
                elif d < r*0.85 and random.random() < 0.05:
                    cells[(y, x)] = DOR + "." + RST
    else:
        r = int(p * 10) + 1
        for dy in range(-r-3, r+4):
            for dx in range(-r-3, r+4):
                d = math.sqrt(dx*dx + dy*dy)
                y, x = cy+dy, cx+dx
                if y < 0 or x < 0: continue
                if d < r*0.2 and random.random() < 0.15:
                    cells[(y, x)] = ORG + "▒" + RST
                elif d < r*0.45 and random.random() < 0.08:
                    cells[(y, x)] = RED + "░" + RST
                elif d < r*0.7 and random.random() < 0.03:
                    cells[(y, x)] = DOR + "." + RST
    return cells

def _explosion_debris_update(debris):
    for d in debris:
        d[0] += d[3] * math.cos(d[2])
        d[1] += d[3] * math.sin(d[2]) + 0.06
        d[3] *= 0.97

def _explosion_debris_render(cells, debris, cx, cy, frame, cols, rows):
    for d in debris:
        ey = cy + int(d[1])
        ex = cx + int(d[0])
        if 0 <= ey < rows and 0 <= ex < cols and (ey, ex) not in cells:
            if frame < 10:
                cells[(ey, ex)] = gradient_pick(GRADIENT_LAVA, random.random()) + random.choice(["*","✦","◉","+"]) + RST
            elif frame < 20:
                cells[(ey, ex)] = ORG + random.choice(["·",".","o","'"]) + RST
            elif frame < 30:
                if random.random() < 0.5:
                    cells[(ey, ex)] = RED + random.choice(["·","."]) + RST
            elif frame < 42:
                if random.random() < 0.2:
                    cells[(ey, ex)] = DOR + "." + RST
            else:
                if random.random() < 0.08:
                    cells[(ey, ex)] = GRY + "." + RST

def _add_smoke_cloud(cells, cx, cy, frame, cols, rows):
    if frame < 8: return
    age = frame - 8
    if age > 55: return
    p = age / 55
    r = int(3 + p * 9)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            d = math.sqrt(dx*dx + dy*dy)
            if d > r: continue
            y, x = cy + dy, cx + dx
            if y < 0 or x < 0 or y >= rows or x >= cols: continue
            if (y, x) in cells: continue
            alpha = 1.0 - d / r
            density = alpha * (1.0 - p * 0.65)
            if density > 0.35 and random.random() < density:
                ch = random.choices(["▓","▒","░"], [2,5,3])[0]
                col = random.choices([GRY, DIM], [4,3])[0]
                cells[(y, x)] = col + ch + RST

class UFOAnimator:
    def _render(self, cells, cols, rows):
        out = CLR
        for r in range(rows):
            line = ""
            for c in range(cols):
                line += cells.get((r, c), " ")
            out += line + "\n"
        sys.stdout.write(out)
        sys.stdout.flush()

    def _make_stars(self, count, cols, rows):
        stars = []
        chars = ["·"] * 120 + ["*"] * 20 + ["☆"] * 8 + ["✧"] * 5 + ["⋆"] * 3 + ["✦"] * 2
        for _ in range(count):
            stars.append([
                random.randint(0, cols - 1),
                random.randint(0, rows - 1),
                random.choice(chars),
                random.uniform(0.15, 0.9),
                random.uniform(0.04, 0.25),
            ])
        return stars

    def _add_stars(self, cells, stars, frame, cols, rows):
        for star in stars:
            sx = (star[0] + int(frame * star[3] * 0.15)) % cols
            sy = star[1]
            sc = star[2]
            twinkle = random.random() < star[4]
            if 0 <= sy < rows:
                if sc in ("*", "☆", "✧", "⋆", "✦"):
                    if twinkle:
                        cells[(sy, sx)] = gradient_pick(GRADIENT_CYAN, random.random()) + sc + RST
                    else:
                        cells[(sy, sx)] = WHT + sc + RST
                elif sc == "·":
                    if random.random() < 0.12:
                        cells[(sy, sx)] = DIM + "·" + RST

    def _add_shooting_star(self, cells, frame, cols, rows):
        if frame > 2 and frame % 45 == 0 and random.random() < 0.6:
            ss_x = random.randint(5, cols - 5)
            ss_y = random.randint(0, rows // 2 - 1)
            for i in range(12):
                sx = (ss_x - i * 2 + frame // 2) % cols
                sy = ss_y + i // 2
                if 0 <= sy < rows and 0 <= sx < cols:
                    a = 1.0 - i / 12
                    if a > 0.5:
                        cells[(sy, sx)] = gradient_pick(GRADIENT_GLOW, a) + "✦" + RST
                    elif a > 0.2:
                        cells[(sy, sx)] = CYL + "·" + RST

    def _add_planets(self, cells, frame, cols, rows):
        planets = [
            {"x": cols - 12, "y": 2, "c": CYL, "s": 4, "ring": True},
            {"x": 5, "y": 3, "c": ORG, "s": 3, "ring": False},
            {"x": cols // 2 + 12, "y": 4, "c": PPL, "s": 2, "ring": False},
            {"x": cols // 3 - 2, "y": 1, "c": NRB, "s": 2, "ring": True},
        ]
        for pd in planets:
            cx, cy, c, s, ring = pd["x"], pd["y"], pd["c"], pd["s"], pd["ring"]
            for dy in range(-s - 1, s + 2):
                for dx in range(-s - 2, s + 3):
                    d2 = dx*dx + dy*dy
                    if d2 <= s*s + 2:
                        dist = math.sqrt(d2)
                        t = dist / (s + 0.5)
                        if c == CYL:
                            shade = gradient_pick([c, NRB, CYL, WHT], t)
                        elif c == ORG:
                            shade = gradient_pick([c, DOR, ORG, WHT], t)
                        else:
                            shade = c
                        if dist < s*0.3: sh = "▓"
                        elif dist < s*0.6: sh = "▒"
                        else: sh = "░"
                        y, x = cy+dy, cx+dx
                        if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                            cells[(y, x)] = shade + sh + RST

            if ring:
                for dy in range(-1, 2):
                    for dx in range(-s - 3, s + 4):
                        d2 = dx*dx + dy*dy
                        if (s + 1)**2 <= d2 <= (s + 3)**2 and abs(dy) <= 1:
                            y, x = cy+dy, cx+dx
                            if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                                cells[(y, x)] = SLV + "░" + RST if random.random() < 0.6 else CYL + "░" + RST

    def fly(self):
        cols, rows = 80, 24
        try:
            import shutil
            cols = max(80, shutil.get_terminal_size().columns)
            rows = max(24, shutil.get_terminal_size().lines)
        except: pass
        os.system("clear" if os.name == "posix" else "cls")

        stars = self._make_stars(180, cols, rows)

        # PHASE 1: UFO enters from left, alien visible, cruises
        for fr in range(140):
            cells = {}
            self._add_stars(cells, stars, fr, cols, rows)
            self._add_shooting_star(cells, fr, cols, rows)
            self._add_planets(cells, fr, cols, rows)

            p = min(1, fr / 30)
            ux = lerp_int(-15, cols // 3, ease_out(p))
            uy = 3 + int(3 * math.sin(fr * 0.25))
            blink = (fr % 30) > 27
            tilt = max(0, int(2 * (1 - ease_out(p)))) if fr < 30 else int(1.5 * math.sin(fr * 0.08))
            glow = 0 if fr < 25 else min(3, (fr - 25) // 10)

            ufc = _ufo_cells(ux, uy, blink, tilt, fr % 8, glow)
            for (y, x), val in ufc.items():
                if 0 <= y < rows and 0 <= x < cols:
                    cells[(y, x)] = val

            if fr > 30 and fr % 4 == 0:
                exh = _ufo_exhaust(ux, uy, fr)
                for (y, x), val in exh.items():
                    if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                        cells[(y, x)] = val

            if fr > 15 and fr < 100:
                alien_x = ux + 6
                alien_y = uy + 6
                ac = _alien_cells(alien_x, alien_y, fr)
                for (y, x), val in ac.items():
                    if 0 <= y < rows and 0 <= x < cols:
                        cells[(y, x)] = val

            if fr > 50 and fr < 90:
                ufo2_x = cols - 20 - int(20 * math.sin(fr * 0.02))
                ufo2_y = rows - 4 + int(2 * math.sin(fr * 0.1))
                if ufo2_x < cols - 5:
                    cells[(ufo2_y, ufo2_x)] = DIM + CYN + "◈" + RST
                    cells[(ufo2_y-1, ufo2_x+1)] = DIM + CYN + "·" + RST

            self._render(cells, cols, rows)
            time.sleep(0.022)

        # PHASE 2: UFO does swooping maneuver, builds speed
        for fr in range(100):
            cells = {}
            self._add_stars(cells, stars, fr, cols, rows)
            self._add_shooting_star(cells, fr, cols, rows)
            self._add_planets(cells, fr, cols, rows)

            p = fr / 100
            ux = lerp_int(cols // 3, cols + 10, ease_in_out(p))
            arc = 8 * math.sin(p * math.pi * 1.5)
            uy = 3 + int(arc + 2 * math.sin(fr * 0.3))
            tilt = int(4 * math.sin(p * math.pi * 1.2))
            blink = (fr % 20) > 17
            glow = 2 + int(p * 3)

            ufc = _ufo_cells(ux, uy, blink, tilt, fr % 6, glow)
            for (y, x), val in ufc.items():
                if 0 <= y < rows and 0 <= x < cols:
                    cells[(y, x)] = val

            if fr % 2 == 0:
                exh = _ufo_exhaust(ux, uy, fr)
                for (y, x), val in exh.items():
                    if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                        cells[(y, x)] = val

            alien_x = ux + 6
            alien_y = uy + 9
            ac = _alien_cells(alien_x, alien_y, fr)
            for (y, x), val in ac.items():
                if 0 <= y < rows and 0 <= x < cols:
                    cells[(y, x)] = val

            self._render(cells, cols, rows)
            time.sleep(0.025)

        # PHASE 3: UFO turns back, comet streaks in, collision
        collision_x = cols // 3 + 4
        collision_y = rows // 2 - 1
        for fr in range(55):
            cells = {}
            self._add_stars(cells, stars, fr, cols, rows)
            self._add_planets(cells, fr, cols, rows)

            p3 = min(1, fr / 40)
            ux = lerp_int(cols + 15, collision_x, ease_in_out(p3))
            uy = collision_y + int(6 * math.sin(p3 * math.pi * 1.3) * (1 - p3 * 0.5))
            tilt = int(4 * math.sin(p3 * math.pi * 0.8))
            blink = fr % 4 == 0
            glow = 3
            if fr > 30:
                glow = 4 + int((fr - 30) / 5)
                blink = fr % 2 == 0
            ufc = _ufo_cells(ux, uy, blink, tilt, fr % 4, glow)
            for (y, x), val in ufc.items():
                if 0 <= y < rows and 0 <= x < cols:
                    cells[(y, x)] = val

            if fr % 2 == 0 and fr < 38:
                exh = _ufo_exhaust(ux, uy, fr)
                for (y, x), val in exh.items():
                    if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                        cells[(y, x)] = val

            cc, comet_x, comet_y = _comet_cells(fr - 10, cols, rows)
            for (y, x), val in cc.items():
                if 0 <= y < rows and 0 <= x < cols:
                    cells[(y, x)] = val
            if comet_x != 0 or comet_y != 0:
                collision_x = comet_x
                collision_y = comet_y

            if fr > 28:
                for _ in range(5):
                    sx = ux + random.randint(-12, 12)
                    sy = uy + random.randint(-8, 8)
                    if 0 <= sy < rows and 0 <= sx < cols and (sy, sx) not in cells:
                        cells[(sy, sx)] = gradient_pick(GRADIENT_LAVA, random.random()) + random.choice(["▓","▒","*"]) + RST

            if fr >= 45:
                for _ in range(8):
                    sx = random.randint(0, cols - 1)
                    sy = random.randint(0, rows - 1)
                    if 0 <= sy < rows and 0 <= sx < cols:
                        cells[(sy, sx)] = BRT + random.choice(["█","▓","*"]) + RST

            self._render(cells, cols, rows)
            time.sleep(0.026)

        hit_x, hit_y = collision_x, collision_y

        # PHASE 4: Collision - big flash then explosion
        for flash in range(6):
            out = CLR
            for r in range(rows):
                for c in range(cols):
                    out += gradient_pick(GRADIENT_LAVA, flash / 5) + "█" + RST
                out += "\n"
            sys.stdout.write(out)
            sys.stdout.flush()
            time.sleep(0.05)
        debris = []
        for _ in range(90):
            ang = random.uniform(0, 2 * math.pi)
            spd = random.uniform(2.0, 7.0)
            debris.append([0.0, 0.0, ang, spd])

        for fr in range(60):
            cells = {}
            self._add_stars(cells, stars, fr, cols, rows)

            ec = _explosion_cells(hit_x, hit_y, fr)
            for (y, x), val in ec.items():
                if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                    cells[(y, x)] = val

            _explosion_debris_update(debris)
            _explosion_debris_render(cells, debris, hit_x, hit_y, fr, cols, rows)

            if fr >= 6:
                _add_smoke_cloud(cells, hit_x, hit_y, fr, cols, rows)

            if fr < 20 and fr % 2 == 0:
                for _ in range(3):
                    sx = hit_x + random.randint(-15, 15)
                    sy = hit_y + random.randint(-10, 10)
                    if 0 <= sy < rows and 0 <= sx < cols and (sy, sx) not in cells:
                        cells[(sy, sx)] = gradient_pick(GRADIENT_LAVA, random.random()) + random.choice(["*","✦","+"]) + RST

            self._render(cells, cols, rows)
            time.sleep(0.05)

        # PHASE 5: Smoke fades, stars return
        for fr in range(25):
            cells = {}
            self._add_stars(cells, stars, fr, cols, rows)
            _add_smoke_cloud(cells, hit_x, hit_y, fr + 60, cols, rows)
            for _ in range(2):
                sx = hit_x + random.randint(-8, 8)
                sy = hit_y + random.randint(-6, 6)
                if 0 <= sy < rows and 0 <= sx < cols and (sy, sx) not in cells:
                    cells[(sy, sx)] = GRY + random.choice(["░","·"]) + RST
            self._render(cells, cols, rows)
            time.sleep(0.06)

        self._landing(cols, rows)

    def _landing(self, cols, rows):
        import pyfiglet
        nl = pyfiglet.figlet_format("AndroXploit", font="big").splitlines()
        bw = max(len(strip(line)) for line in nl)
        box_in = 30
        box_w = box_in + 4
        box_l = "═" * box_in
        line1 = " AndroXploit V1.1 "
        line2 = "   By: AniipID    "
        cx = max(2, (cols - bw) // 2)
        bx = max(2, (cols - box_w) // 2)
        p = " " * cx
        bp = " " * bx

        for f in range(22):
            a = (f + 1) / 22
            cv = int(82 + (46 - 82) * a)
            c = f"\033[38;5;{cv}m"
            g = f"\033[38;5;{int(46 + (82-46)*a)}m"
            out = CLR
            out += "\n" * 2
            for line in nl:
                out += p + BOLD + c + line + RST + "\n"
            out += "\n"
            out += bp + c + "╔" + box_l + "╗" + RST + "\n"
            out += bp + c + "║" + RST + " " + BOLD + g + line1 + RST + " " + c + "║" + RST + "\n"
            out += bp + c + "║" + RST + " " * box_in + c + "║" + RST + "\n"
            out += bp + c + "║" + RST + " " + DIM + G2 + line2 + RST + " " + c + "║" + RST + "\n"
            out += bp + c + "╚" + box_l + "╝" + RST + "\n"
            sys.stdout.write(out)
            sys.stdout.flush()
            time.sleep(0.03)
        time.sleep(1.5)


class Animator:
    _instance = None
    _current_spinner = None

    @classmethod
    def premium(cls, text="Processing..."):
        return yaspin(SPINNER_STYLES["premium"], text=text, color="green")

    @classmethod
    def spinner(cls, text="Processing...", style="dots"):
        sp = SPINNER_STYLES.get(style, SPINNER_STYLES["dots"])
        return yaspin(sp, text=text, color="green")

    @classmethod
    def pulse(cls, text="Working..."):
        return yaspin(SPINNER_STYLES["pulse"], text=text, color="green")

    @classmethod
    def task(cls, text="Running..."):
        return yaspin(SPINNER_STYLES["moon"], text=text, color="green")

    @classmethod
    def clock(cls, text="Timed operation..."):
        return yaspin(SPINNER_STYLES["clock"], text=text, color="green")

    @classmethod
    def progress(cls, description="Processing", total=100, transient=True):
        p = Progress(
            SpinnerColumn(spinner_name="dots12", style="green"),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(complete_style="green", finished_style="green", pulse_style="green"),
            MofNCompleteColumn(),
            TimeElapsedColumn(),
            TimeRemainingColumn(),
            console=console, transient=transient,
        )
        return p

    @classmethod
    def table_progress(cls, title="Progress", columns=None):
        table = Table(title=title, border_style="green", header_style="bold yellow")
        for col in columns or ["Component", "Status"]:
            table.add_column(col, style="white")
        return table


class LiveProgress:
    def __init__(self, description="Processing", total=100):
        self.description = description
        self.total = total
        self.progress = Progress(
            SpinnerColumn(spinner_name="dots12", style="green"),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(complete_style="green", finished_style="green", pulse_style="green"),
            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
            TimeElapsedColumn(), TimeRemainingColumn(),
            console=console,
        )
        self.task_id = None
        self.live = None

    def __enter__(self):
        self.live = Live(self.progress, refresh_per_second=10, console=console, transient=True)
        self.live.__enter__()
        self.task_id = self.progress.add_task(f"[green]{self.description}", total=self.total)
        return self

    def update(self, completed=None, description=None, advance=None):
        if description:
            self.progress.update(self.task_id, description=f"[green]{description}")
        if advance:
            self.progress.update(self.task_id, advance=advance)
        if completed is not None:
            self.progress.update(self.task_id, completed=completed)

    def __exit__(self, *args):
        self.progress.update(self.task_id, completed=self.total)
        time.sleep(0.2)
        self.live.__exit__(*args)


class AnimatedStatus:
    def __init__(self):
        self.console = Console()

    def ok(self, message):
        self.console.print(f"  [bold green]\u2713[/bold green] {message}")

    def fail(self, message):
        self.console.print(f"  [bold red]\u2718[/bold red] {message}")

    def warn(self, message):
        self.console.print(f"  [bold yellow]\u26a0[/bold yellow] {message}")

    def info(self, message):
        self.console.print(f"  [bold green]\u2192[/bold green] {message}")

    def section(self, title):
        self.console.print(f"\n[bold green]\u2550\u2550\u2550 {title} [/bold green]")
