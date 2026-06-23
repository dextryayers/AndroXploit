import time
import os
import sys
import random
import re
import math
import threading
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
    "premium": Spinners.arc,
    "dots": Spinners.dots12,
    "moon": Spinners.moon,
    "earth": Spinners.earth,
    "clock": Spinners.clock,
    "arrow": Spinners.arrow3,
    "toggle": Spinners.toggle7,
    "pulse": Spinners.earth,
    "bounce": Spinners.bouncingBar,
}

RST = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
G1 = "\033[38;5;82m"
G2 = "\033[38;5;46m"
G3 = "\033[38;5;28m"
G4 = "\033[38;5;22m"
G5 = "\033[38;5;64m"
WHT = "\033[38;5;255m"
BRT = "\033[38;5;15m"
YLW = "\033[38;5;226m"
RED = "\033[38;5;196m"
BLU = "\033[38;5;39m"
CYN = "\033[38;5;51m"
MGT = "\033[38;5;201m"
ORG = "\033[38;5;214m"
PNK = "\033[38;5;213m"
BRN = "\033[38;5;130m"
YLG = "\033[38;5;190m"
CLR = "\033[2J\033[H"


def strip(s):
    return re.sub(r'\033\[[0-9;]*m', '', s)


def _ufo_cells(ux, uy, blink, tilt, pulse):
    cells = {}
    t = tilt * 2
    p = pulse
    pp = "◉" if p % 2 == 0 else "◈"

    lines = []
    lines.append((0, G3 + "        ╔══════════╗" + RST))
    lines.append((1, G3 + "       ╔╝" + DIM + "  ┌────┐  " + G3 + "╚╗" + RST))
    if blink:
        lines.append((2, G3 + "       ║" + DIM + "   │ " + YLW + "▄ ▄" + DIM + " │   " + G3 + "║" + RST))
    else:
        lines.append((2, G3 + "       ║" + DIM + "   │ " + BRT + "● ●" + DIM + " │   " + G3 + "║" + RST))
    lines.append((3, G3 + "       ║" + DIM + "   │  " + G2 + "◡" + DIM + "  │   " + G3 + "║" + RST))
    lines.append((4, G3 + "       ║" + DIM + "   ├────┤   " + G3 + "║" + RST))
    lines.append((5, G3 + "      ╔╝" + G4 + "   ██████   " + G3 + "╚╗" + RST))
    lines.append((6, G4 + "     ╔╝ " + G5 + "████████████" + G4 + " ╚╗" + RST))
    lines.append((7, G4 + "    ╔╝ " + G1 + "██████████████" + G4 + " ╚╗" + RST))
    lines.append((8, G1 + "   ╔╝ " + G2 + "████████████████" + G1 + " ╚╗" + RST))
    lines.append((9, G2 + "   ║ " + G1 + "████ " + YLW + pp + " " + pp + " " + pp + G1 + " ████" + G2 + " ║" + RST))
    lines.append((10, G1 + "   ║ " + G3 + "████████████████" + G1 + " ║" + RST))
    lines.append((11, G3 + "   ╚╗ " + G4 + "██████████████" + G3 + " ╔╝" + RST))
    lines.append((12, G3 + "    ╚╗" + G4 + "  ▀▀▀▀▀▀▀▀▀▀  " + G3 + "╔╝" + RST))
    lines.append((13, G3 + "     ╚╗" + "             " + "╔╝" + RST))
    lines.append((14, G3 + "      ╚═══════════════╝" + RST))
    lines.append((15, G4 + "        ▄▄" + "           " + "▄▄" + RST))
    lines.append((16, G3 + "       " + "▄▄▄▄" + "         " + "▄▄▄▄" + RST))

    for dy, line in lines:
        ly = uy + dy
        if ly < 0:
            continue
        lw = len(strip(line))
        centered_x = ux + (26 - lw) // 2
        if centered_x + lw < 0 or centered_x > 400:
            continue
        for ci, ch in enumerate(line):
            cx = centered_x + ci + t
            if cx >= 0:
                cells[(ly, cx)] = ch
    return cells


