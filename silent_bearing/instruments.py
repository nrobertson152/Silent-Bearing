"""Hydrophone scope, plot table, brass dials and status bars."""
import math

import pygame

from .ui import THEME, font, text
from .util import KN, RAD, adiff, bearing, clamp, dist, lerp_color, p3


# ------------------------------------------------------------- hydrophones
def draw_sonar(surf, rect, world, t):
    s = world.sub
    cx, cy = rect.centerx, rect.centery + 6
    R = min(rect.w, rect.h - 24) // 2 - 16
    face_dark, face = (4, 12, 9), (9, 26, 19)
    pygame.draw.circle(surf, THEME.seam, (cx, cy), R + 8)
    pygame.draw.circle(surf, THEME.brass_lo, (cx, cy), R + 6, 3)
    pygame.draw.circle(surf, face_dark, (cx, cy), R)
    for i in range(6, 0, -1):
        pygame.draw.circle(surf, lerp_color(face_dark, face, i / 6), (cx, cy), int(R * i / 7))
    dim = (34, 74, 52)
    for f in (0.33, 0.66):
        pygame.draw.circle(surf, dim, (cx, cy), int(R * f), 1)
    for d in range(0, 360, 10):
        a = d * RAD
        r0 = R - (9 if d % 30 == 0 else 4)
        pygame.draw.line(surf, dim if d % 30 else (70, 130, 96),
                         (cx + math.sin(a) * r0, cy - math.cos(a) * r0),
                         (cx + math.sin(a) * R, cy - math.cos(a) * R), 1)
    fl = font(11, "mono")
    for d in range(0, 360, 30):
        a = d * RAD
        lbl = "BOW" if d == 0 else "STN" if d == 180 else f"{d:03d}"
        text(surf, lbl, fl, (90, 150, 112), (cx + math.sin(a) * (R - 20), cy - math.cos(a) * (R - 20)), "center")

    # Training sweep.
    sw = pygame.Surface((rect.w, rect.h), pygame.SRCALPHA)
    ang = (t * 50) % 360
    for k in range(12):
        a0 = (ang - k * 2.5) * RAD
        a1 = (ang - (k + 1) * 2.5) * RAD
        pts = [(cx - rect.x, cy - rect.y),
               (cx - rect.x + math.sin(a0) * R, cy - rect.y - math.cos(a0) * R),
               (cx - rect.x + math.sin(a1) * R, cy - rect.y - math.cos(a1) * R)]
        pygame.draw.polygon(sw, (120, 230, 160, max(0, 46 - k * 4)), pts)
    surf.blit(sw, rect.topleft)

    own_noise = abs(s.spd) > 6
    flabel = font(12, "mono", True)
    for sh in world.ships:
        if not sh.heard:
            continue
        r = dist(s.x, s.y, sh.x, sh.y)
        b = bearing(s.x, s.y, sh.x, sh.y)
        rel = adiff(b, s.hdg)
        strength = clamp((0.35 + sh.spd / 14) * (4000 / (r + 1500)), 0.08, 1.0)
        if own_noise:
            strength *= 0.55
        a = rel * RAD
        dx, dy = math.sin(a), -math.cos(a)
        r0, r1 = R * 0.12, R * (0.25 + 0.73 * strength)
        if sh.hunting:
            col = lerp_color((60, 40, 10), THEME.amber, 0.4 + 0.6 * strength)
        elif sh.hp <= 0:
            col = lerp_color((40, 40, 40), (200, 200, 200), strength)
        else:
            col = lerp_color((30, 70, 46), THEME.phos, 0.3 + 0.7 * strength)
        pygame.draw.line(surf, col, (cx + dx * r0, cy + dy * r0), (cx + dx * r1, cy + dy * r1), 3)
        pygame.draw.circle(surf, col, (int(cx + dx * r1), int(cy + dy * r1)), 4)
        if sh.is_target or sh.hunting:
            text(surf, p3(b), flabel, col, (cx + dx * (r1 + 14), cy + dy * (r1 + 12)), "center")
    for tp in world.torps:
        a = adiff(bearing(s.x, s.y, tp.x, tp.y), s.hdg) * RAD
        rr = R * clamp(0.2 + dist(s.x, s.y, tp.x, tp.y) / 6000, 0.2, 0.95)
        pygame.draw.circle(surf, (230, 120, 90), (int(cx + math.sin(a) * rr), int(cy - math.cos(a) * rr)), 2)
    if world.ping_flash > 0:
        pygame.draw.circle(surf, lerp_color(face, THEME.amber, world.ping_flash), (cx, cy),
                           int(R * (1.05 - world.ping_flash * 0.5)), 2)
        text(surf, "ACTIVE SONAR ON US", font(13, "mono", True), THEME.amber, (cx, cy + R * 0.5), "center")
    pygame.draw.polygon(surf, THEME.brass, [(cx, cy - R - 2), (cx - 6, cy - R - 12), (cx + 6, cy - R - 12)])
    pygame.draw.circle(surf, THEME.phos, (cx, cy), 3)
    status = "OWN NOISE HIGH: slow down to listen" if own_noise else "Strobe length shows loudness, not range"
    text(surf, status, font(12), THEME.amber if own_noise else THEME.muted, (rect.centerx, rect.bottom - 4), "midbottom")


