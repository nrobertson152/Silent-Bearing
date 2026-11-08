"""The attack periscope: horizon, sea state, ship silhouettes and the reticle."""
import math
import random

import pygame

from .ui import THEME, font, text
from .util import RAD, adiff, bearing, clamp, dist, lerp_color, p3, wrap
from .world import ARM_DIST, PERI_MAX

PAL = {
    "day": dict(sky_top=(93, 127, 147), sky_hor=(197, 211, 210), sea_hor=(84, 106, 112),
                sea_bot=(16, 34, 40), ship=(54, 64, 70), reticle=(16, 18, 18), wave_hi=(176, 194, 194)),
    "dusk": dict(sky_top=(38, 46, 78), sky_hor=(214, 150, 102), sea_hor=(74, 64, 70),
                 sea_bot=(12, 14, 20), ship=(24, 24, 32), reticle=(22, 16, 18), wave_hi=(206, 152, 118)),
    "night": dict(sky_top=(3, 6, 11), sky_hor=(36, 50, 66), sea_hor=(16, 24, 32),
                  sea_bot=(2, 4, 6), ship=(4, 7, 10), reticle=(132, 176, 146), wave_hi=(70, 88, 104)),
}

LOW_FOV = 30.0
HIGH_FOV = 7.5


def fov_of(sub):
    return HIGH_FOV if sub.zoom else LOW_FOV


# Silhouettes. u runs 0 (bow) to 1 (stern); heights are metres above the waterline.
def profile(sh):
    t = sh.type
    if t == "bb":
        hull = [(0, 0), (0, 11), (0.07, 9.5), (0.5, 8), (1, 7.5), (1, 0)]
        rects = [(0.17, 0.23, 8.5, 13.5), (0.24, 0.30, 10, 16), (0.47, 0.54, 8, 25),
                 (0.56, 0.63, 8, 18), (0.585, 0.60, 18, 32), (0.67, 0.73, 10, 16), (0.75, 0.81, 8.5, 13.5)]
        if sh.nation == "jp":
            rects += [(0.32, 0.45, 8, 24), (0.33, 0.44, 24, 30), (0.345, 0.43, 30, 36),
                      (0.355, 0.415, 36, 42), (0.37, 0.40, 42, 50)]
        else:
            rects += [(0.31, 0.45, 8, 22), (0.34, 0.42, 22, 34), (0.365, 0.395, 34, 44)]
        guns = [(0.17, 12, -0.07), (0.24, 14, -0.07), (0.73, 14, 0.07), (0.81, 12, 0.07)]
    elif t == "cv":
        hull = [(0, 0), (0, 15), (0.04, 16.5), (1, 16.5), (1, 0)]
        rects = [(0.0, 1.0, 16.5, 18.5), (0.55, 0.66, 18.5, 28), (0.57, 0.64, 28, 34), (0.60, 0.61, 28, 42)]
        guns = []
    elif t == "ca":
        hull = [(0, 0), (0, 9.5), (0.1, 8), (0.5, 7), (1, 6), (1, 0)]
        rects = [(0.15, 0.21, 7.5, 11.5), (0.22, 0.28, 8.5, 13), (0.29, 0.39, 7, 20), (0.33, 0.35, 20, 32),
                 (0.42, 0.47, 7, 21), (0.50, 0.55, 7, 19), (0.60, 0.61, 7, 26), (0.70, 0.76, 8.5, 12.5),
                 (0.78, 0.84, 7.5, 11.5)]
        guns = [(0.15, 10, -0.06), (0.22, 11.5, -0.06), (0.76, 11, 0.06), (0.84, 10, 0.06)]
    else:
        hull = [(0, 0), (0, 7.5), (0.12, 6), (0.5, 5), (1, 4.5), (1, 0)]
        rects = [(0.12, 0.17, 6, 9), (0.20, 0.30, 5.5, 12), (0.245, 0.255, 12, 22), (0.36, 0.42, 5, 14),
                 (0.46, 0.52, 5, 13), (0.56, 0.66, 5, 7), (0.75, 0.80, 5, 8), (0.85, 0.90, 4.8, 7.8)]
        guns = [(0.12, 8, -0.05), (0.90, 7, 0.05)]
    return hull, rects, guns