def _tree_cells(bx, by, variant=0):
    cells = {}
    col = G2 if variant == 0 else G5 if variant == 1 else G3
    tr = G4
    patterns = [
        (0, "   ╔══╗   "),
        (1, "  ╔╝██╚╗  "),
        (2, "  ║ ██ ║  "),
        (3, "  ║ ██ ║  "),
        (4, "  ╚╗  ╔╝  "),
        (5, "   ║██║   "),
        (6, "   ║  ║   "),
    ]
    for dy, p in patterns:
        y = by + dy
        for dx, ch in enumerate(p):
            x = bx + dx
            if ch in "╔╗╚╝═║":
                cells[(y, x)] = tr + ch + RST
            elif ch == "█":
                cells[(y, x)] = col + ch + RST
    return cells


def _chicken_cells(cx, cy, state):
    cells = {}
    col = YLW
    leg = BRN
    if state == 0:
        lines = [
            (0, "  " + col + ".-." + RST + "  "),
            (1, "  " + col + "`o'" + RST + "  "),
            (2, "   " + leg + "│" + RST + "   "),
            (3, "  " + leg + "╱" + RST + " " + leg + "╲" + RST + "  "),
        ]
    else:
        lines = [
            (2, "  " + col + ".-." + RST + "  "),
            (3, "  " + col + "`o'" + RST + "  "),
            (4, "   " + leg + "│" + RST + "   "),
        ]
    for dy, line in lines:
        y = cy + dy
        for dx, ch in enumerate(line):
            x = cx + dx
            cells[(y, x)] = ch
    return cells


def _reuleaux_beam_cells(cx, top_y, H, frame):
    cells = {}
    if H < 2:
        return cells
    w = H
    h_eq = w * 0.8660254
    dh = w - h_eq
    A_y = H
    B_x = -w / 2
    B_y = H - h_eq
    C_x = w / 2
    C_y = H - h_eq
    margin_extra = 0.6

    for dy in range(int(H) + 2):
        y = top_y + dy
        if y < 0:
            continue
        for dx in range(-int(w / 2) - 2, int(w / 2) + 3):
            x = cx + dx
            dA = math.sqrt(dx * dx + (dy - A_y) ** 2)
            dB = math.sqrt((dx - B_x) ** 2 + (dy - B_y) ** 2)
            dC = math.sqrt((dx - C_x) ** 2 + (dy - C_y) ** 2)
            if dA <= w + margin_extra and dB <= w + margin_extra and dC <= w + margin_extra:
                margin = min(w - dA, w - dB, w - dC) + margin_extra
                if margin > w * 0.35:
                    ch = "█"
                    col = WHT
                elif margin > w * 0.2:
                    ch = "▓"
                    col = CYN
                elif margin > w * 0.08:
                    ch = "▒"
                    col = BLU
                else:
                    ch = "░"
                    col = BLU
                if frame % 4 < 2:
                    col = CYN if col == BLU else (WHT if col == CYN else col)
                cells[(y, x)] = col + ch + RST
    return cells