# --------------------------------------------------------------- plot table
PAPER = (206, 208, 192)
PAPER_DK = (188, 192, 176)
INK = (36, 44, 48)
RED_INK = (156, 44, 32)


def draw_chart(surf, rect, world, radius):
    s = world.sub
    surf.fill(PAPER, rect)
    old = surf.get_clip()
    surf.set_clip(rect)
    cx, cy = rect.centerx, rect.centery
    ppm = (min(rect.w, rect.h) / 2 - 8) / radius

    def W(x, y):
        return (cx + (x - s.x) * ppm, cy - (y - s.y) * ppm)

    g = 1000 if radius <= 6000 else 2000
    x0 = math.floor((s.x - rect.w / ppm) / g) * g
    y0 = math.floor((s.y - rect.h / ppm) / g) * g
    x = x0
    while x < s.x + rect.w / ppm:
        X = W(x, 0)[0]
        pygame.draw.line(surf, PAPER_DK, (X, rect.top), (X, rect.bottom))
        x += g
    y = y0
    while y < s.y + rect.h / ppm:
        Y = W(0, y)[1]
        pygame.draw.line(surf, PAPER_DK, (rect.left, Y), (rect.right, Y))
        y += g

    # Torpedo range ring.
    rr = world.nat.torp.range_m * ppm
    for k in range(0, 72, 2):
        pygame.draw.arc(surf, (150, 120, 96), pygame.Rect(cx - rr, cy - rr, 2 * rr, 2 * rr),
                        k * 5 * RAD, (k * 5 + 5) * RAD, 1)

    # Hydrophone bearing lines.
    far = radius * 1.5
    for sh in world.ships:
        if sh.heard:
            b = bearing(s.x, s.y, sh.x, sh.y) * RAD
            col = (190, 120, 40) if sh.hunting else (126, 136, 150)
            pygame.draw.line(surf, col, (cx, cy), (cx + math.sin(b) * far * ppm, cy - math.cos(b) * far * ppm), 1)

    # Depth charge bursts.
    for f in world.fx:
        if f.kind == "dc":
            a = world.t - f.t0
            p = W(f.x, f.y)
            pygame.draw.circle(surf, (200, 110, 40), (int(p[0]), int(p[1])), int(4 + a * 5), 1)
        elif f.kind == "boom":
            p = W(f.x, f.y)
            pygame.draw.circle(surf, RED_INK, (int(p[0]), int(p[1])), int(6 + (world.t - f.t0) * 4), 2)

    # Plotted contacts.
    fl = font(12, "ui", True)
    fs = font(11, "mono")
    for sh in world.ships:
        if sh.plot is None:
            continue
        px, py, ph, ps, pt = sh.plot
        age = world.t - pt
        X, Y = W(px, py)
        fresh = age < 4
        col = RED_INK if sh.is_target else INK
        if sh.dead or sh.hp <= 0:
            pygame.draw.line(surf, col, (X - 6, Y - 6), (X + 6, Y + 6), 2)
            pygame.draw.line(surf, col, (X - 6, Y + 6), (X + 6, Y - 6), 2)
        else:
            vx = math.sin(ph * RAD) * ps * KN * 120 * ppm
            vy = -math.cos(ph * RAD) * ps * KN * 120 * ppm
            pygame.draw.line(surf, col, (X, Y), (X + vx, Y + vy), 1)
            if sh.is_target:
                pts = [(X, Y - 7), (X + 7, Y), (X, Y + 7), (X - 7, Y)]
            else:
                a = ph * RAD
                pts = [(X + math.sin(a) * 7, Y - math.cos(a) * 7),
                       (X + math.sin(a + 2.5) * 5, Y - math.cos(a + 2.5) * 5),
                       (X + math.sin(a - 2.5) * 5, Y - math.cos(a - 2.5) * 5)]
            pygame.draw.polygon(surf, col, pts, 0 if fresh else 1)
        name = sh.short if sh.is_target else sh.short
        r = text(surf, name, fl, col, (X + 9, Y - 8))
        if not fresh:
            m, sec = divmod(int(age), 60)
            text(surf, f"seen -{m}:{sec:02d}", fs, (110, 110, 100), (r.left, r.bottom - 1))

    # Own torpedoes.
    for tp in world.torps:
        pts = [W(x, y) for x, y in tp.trail] + [W(tp.x, tp.y)]
        if len(pts) > 1:
            pygame.draw.lines(surf, RED_INK, False, pts, 1)
        X, Y = W(tp.x, tp.y)
        pygame.draw.circle(surf, RED_INK, (int(X), int(Y)), 3)

    # Own boat and projected track.
    a = s.hdg * RAD
    for k in range(0, 10, 2):
        d0, d1 = k * 200 * ppm, (k + 1) * 200 * ppm
        pygame.draw.line(surf, (40, 80, 110), (cx + math.sin(a) * d0, cy - math.cos(a) * d0),
                         (cx + math.sin(a) * d1, cy - math.cos(a) * d1), 1)
    pts = [(cx + math.sin(a) * 10, cy - math.cos(a) * 10),
           (cx + math.sin(a + 2.6) * 7, cy - math.cos(a + 2.6) * 7),
           (cx + math.sin(a - 2.6) * 7, cy - math.cos(a - 2.6) * 7)]
    pygame.draw.polygon(surf, (24, 70, 100), pts)
    if world.lock is not None and world.lock.alive:
        sol = world.solution()
        if sol:
            b = sol["hdg"] * RAD
            L = sol["run"] * ppm
            pygame.draw.line(surf, (40, 120, 60), (cx, cy), (cx + math.sin(b) * L, cy - math.cos(b) * L), 1)

    # Margins.
    text(surf, "N", font(14, "ui", True), INK, (rect.right - 16, rect.top + 6), "midtop")
    pygame.draw.polygon(surf, INK, [(rect.right - 16, rect.top + 22), (rect.right - 20, rect.top + 32),
                                    (rect.right - 12, rect.top + 32)])
    text(surf, f"radius {radius // 1000} km   grid {g // 1000} km   dashed: torpedo range",
         font(11, "mono"), (90, 92, 84), (rect.left + 6, rect.bottom - 4), "bottomleft")
    surf.set_clip(old)
    pygame.draw.rect(surf, THEME.seam, rect, 2)