class Scope:
    def __init__(self, size):
        self.w, self.h = size
        self.surf = pygame.Surface(size)
        self.cx, self.cy = self.w / 2, self.h / 2
        self.rx, self.ry = self.w * 0.49, self.h * 0.47
        self.mask = self._make_mask()
        self.vignette = self._make_vignette()
        self._grads = {}
        self.reduced_motion = False
        self.snow = [(random.random(), random.random(), random.uniform(0.5, 1.6)) for _ in range(90)]

    @property
    def ppd(self):
        return (2 * self.rx) / LOW_FOV

    def _ellipse_rect(self, inset=0):
        return pygame.Rect(int(self.cx - self.rx + inset), int(self.cy - self.ry + inset),
                           int(2 * (self.rx - inset)), int(2 * (self.ry - inset)))

    def _make_mask(self):
        m = pygame.Surface((self.w, self.h), pygame.SRCALPHA)
        m.fill((7, 9, 10, 255))
        pygame.draw.ellipse(m, (0, 0, 0, 0), self._ellipse_rect())
        pygame.draw.ellipse(m, (0, 0, 0, 255), self._ellipse_rect(-2), 5)
        pygame.draw.ellipse(m, (60, 52, 36, 255), self._ellipse_rect(-6), 2)
        return m

    def _make_vignette(self):
        # Concentric rings darken toward the rim of the lens.
        steps = 28
        ring = pygame.Surface((self.w, self.h), pygame.SRCALPHA)
        for i in range(steps):
            f = i / (steps - 1)            # 0 centre -> 1 rim
            inset = int((1 - f) * min(self.rx, self.ry) * 0.45)
            a = int(190 * f ** 3)
            pygame.draw.ellipse(ring, (0, 0, 0, a), self._ellipse_rect(inset), 6)
        return ring

    def _grad(self, tod):
        g = self._grads.get(tod)
        if g is None:
            p = PAL[tod]
            g = pygame.Surface((1, self.h * 2))
            for y in range(self.h * 2):
                if y < self.h:
                    f = (y / self.h) ** 1.6
                    c = lerp_color(p["sky_top"], p["sky_hor"], f)
                else:
                    f = ((y - self.h) / self.h) ** 0.7
                    c = lerp_color(p["sea_hor"], p["sea_bot"], f)
                g.set_at((0, y), c)
            g = pygame.transform.scale(g, (self.w, self.h * 2))
            self._grads[tod] = g
        return g

    # ------------------------------------------------------------------ draw
    def draw(self, world, t):
        S = self.surf
        s = world.sub
        if s.can_see:
            self._draw_view(world, t)
        else:
            self._draw_housed(world, t)
        S.blit(self.vignette, (0, 0))
        S.blit(self.mask, (0, 0))
        return S

    def _draw_housed(self, world, t):
        S = self.surf
        s = world.sub
        for sh in world.ships:
            sh.box = None
        if s.depth > PERI_MAX:
            top, bot = (8, 30, 34), (2, 8, 10)
        else:
            top, bot = (24, 28, 30), (10, 12, 13)
        for y in range(0, self.h, 4):
            pygame.draw.rect(S, lerp_color(top, bot, y / self.h), (0, y, self.w, 4))
        if s.depth > PERI_MAX:
            for (x0, y0, sp) in self.snow:
                x = (x0 * self.w + math.sin(t * 0.3 + y0 * 9) * 8) % self.w
                y = (y0 * self.h - t * 6 * sp) % self.h
                pygame.draw.circle(S, (60, 100, 104), (int(x), int(y)), 1)
            l1 = "PERISCOPE HOUSED"
            l2 = f"Keel depth {s.depth:.0f} m. Come up to 12 m to raise the scope."
        else:
            l1 = "PERISCOPE DOWN"
            l2 = "Press P or Raise scope to look."
        c = (150, 180, 170) if s.depth > PERI_MAX else THEME.muted
        text(S, l1, font(30, "display", True), c, (self.cx, self.cy - 16), "center")
        text(S, l2, font(16), c, (self.cx, self.cy + 18), "center")

    def _draw_view(self, world, t):
        S = self.surf
        s = world.sub
        pal = PAL[world.tod]
        surfaced = s.surfaced
        fov = fov_of(s)
        ppd = (2 * self.rx) / fov
        view = wrap(s.hdg + s.scope_rel)
        eye = 9.0 if surfaced else 1.6
        calm = 0.25 if self.reduced_motion else 1.0
        if surfaced:
            bob = math.sin(t * 0.8) * 3 * calm
        else:
            bob = (math.sin(t * 0.9) * 4 + math.sin(t * 2.1) * 1.5) * calm
        jx = jy = 0.0
        if world.shake > 0:
            jx = random.uniform(-1, 1) * world.shake * 7
            jy = random.uniform(-1, 1) * world.shake * 7
        hy = self.cy + bob + jy
        S.blit(self._grad(world.tod), (jx, hy - self.h))

        def sx_of(b):
            return self.cx + adiff(b, view) * ppd + jx

        self._celestial(S, world, pal, sx_of, hy, ppd)

        # Ships, far to near.
        order = sorted((sh for sh in world.ships if not sh.dead),
                       key=lambda sh: -dist(s.x, s.y, sh.x, sh.y))
        self._labels = []
        for sh in order:
            sh.box = None
            r = dist(s.x, s.y, sh.x, sh.y)
            if r > world.vis or r < 30:
                continue
            b = bearing(s.x, s.y, sh.x, sh.y)
            rel = adiff(b, view)
            ang_half = math.degrees(sh.length / 2 / r)
            if abs(rel) > fov / 2 + ang_half + 1:
                continue
            ppm = ppd * 57.2958 / r
            wy = hy + ppm * eye
            fade = clamp(1 - r / world.vis, 0, 1)
            col = lerp_color(pal["sky_hor"], pal["ship"], 0.28 + 0.72 * fade ** 0.6)
            self._draw_ship(S, sh, b, sx_of(b), wy, ppm, col)
            if sh.box:
                self._label(S, world, sh, col)

        self._fx(S, world, sx_of, hy, ppd, eye)
        self._waves(S, pal, hy, ppd, view, t, jx)
        self._wakes(S, world, sx_of, hy, ppd, eye, pal)
        if not surfaced and s.depth > 11:
            w = math.sin(t * 0.53) * math.sin(t * 1.31)
            wash = clamp((w - 0.55) / 0.45, 0, 1) * clamp((s.depth - 11) / 3.5, 0, 1)
            if wash > 0:
                ov = pygame.Surface((self.w, int(self.h * 0.9 * wash) + 1), pygame.SRCALPHA)
                ov.fill((*pal["sea_hor"], 170))
                S.blit(ov, (0, self.h - ov.get_height()))
        if not surfaced and abs(s.spd) > 5:
            n = int((abs(s.spd) - 5) * 14)
            for _ in range(n):
                x = random.uniform(self.cx - self.rx, self.cx + self.rx)
                y = self.h - random.uniform(0, 60) * (abs(s.spd) / 8)
                pygame.draw.circle(S, pal["wave_hi"], (int(x), int(y)), random.randint(1, 3))
        self._reticle(S, world, pal, view, ppd, fov)

    def _celestial(self, S, world, pal, sx_of, hy, ppd):
        if world.tod == "night":
            x = sx_of(210)
            y = hy - 9 * ppd
            if -60 < x < self.w + 60:
                pygame.draw.circle(S, (196, 204, 196), (int(x), int(y)), max(2, int(0.5 * ppd)))
                for i in range(14):
                    yy = hy + 3 + i * i * 1.4
                    ww = 4 + i * 3
                    pygame.draw.line(S, (54, 66, 74), (x - ww, yy), (x + ww * 0.6, yy), 1)
        elif world.tod == "dusk":
            x = sx_of(258)
            if -200 < x < self.w + 200:
                for i in range(6, 0, -1):
                    pygame.draw.circle(S, lerp_color(pal["sky_hor"], (255, 214, 150), 1 - i / 7),
                                       (int(x), int(hy - 0.6 * ppd)), int(i * 0.5 * ppd))

    def _draw_ship(self, S, sh, brg, sx, wy, ppm, col):
        d = adiff(sh.hdg, brg)
        sn, cs = math.sin(d * RAD), math.cos(d * RAD)
        dirn = 1 if sn >= 0 else -1
        proj = sh.length * abs(sn) + sh.beam * abs(cs)
        tilt = sh.sinking * 0.30 * dirn
        drop = (sh.sinking ** 1.5) * 40 * ppm
        ct, st = math.cos(tilt), math.sin(tilt)

        def P(u, h):
            x = (0.5 - u) * proj * dirn * ppm
            y = -h * ppm
            return (sx + x * ct - y * st, wy + x * st + y * ct + drop)

        hull, rects, guns = profile(sh)
        S.set_clip(pygame.Rect(0, 0, self.w, int(wy) + 1))
        pts = [P(u, h) for u, h in hull]
        minx = min(p[0] for p in pts)
        maxx = max(p[0] for p in pts)
        miny = wy
        if maxx - minx < 1.5:
            pygame.draw.line(S, col, (sx, wy), (sx, wy - 30 * ppm))
        else:
            pygame.draw.polygon(S, col, pts)
            for u0, u1, h0, h1 in rects:
                q = [P(u0, h0), P(u1, h0), P(u1, h1), P(u0, h1)]
                pygame.draw.polygon(S, col, q)
                miny = min(miny, min(p[1] for p in q))
            gw = max(1, int(0.9 * ppm))
            for u, h, du in guns:
                pygame.draw.line(S, col, P(u, h), P(u + du, h), gw)
        S.set_clip(None)
        miny = min(miny, min(p[1] for p in pts))
        sh.box = pygame.Rect(int(minx), int(miny), max(4, int(maxx - minx)), max(4, int(wy - miny)))

    def _label(self, S, world, sh, col):
        r = sh.box
        locked = world.lock is sh
        if sh.is_target:
            label, c = sh.short.upper(), THEME.amber
        else:
            label, c = sh.short.upper(), (200, 206, 200)
        if sh.hp <= 0:
            label += " SINKING"
        img = font(12, "mono", True).render(label, True, c)
        lr = img.get_rect(midbottom=(r.centerx, r.top - 6))
        # Nudge labels upward so neighbours at similar bearings stay readable.
        for _ in range(6):
            if any(lr.inflate(6, 2).colliderect(o) for o in self._labels):
                lr.y -= lr.h + 2
        self._labels.append(lr)
        bg = pygame.Surface((lr.w + 8, lr.h + 2), pygame.SRCALPHA)
        bg.fill((0, 0, 0, 130))
        S.blit(bg, (lr.x - 4, lr.y - 1))
        S.blit(img, lr)
        if locked:
            br = r.inflate(14, 12)
            a = 8
            for (x, y, dx, dy) in ((br.left, br.top, 1, 1), (br.right, br.top, -1, 1),
                                   (br.left, br.bottom, 1, -1), (br.right, br.bottom, -1, -1)):
                pygame.draw.line(S, THEME.amber, (x, y), (x + a * dx, y), 2)
                pygame.draw.line(S, THEME.amber, (x, y), (x, y + a * dy), 2)

    def _fx(self, S, world, sx_of, hy, ppd, eye):
        s = world.sub
        night = world.tod != "day"
        for f in world.fx:
            r = dist(s.x, s.y, f.x, f.y)
            if r > world.vis or r < 20:
                continue
            x = sx_of(bearing(s.x, s.y, f.x, f.y))
            if x < -100 or x > self.w + 100:
                continue
            ppm = ppd * 57.2958 / r
            a = world.t - f.t0
            wy = hy + ppm * eye
            if f.kind == "boom":
                hmax = 70 * f.size
                rise = min(1.0, a / 0.7)
                fall = max(0.0, (a - 2.0) / 5.0)
                h = hmax * rise * (1 - fall)
                w = 14 * f.size * (1 + a * 0.4)
                if night and a < 1.2:
                    pygame.draw.circle(S, (255, 170, 80), (int(x), int(wy - 6 * ppm)),
                                       max(2, int((24 - a * 12) * ppm)))
                if h > 0.5:
                    col = (236, 238, 232) if not night else (150, 150, 146)
                    pts = [(x - w * ppm, wy), (x - w * 0.35 * ppm, wy - h * ppm),
                           (x + w * 0.35 * ppm, wy - h * 0.9 * ppm), (x + w * ppm, wy)]
                    pygame.draw.polygon(S, col, pts)
                if a > 1.5:
                    smoke = (40, 38, 36) if not night else (20, 18, 18)
                    pygame.draw.circle(S, smoke, (int(x + a * 2 * ppm), int(wy - (30 + a * 8) * ppm)),
                                       max(2, int((10 + a * 3) * ppm)))
            elif f.kind == "dc":
                h = 32 * min(1.0, a / 0.5) * max(0.0, 1 - max(0.0, a - 1.2) / 3)
                if h > 0.5:
                    col = (226, 232, 228) if not night else (120, 126, 126)
                    w = 9
                    pygame.draw.polygon(S, col, [(x - w * ppm, wy), (x, wy - h * ppm), (x + w * ppm, wy)])

    def _waves(self, S, pal, hy, ppd, view, t, jx):
        n = 12
        step = 16
        off = view * ppd
        calm = 0.3 if self.reduced_motion else 1.0
        for i in range(n):
            f = (i + 1) / n
            y0 = hy + 2 + (self.h - hy + 30) * f ** 1.9
            amp = 0.6 + f * f * 9
            wl = 30 + f * f * 320
            k = math.tau / wl
            sp = (0.7 + f) * calm
            base = lerp_color(pal["sea_hor"], pal["sea_bot"], f ** 0.8)
            if i % 2:
                base = lerp_color(base, pal["wave_hi"], 0.05)
            pts = []
            for x in range(-step, self.w + step + 1, step):
                xx = x + off - jx
                y = y0 + amp * math.sin(xx * k + t * sp + i) + amp * 0.4 * math.sin(xx * k * 2.3 - t * 1.3 * calm + i * 2)
                pts.append((x, y))
            pygame.draw.polygon(S, base, pts + [(self.w + step, self.h + 5), (-step, self.h + 5)])
            pygame.draw.lines(S, lerp_color(base, pal["wave_hi"], 0.22), False, pts, 1)

    def _wakes(self, S, world, sx_of, hy, ppd, eye, pal):
        s = world.sub
        for tp in world.torps:
            if not tp.wake:
                continue
            r = dist(s.x, s.y, tp.x, tp.y)
            if r > 3500 or r < 40:
                continue
            x = sx_of(bearing(s.x, s.y, tp.x, tp.y))
            y = hy + ppd * 57.2958 * eye / r + 2
            ln = max(3, int(ppd * 57.2958 * 30 / r))
            pygame.draw.line(S, pal["wave_hi"], (x - ln / 2, y), (x + ln / 2, y), 2)

    def _reticle(self, S, world, pal, view, ppd, fov):
        s = world.sub
        c = pal["reticle"]
        cx, cy = self.cx, self.cy
        pygame.draw.line(S, c, (cx - self.rx, cy), (cx - 14, cy), 1)
        pygame.draw.line(S, c, (cx + 14, cy), (cx + self.rx, cy), 1)
        pygame.draw.line(S, c, (cx, cy - self.ry), (cx, cy - 14), 1)
        pygame.draw.line(S, c, (cx, cy + 14), (cx, cy + self.ry * 0.55), 1)
        unit = 1 if s.zoom else 2
        span = int(fov / 2) + 1
        for d in range(-span, span + 1):
            if d % unit:
                continue
            x = cx + d * ppd
            big = d % (unit * 5) == 0
            ln = 9 if big else 5
            pygame.draw.line(S, c, (x, cy - ln), (x, cy + ln), 1)
        for i in range(1, 7):
            y = cy + i * 14
            pygame.draw.line(S, c, (cx - 4, y), (cx + 4, y), 1)

        # True-bearing tape along the top of the lens.
        ty = cy - self.ry * 0.78
        f = font(13, "mono")
        stepd = 2 if s.zoom else 10
        start = int((view - fov / 2) // stepd) * stepd
        d = start
        while d <= view + fov / 2 + stepd:
            x = cx + adiff(d, view) * ppd
            pygame.draw.line(S, c, (x, ty), (x, ty + 8), 1)
            text(S, p3(d), f, c, (x, ty - 2), "midbottom")
            d += stepd
        pygame.draw.polygon(S, THEME.amber, [(cx - 6, ty + 16), (cx + 6, ty + 16), (cx, ty + 9)])

        # Data strip.
        lines = []
        mag = "x6 HIGH" if s.zoom else "x1.5 LOW"
        where = "BRIDGE" if s.surfaced else "SCOPE"
        lines.append((f"{where}  TRUE {p3(view)}  REL {p3(s.scope_rel)}  {mag}", THEME.text))
        sol = world.solution()
        if world.lock is not None and world.lock.alive:
            tg = world.lock
            r = dist(s.x, s.y, tg.x, tg.y)
            aob = adiff(bearing(tg.x, tg.y, s.x, s.y), tg.hdg)
            side = "STBD" if aob > 0 else "PORT"
            q = int((sol or {}).get("q", 0) * 100)
            lines.append((f"TGT {tg.short.upper()}  RNG {r:,.0f} m  AOB {abs(aob):.0f} {side}  "
                          f"SPD {tg.spd:.0f} kn  SOLN {q}%", THEME.amber))
            if sol:
                g = sol["gyro"]
                ok = sol["in_range"] and abs(g) <= 90 and sol["run"] > ARM_DIST
                msg = "READY" if ok else ("OUT OF RANGE" if not sol["in_range"] else
                                          "GYRO > 90" if abs(g) > 90 else "TOO CLOSE")
                lines.append((f"GYRO {abs(g):.0f} {'R' if g >= 0 else 'L'}  RUN {sol['run']:,.0f} m  "
                              f"TIME {sol['t']:.0f} s  {msg}", THEME.good if ok else THEME.alarm))
            else:
                lines.append(("NO SOLUTION: torpedo can't catch her from here", THEME.alarm))
        f2 = font(14, "mono", True)
        y = cy + self.ry * 0.86 - len(lines) * 18
        for ln, col in lines:
            img = f2.render(ln, True, col)
            r = img.get_rect(midtop=(cx, y))
            bg = pygame.Surface((r.w + 12, r.h + 2), pygame.SRCALPHA)
            bg.fill((0, 0, 0, 120))
            S.blit(bg, (r.x - 6, r.y - 1))
            S.blit(img, r)
            y += 18