def _explosion_cells(cx, cy, frame, total):
    cells = {}
    progress = frame / total if total > 0 else 1
    r = int(progress * 10) + 1

    for dy in range(-r - 2, r + 3):
        for dx in range(-r - 2, r + 3):
            d = math.sqrt(dx * dx + dy * dy)
            y = cy + dy
            x = cx + dx
            if y < 0 or x < 0:
                continue
            if progress < 0.15:
                if d < r * 0.8:
                    cells[(y, x)] = WHT + "█" + RST
                elif d < r:
                    cells[(y, x)] = YLW + "▓" + RST
            elif progress < 0.35:
                if d < r * 0.3:
                    cells[(y, x)] = YLW + "█" + RST
                elif d < r * 0.6:
                    cells[(y, x)] = ORG + "▓" + RST
                elif d < r:
                    cells[(y, x)] = RED + "▒" + RST
            elif progress < 0.6:
                if d < r * 0.2:
                    cells[(y, x)] = ORG + "▓" + RST
                elif d < r * 0.5:
                    cells[(y, x)] = RED + "▒" + RST
                elif d < r:
                    cells[(y, x)] = RED + "░" + RST
            else:
                if d < r * 0.3:
                    cells[(y, x)] = RED + "░" + RST
                elif d < r * 0.7 and random.random() < 0.5:
                    cells[(y, x)] = G4 + "▒" + RST

    if frame > 3:
        for _ in range(min(int(6 + progress * 20), 30)):
            ang = random.uniform(0, 2 * math.pi)
            dist = random.uniform(r, r + 8 + progress * 5)
            dy = int(dist * math.sin(ang))
            dx = int(dist * math.cos(ang))
            y = cy + dy
            x = cx + dx
            if y < 0 or x < 0:
                continue
            if progress < 0.4:
                cells[(y, x)] = YLW + random.choice(["*", "·", "o"]) + RST
            elif progress < 0.7:
                cells[(y, x)] = ORG + random.choice(["·", ".", "'"]) + RST
            else:
                if random.random() < 0.4:
                    cells[(y, x)] = G4 + "·" + RST

    if frame > total * 0.4:
        for _ in range(5):
            sy = cy - int(r * random.uniform(0.5, 1.5))
            sx = cx + int(random.uniform(-r * 0.5, r * 0.5))
            if sy >= 0 and sx >= 0:
                cells[(sy, sx)] = G4 + "▒" + RST

    return cells


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
        chars = ["·"] * 60 + ["*"] * 8 + ["☆"] * 4 + ["✧"] * 2 + ["+"] * 2 + ["°"] * 2
        for _ in range(count):
            stars.append([
                random.randint(0, cols - 1),
                random.randint(0, rows - 1),
                random.choice(chars),
            ])
        return stars

    def _add_stars(self, cells, stars, frame, cols, rows):
        for star in stars:
            sx = (star[0] + frame // 2) % cols
            sy = star[1]
            sc = star[2]
            if 0 <= sy < rows:
                if sc in ("*", "☆", "✧", "+") and random.random() < 0.25:
                    cells[(sy, sx)] = BRT + sc + RST
                elif sc == "·":
                    cells[(sy, sx)] = DIM + "·" + RST
                elif sc == "°":
                    cells[(sy, sx)] = BLU + "°" + RST
                else:
                    cells[(sy, sx)] = WHT + sc + RST

    def _add_ground(self, cells, frame, cols, rows):
        path_base = rows - 8
        for x in range(cols):
            offset = int(2 * math.sin(x * 0.08 + frame * 0.005))
            py = path_base + offset
            if 0 <= py < rows:
                cells[(py, x)] = BRN + "▒" + RST
            for gy in range(py + 1, rows):
                if gy < rows:
                    if (x + frame * 2) % 7 < 2 and gy < py + 3:
                        cells[(gy, x)] = G3 + "░" + RST
                    else:
                        cells[(gy, x)] = G4 + "▓" + RST
            if py - 1 >= 0:
                cells[(py - 1, x)] = G4 + "▄" + RST

        for x in range(0, cols, 4):
            offset = int(2 * math.sin(x * 0.08 + frame * 0.005))
            py = path_base + offset
            if py - 2 >= 0 and random.random() < 0.008:
                flor = random.choice([G3 + "░" + RST, G5 + "▒" + RST, G2 + "▀" + RST])
                cells[(py - 2, x)] = flor

    def _add_planets(self, cells, frame, cols, rows):
        pd_list = [
            {"x": cols - 14, "y": 2, "c": CYN, "s": 3},
            {"x": 5, "y": 3, "c": ORG, "s": 2},
            {"x": cols // 2 + 12, "y": 4, "c": MGT, "s": 2},
        ]
        for pd in pd_list:
            cx, cy, c, s = pd["x"], pd["y"], pd["c"], pd["s"]
            for dy in range(-s - 1, s + 2):
                for dx in range(-s - 2, s + 3):
                    d2 = dx * dx + dy * dy
                    if d2 <= s * s + 2:
                        dist = math.sqrt(d2)
                        r = s
                        if dist < r * 0.3:
                            shade = "▓"
                        elif dist < r * 0.6:
                            shade = "▒"
                        else:
                            shade = "░"
                        y, x = cy + dy, cx + dx
                        if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                            cells[(y, x)] = c + shade + RST

        sat_x, sat_y = 5, 3
        ring_c = YLW
        for dy in range(-1, 2):
            for dx in range(-6, 7):
                d2 = dx * dx + dy * dy
                if 8 <= d2 <= 14 and abs(dy) <= 1:
                    y, x = sat_y + dy, sat_x + dx
                    if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                        cells[(y, x)] = ring_c + "░" + RST

        moon_cx, moon_cy = cols // 2 + 12, 4
        moon_angle = frame * 0.04
        mx = int(moon_cx + 7 * math.cos(moon_angle))
        my = int(moon_cy + 4 * math.sin(moon_angle))
        if 0 <= my < rows and 0 <= mx < cols and (my, mx) not in cells:
            cells[(my, mx)] = WHT + "●" + RST
            if mx + 1 < cols and (my, mx + 1) not in cells:
                cells[(my, mx + 1)] = DIM + "·" + RST

    def _add_trees(self, cells, frame, cols, rows):
        path_base = rows - 8
        positions = [3, cols // 3, cols // 2 + 6, cols - 10]
        for i, tx in enumerate(positions):
            offset = int(2 * math.sin(tx * 0.08 + frame * 0.005))
            ty = path_base + offset - 7
            if ty >= 0:
                tc = _tree_cells(tx, ty, i % 3)
                for (y, x), val in tc.items():
                    if y < rows and x < cols and (y, x) not in cells:
                        cells[(y, x)] = val

    def fly(self):
        cols, rows = 80, 24
        try:
            import shutil
            cols = max(80, shutil.get_terminal_size().columns)
            rows = max(24, shutil.get_terminal_size().lines)
        except:
            pass

        os.system("clear" if os.name == "posix" else "cls")

        stars = self._make_stars(120, cols, rows)
        chicken_x = cols // 2 - 3
        chicken_y = rows - 11
        peck_timer = 0
        chicken_state = 0

        # --- PHASE 1: Full scene with ground + UFO flyby ---
        for frame in range(100):
            cells = {}
            self._add_stars(cells, stars, frame, cols, rows)
            self._add_planets(cells, frame, cols, rows)
            self._add_ground(cells, frame, cols, rows)
            self._add_trees(cells, frame, cols, rows)

            peck_timer += 1
            if peck_timer < 15:
                chicken_state = 0
            elif peck_timer < 22:
                chicken_state = 1
            elif peck_timer < 30:
                chicken_state = 0
            else:
                peck_timer = 0

            cc = _chicken_cells(chicken_x, chicken_y, chicken_state)
            for (y, x), val in cc.items():
                if y < rows and x < cols and (y, x) not in cells:
                    cells[(y, x)] = val

            blink = (frame % 30) > 27
            tilt = max(0, 3 - max(0, frame - 15) // 5) if frame < 30 else 0
            ux = -30 + frame * 2
            uy = 2 + int(round(1.8 * math.sin(frame * 0.4)))
            if ux < cols + 10:
                ufo_c = _ufo_cells(ux, uy, blink, tilt, frame % 4)
                for (y, x), val in ufo_c.items():
                    if 0 <= y < rows and 0 <= x < cols:
                        cells[(y, x)] = val

            self._render(cells, cols, rows)
            time.sleep(0.026)

        # --- PHASE 2: UFO turns around and approaches chicken ---
        for frame in range(60):
            cells = {}
            self._add_stars(cells, stars, frame, cols, rows)
            self._add_planets(cells, frame, cols, rows)
            self._add_ground(cells, frame, cols, rows)
            self._add_trees(cells, frame, cols, rows)

            peck_timer += 1
            if peck_timer < 12:
                chicken_state = 0
            elif peck_timer < 18:
                chicken_state = 1
            elif peck_timer < 25:
                chicken_state = 0
            else:
                peck_timer = 0

            cc = _chicken_cells(chicken_x, chicken_y, chicken_state)
            for (y, x), val in cc.items():
                if y < rows and x < cols and (y, x) not in cells:
                    cells[(y, x)] = val

            target_x = chicken_x + 3
            start_x = cols + 20
            progress = frame / 60
            ux = int(start_x - (start_x - target_x) * (1 - (1 - progress) ** 3))
            uy = 2 + int(2 * math.sin(frame * 0.5))
            blink = (frame % 35) > 32
            tilt = max(0, int(3 * (1 - progress)))
            ufo_c = _ufo_cells(ux, uy, blink, tilt, frame % 4)
            for (y, x), val in ufo_c.items():
                if 0 <= y < rows and 0 <= x < cols:
                    cells[(y, x)] = val

            self._render(cells, cols, rows)
            time.sleep(0.035)

        # --- PHASE 3: Hover above chicken, Reuleaux beam ---
        for frame in range(55):
            cells = {}
            self._add_stars(cells, stars, frame, cols, rows)
            self._add_planets(cells, frame, cols, rows)
            self._add_ground(cells, frame, cols, rows)
            self._add_trees(cells, frame, cols, rows)

            peck_timer += 1
            if peck_timer < 20:
                chicken_state = 0
            else:
                peck_timer = 0

            cc = _chicken_cells(chicken_x, chicken_y, chicken_state)
            for (y, x), val in cc.items():
                if y < rows and x < cols and (y, x) not in cells:
                    cells[(y, x)] = val

            ux = chicken_x + 3
            uy = 1 + int(round(1.5 * math.sin(frame * 0.3)))
            blink = (frame % 30) > 27
            ufo_c = _ufo_cells(ux, uy, blink, 0, frame % 4)
            for (y, x), val in ufo_c.items():
                if 0 <= y < rows and 0 <= x < cols:
                    cells[(y, x)] = val

            beam_top = uy + 16
            beam_bottom = chicken_y
            H = beam_bottom - beam_top
            if H > 2 and frame > 5:
                bc = _reuleaux_beam_cells(ux + 2, beam_top, H, frame)
                for (y, x), val in bc.items():
                    if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                        cells[(y, x)] = val

            self._render(cells, cols, rows)
            time.sleep(0.04)

        # --- PHASE 4: Chicken abduction with Reuleaux beam ---
        for frame in range(55):
            cells = {}
            self._add_stars(cells, stars, frame, cols, rows)
            self._add_planets(cells, frame, cols, rows)
            self._add_ground(cells, frame, cols, rows)
            self._add_trees(cells, frame, cols, rows)

            progress = frame / 55
            lifted = int(progress * (chicken_y - 3))
            lifted_y = chicken_y - lifted

            if lifted_y > 3:
                cc = _chicken_cells(chicken_x, lifted_y, 0)
                for (y, x), val in cc.items():
                    if y < rows and x < cols and (y, x) not in cells:
                        cells[(y, x)] = val

            ux = chicken_x + 3
            uy = 1 + int(round(1.5 * math.sin(frame * 0.25)))
            ufo_c = _ufo_cells(ux, uy, False, 0, frame % 4)
            for (y, x), val in ufo_c.items():
                if 0 <= y < rows and 0 <= x < cols:
                    cells[(y, x)] = val

            beam_top = uy + 16
            beam_bottom = lifted_y
            H = beam_bottom - beam_top
            if H > 2:
                bc = _reuleaux_beam_cells(ux + 2, beam_top, H, frame)
                for (y, x), val in bc.items():
                    if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                        cells[(y, x)] = val

            if lifted_y > 3 and frame % 6 < 3:
                cc = _chicken_cells(chicken_x, lifted_y + 1, 1)
                for (y, x), val in cc.items():
                    if y < rows and x < cols and (y, x) not in cells:
                        cells[(y, x)] = val

            self._render(cells, cols, rows)
            time.sleep(0.04)

        # --- PHASE 5: UFO escapes and crashes ---
        for frame in range(65):
            cells = {}
            self._add_stars(cells, stars, frame, cols, rows)
            self._add_planets(cells, frame, cols, rows)
            self._add_ground(cells, frame, cols, rows)
            self._add_trees(cells, frame, cols, rows)

            if frame < 30:
                ux = chicken_x + 3 + frame * 3
                uy = 2 + int(2 * math.sin(frame * 0.4))
                tilt = min(4, frame // 7)
                ufo_c = _ufo_cells(ux, uy, False, tilt, frame % 4)
                for (y, x), val in ufo_c.items():
                    if 0 <= y < rows and 0 <= x < cols:
                        cells[(y, x)] = val
            elif frame < 35:
                crash_x = cols - 12
                crash_y = rows - 11
                ufo_c = _ufo_cells(crash_x, crash_y, True, 5, frame % 4)
                for (y, x), val in ufo_c.items():
                    if 0 <= y < rows and 0 <= x < cols:
                        cells[(y, x)] = val

            self._render(cells, cols, rows)
            time.sleep(0.035)

        # --- PHASE 6: EXPLOSION ---
        total_explosion = 35
        crash_x = cols - 12
        crash_y = rows - 11

        expl_debris = []
        for _ in range(40):
            ang = random.uniform(0, 2 * math.pi)
            spd = random.uniform(1, 5)
            expl_debris.append([0.0, 0.0, ang, spd])

        for frame in range(total_explosion):
            cells = {}
            self._add_stars(cells, stars, frame, cols, rows)
            self._add_ground(cells, 0, cols, rows)

            ec = _explosion_cells(crash_x, crash_y, frame, total_explosion)
            for (y, x), val in ec.items():
                if 0 <= y < rows and 0 <= x < cols and (y, x) not in cells:
                    cells[(y, x)] = val

            for ed in expl_debris:
                ed[0] += ed[3] * 0.15 * math.cos(ed[2])
                ed[1] += ed[3] * 0.15 * math.sin(ed[2])
                ey = crash_y + int(ed[1])
                ex = crash_x + int(ed[0])
                if 0 <= ey < rows and 0 <= ex < cols and (ey, ex) not in cells:
                    if frame < 15:
                        cells[(ey, ex)] = YLW + "·" + RST
                    elif frame < 25:
                        cells[(ey, ex)] = ORG + "·" + RST
                    else:
                        cells[(ey, ex)] = RED + "·" + RST

            self._render(cells, cols, rows)
            time.sleep(0.065)

        # --- PHASE 7: Fade to logo ---
        for flash in range(6):
            out = CLR
            block = "▓" if flash % 2 == 0 else " "
            for r in range(rows):
                for c in range(cols):
                    out += ORG + block + RST
                out += "\n"
            sys.stdout.write(out)
            sys.stdout.flush()
            time.sleep(0.08)

        self._landing(cols, rows)

    def _landing(self, cols, rows):
        center_x = max(2, (cols - 62) // 2)
        pad = " " * center_x

        for flash in range(5):
            out = CLR
            block = "██" if flash % 2 == 0 else "  "
            for r in range(rows):
                out += pad + WHT + block * 25 + RST + "\n"
            sys.stdout.write(out)
            sys.stdout.flush()
            time.sleep(0.07)

        time.sleep(0.1)

        import pyfiglet
        name_lines = pyfiglet.figlet_format("AndroXploit", font="big").splitlines()

        box_w = 56
        b_ln = "═" * box_w
        title = "ANDROID PENTEST FRAMEWORK V1.1"
        byline = "By: AniipID"
        tl = (box_w - len(title)) // 2
        tr = box_w - len(title) - tl
        bl = (box_w - len(byline)) // 2
        br = box_w - len(byline) - bl

        for f in range(10):
            alpha = (f + 1) / 10
            cv = int(82 + (46 - 82) * alpha)
            c = f"\033[38;5;{cv}m"

            out = CLR
            for line in name_lines:
                out += pad + c + line + RST + "\n"
            out += "\n"
            out += pad + c + "╔" + b_ln + "╗" + RST + "\n"
            out += pad + c + "║" + RST + " " * tl + BOLD + G2 + title + RST + " " * tr + c + "║" + RST + "\n"
            out += pad + c + "║" + RST + " " * bl + DIM + G3 + byline + RST + " " * br + c + "║" + RST + "\n"
            out += pad + c + "╚" + b_ln + "╝" + RST + "\n"

            sys.stdout.write(out)
            sys.stdout.flush()
            time.sleep(0.04)

        time.sleep(0.5)


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
        progress = Progress(
            SpinnerColumn(spinner_name="dots12", style="green"),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(complete_style="green", finished_style="green", pulse_style="green"),
            MofNCompleteColumn(),
            TimeElapsedColumn(),
            TimeRemainingColumn(),
            console=console,
            transient=transient,
        )
        return progress

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
            TimeElapsedColumn(),
            TimeRemainingColumn(),
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