# --------------------------------------------------------------- brass dials
def _bezel(surf, c, R):
    pygame.draw.circle(surf, THEME.seam, (c[0], c[1] + 3), R + 1)
    pygame.draw.circle(surf, THEME.brass_lo, c, R)
    pygame.draw.circle(surf, THEME.brass, c, R - 2)
    pygame.draw.circle(surf, THEME.brass_lo, c, R - 6)
    pygame.draw.circle(surf, THEME.dial, c, R - 8)


def _arc_pts(c, r, a0, a1, n=24):
    return [(c[0] + math.cos(a0 + (a1 - a0) * i / n) * r, c[1] + math.sin(a0 + (a1 - a0) * i / n) * r)
            for i in range(n + 1)]


def draw_dial(surf, c, R, value, vmin, vmax, label, readout, major, minor, red_from=None, order=None,
              unit=""):
    _bezel(surf, c, R)
    Rf = R - 8
    a0, sweep = 135 * RAD, 270 * RAD

    def ang(v):
        return a0 + (clamp(v, vmin, vmax) - vmin) / (vmax - vmin) * sweep

    if red_from is not None:
        outer = _arc_pts(c, Rf - 3, ang(red_from), ang(vmax))
        inner = _arc_pts(c, Rf - 11, ang(red_from), ang(vmax))[::-1]
        pygame.draw.polygon(surf, (196, 60, 42), outer + inner)
    v = vmin
    fn = font(11, "ui", True)
    while v <= vmax + 1e-6:
        a = ang(v)
        is_major = abs((v - vmin) / major - round((v - vmin) / major)) < 1e-6
        r0 = Rf - (12 if is_major else 7)
        pygame.draw.line(surf, THEME.ink, (c[0] + math.cos(a) * r0, c[1] + math.sin(a) * r0),
                         (c[0] + math.cos(a) * (Rf - 3), c[1] + math.sin(a) * (Rf - 3)), 2 if is_major else 1)
        if is_major:
            text(surf, f"{v:g}", fn, THEME.ink, (c[0] + math.cos(a) * (Rf - 22), c[1] + math.sin(a) * (Rf - 22)),
                 "center")
        v += minor
    text(surf, label, font(10, "ui", True), (110, 98, 76), (c[0], c[1] + 15), "center")
    if order is not None:
        a = ang(order)
        tip = (c[0] + math.cos(a) * (Rf - 2), c[1] + math.sin(a) * (Rf - 2))
        b1 = (c[0] + math.cos(a - 0.08) * (Rf + 6), c[1] + math.sin(a - 0.08) * (Rf + 6))
        b2 = (c[0] + math.cos(a + 0.08) * (Rf + 6), c[1] + math.sin(a + 0.08) * (Rf + 6))
        pygame.draw.polygon(surf, (40, 110, 70), [tip, b1, b2])
    box = pygame.Rect(0, 0, 46, 17)
    box.center = (c[0], c[1] + Rf * 0.70)
    pygame.draw.rect(surf, (24, 22, 18), box, border_radius=2)
    text(surf, readout, font(13, "mono", True), THEME.amber, box.center, "center")
    a = ang(value)
    tip = (c[0] + math.cos(a) * (Rf - 6), c[1] + math.sin(a) * (Rf - 6))
    tail = (c[0] - math.cos(a) * 10, c[1] - math.sin(a) * 10)
    side = (math.cos(a + math.pi / 2) * 3, math.sin(a + math.pi / 2) * 3)
    pygame.draw.polygon(surf, (24, 22, 20), [tip, (tail[0] + side[0], tail[1] + side[1]),
                                             (tail[0] - side[0], tail[1] - side[1])])
    pygame.draw.circle(surf, THEME.brass, c, 5)
    pygame.draw.circle(surf, THEME.brass_lo, c, 5, 1)


def draw_compass(surf, c, R, hdg, rudder):
    _bezel(surf, c, R)
    Rf = R - 8
    fn = font(12, "ui", True)
    for d in range(0, 360, 5):
        a = (d - hdg - 90) * RAD
        big = d % 30 == 0
        r0 = Rf - (11 if big else 5 if d % 10 == 0 else 3)
        pygame.draw.line(surf, THEME.ink, (c[0] + math.cos(a) * r0, c[1] + math.sin(a) * r0),
                         (c[0] + math.cos(a) * (Rf - 2), c[1] + math.sin(a) * (Rf - 2)), 2 if big else 1)
        if big:
            lbl = {0: "N", 90: "E", 180: "S", 270: "W"}.get(d, str(d // 10))
            col = (170, 40, 30) if d == 0 else THEME.ink
            text(surf, lbl, fn, col, (c[0] + math.cos(a) * (Rf - 21), c[1] + math.sin(a) * (Rf - 21)), "center")
    pygame.draw.polygon(surf, (180, 50, 36), [(c[0], c[1] - Rf + 1), (c[0] - 5, c[1] - Rf - 7), (c[0] + 5, c[1] - Rf - 7)])
    pygame.draw.line(surf, (180, 50, 36), (c[0], c[1] - Rf + 2), (c[0], c[1] - Rf + 16), 2)
    # Rudder angle indicator.
    ra = (90 - rudder * 1.6) * RAD
    pygame.draw.arc(surf, (120, 108, 86), pygame.Rect(c[0] - 26, c[1] - 26, 52, 52), 210 * RAD, 330 * RAD, 1)
    pygame.draw.line(surf, (40, 110, 70), c, (c[0] + math.cos(ra) * 26, c[1] + math.sin(ra) * 26), 3)
    pygame.draw.circle(surf, THEME.brass, c, 5)
    box = pygame.Rect(0, 0, 44, 18)
    box.center = (c[0], c[1] - 18)
    pygame.draw.rect(surf, (24, 22, 18), box, border_radius=2)
    text(surf, p3(hdg), font(13, "mono", True), THEME.amber, box.center, "center")


def draw_bar(surf, rect, frac, label, color, value):
    t = THEME
    text(surf, label.upper(), font(11, "ui", True), t.muted, (rect.left, rect.top))
    text(surf, value, font(12, "mono", True), color, (rect.right, rect.top - 1), "topright")
    bar = pygame.Rect(rect.left, rect.top + 16, rect.w, 10)
    pygame.draw.rect(surf, t.seam, bar, border_radius=2)
    fill = bar.inflate(-2, -2)
    fill.w = int(fill.w * clamp(frac, 0, 1))
    if fill.w > 0:
        pygame.draw.rect(surf, color, fill, border_radius=2)
    for k in range(1, 10):
        x = bar.left + bar.w * k / 10
        pygame.draw.line(surf, t.seam, (x, bar.top + 1), (x, bar.bottom - 2))
