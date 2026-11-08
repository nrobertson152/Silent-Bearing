"""Window, screens, input and the control-room layout."""
import sys

import pygame

from .audio import Audio
from .data import NATION_ORDER, NATIONS, PREFIX
from .instruments import draw_bar, draw_chart, draw_compass, draw_dial, draw_sonar
from .scope import Scope, fov_of
from .ui import THEME, Button, draw_badge, font, plate, spaced, text, text_block, wrap_text
from .util import adiff, bearing, clamp, fmt_clock, wrap
from .world import RUDDER, TELEGRAPH, World

W, H = 1280, 800
TOP = pygame.Rect(0, 0, W, 40)
SCOPE = pygame.Rect(12, 48, 840, 470)
STRIP = pygame.Rect(12, 526, 840, 42)
PANEL = pygame.Rect(12, 576, 840, 212)
SONAR = pygame.Rect(864, 48, 404, 262)
CHART = pygame.Rect(864, 318, 404, 312)
LOG = pygame.Rect(864, 638, 404, 150)
CHART_PAPER = pygame.Rect(CHART.x + 8, CHART.y + 28, CHART.w - 16, CHART.h - 36)

TYPE_NAMES = {"bb": "Battleship", "cv": "Aircraft carrier", "ca": "Cruiser"}
TOD_NAMES = {"day": "Daylight", "dusk": "Dusk", "night": "Night"}
CHART_SCALES = (3000, 6000, 12000)

CONTROLS = [
    ("W / S", "Engine telegraph"), ("A / D", "Rudder"), ("R / F", "Order shallower / deeper"),
    ("C", "Crash dive"), ("P", "Raise or lower the periscope"), ("Left / Right, or drag", "Train the periscope"),
    ("Z, or wheel on scope", "Periscope power"), ("L, or click a ship", "Lock target on the TDC"),
    ("Space", "Fire one torpedo"), ("X", "Fire a spread of three"), ("T", "Time compression"),
    ("M, or wheel on chart", "Plot table scale"), ("V", "Sound on / off"), ("Esc", "Pause"),
    ("F11", "Fullscreen"),
]


class App:
    def __init__(self):
        pygame.init()
        pygame.display.set_caption("Silent Bearing")
        self.screen = pygame.display.set_mode((W, H), pygame.SCALED | pygame.RESIZABLE)
        self.clock = pygame.time.Clock()
        self.audio = Audio()
        self.scope = Scope(SCOPE.size)
        self.real_t = 0.0
        self.state = "menu"
        self.menu_step = "nation"
        self.nat_id = None
        self.tgt_id = None
        self.in_patrol = False
        self.paused = False
        self.result_shown = False
        self.end_timer = 0.0
        self.chart_r = 6000
        self.train_btn = 0
        self.drag = None
        self.mouse = (0, 0)
        self._demo_world()
        self._build_play_buttons()
        self.menu_buttons = []
        self.overlay_buttons = []
        self._build_menu()

    # ----------------------------------------------------------------- setup
    def _demo_world(self):
        nat = NATIONS["us"]
        self.world = World(nat, nat.targets[3], demo=True)
        s, tg = self.world.sub, self.world.target
        tg.x, tg.y = -2600.0, 3400.0
        s.scope_rel = adiff(bearing(s.x, s.y, tg.x, tg.y), s.hdg)
        for e in self.world.escorts:
            e.x, e.y = self.world._station(tg, e.off)
        self.world._observe(0)
        self.world.lock = tg
        self.world.lock_obs = 8
        THEME.set_red(False)

    def start_mission(self, nat_id, tgt_id):
        nat = NATIONS[nat_id]
        spec = next(t for t in nat.targets if t.id == tgt_id)
        self.nat_id, self.tgt_id = nat_id, tgt_id
        self.world = World(nat, spec)
        THEME.set_red(spec.tod == "night")
        self.state = "play"
        self.in_patrol = True
        self.paused = False
        self.result_shown = False
        self.end_timer = 0.0
        self.chart_r = 6000
        self.overlay_buttons = []
        self._build_dive_buttons()

    def _build_play_buttons(self):
        self.play_buttons = []
        B = self._pb
        x, y, h = STRIP.x + 10, STRIP.y + 6, 30
        B((x, y, 38, h), "<", hold=lambda p: self._train(-1, p)); x += 42
        B((x, y, 50, h), "BOW", on_click=self.scope_bow); x += 54
        B((x, y, 38, h), ">", hold=lambda p: self._train(1, p)); x += 48
        B((x, y, 112, h), lambda: "LOWER SCOPE" if self.world.sub.scope else "RAISE SCOPE",
          on_click=lambda: self.world.toggle_scope(), active=lambda: self.world.sub.scope); x += 116
        B((x, y, 92, h), lambda: "POWER x6" if self.world.sub.zoom else "POWER x1.5",
          on_click=self.toggle_zoom, active=lambda: self.world.sub.zoom); x += 96
        B((x, y, 60, h), "LOCK", on_click=lambda: self.world.lock_nearest(),
          active=lambda: self.world.lock is not None); x += 70
        B((x, y, 64, h), "FIRE", style="fire", on_click=lambda: self.world.fire(1)); x += 68
        B((x, y, 92, h), "SPREAD x3", style="fire", on_click=lambda: self.world.fire(3)); x += 100
        self.tubes_x = x

        lx, w = PANEL.x + 438, 392
        y = PANEL.y + 30
        bw = (w - 3 * 7) / 8
        for i, (lbl, _) in enumerate(TELEGRAPH):
            B((lx + i * (bw + 3), y, bw, 28), lbl, on_click=lambda i=i: self.world.set_telegraph(i),
              active=lambda i=i: self.world.sub.tel == i)
        y = PANEL.y + 82
        bw = (w - 3 * 4) / 5
        for i, (_, lbl) in enumerate(RUDDER):
            B((lx + i * (bw + 3), y, bw, 28), lbl, on_click=lambda i=i: self.world.set_rudder(i),
              active=lambda i=i: self.world.sub.rud_i == i)

        x = W - 12
        for lbl, fn in (("MENU", self.open_pause), (lambda: "SOUND ON" if self.audio.on else "SOUND OFF",
                                                    self.toggle_sound)):
            bw = 66 if lbl == "MENU" else 90
            x -= bw
            B((x, 6, bw, 28), lbl, on_click=fn, active=(lambda: self.audio.on) if fn == self.toggle_sound else None)
            x -= 6
        for tc in (16, 4, 1):
            x -= 40
            B((x, 6, 40, 28), f"{tc}x", on_click=lambda tc=tc: self.set_tc(tc),
              active=lambda tc=tc: self.world.tc == tc)
            x -= 3
        self.tc_left = x

        x = CHART.right - 10
        for r in reversed(CHART_SCALES):
            x -= 44
            B((x, CHART.y + 4, 42, 20), f"{r // 1000} km", on_click=lambda r=r: self._set_chart(r),
              active=lambda r=r: self.chart_r == r)
        self.dive_buttons = []
        self._build_dive_buttons()

    def _pb(self, rect, label, **kw):
        b = Button(rect, label, **kw)
        self.play_buttons.append(b)
        return b

    def _build_dive_buttons(self):
        for b in self.dive_buttons:
            if b in self.play_buttons:
                self.play_buttons.remove(b)
        self.dive_buttons = []
        depths = self.world.depths
        lx, w = PANEL.x + 438, 392
        n = len(depths) + 1
        bw = (w - 3 * (n - 1)) / n
        y = PANEL.y + 134
        for i, d in enumerate(depths):
            lbl = "SURF" if d == 0 else f"{d} m"
            b = Button((lx + i * (bw + 3), y, bw, 28), lbl,
                       on_click=lambda d=d: self.world.set_depth(d),
                       active=lambda d=d: abs(self.world.sub.dep_ord - d) < 0.5)
            self.dive_buttons.append(b)
        b = Button((lx + (n - 1) * (bw + 3), y, bw, 28), "CRASH", style="fire", on_click=self.crash_dive)
        self.dive_buttons.append(b)
        self.play_buttons.extend(self.dive_buttons)

    # --------------------------------------------------------------- actions
    def _train(self, d, pressed):
        self.train_btn = d if pressed else 0

    def scope_bow(self):
        self.world.sub.scope_rel = 0.0

    def toggle_zoom(self):
        self.world.sub.zoom = not self.world.sub.zoom

    def toggle_sound(self):
        self.audio.toggle()

    def _set_chart(self, r):
        self.chart_r = r

    def crash_dive(self):
        ds = self.world.depths
        target = max([d for d in ds if d <= 60] or [ds[-1]])
        self.world.set_depth(target, crash=True)

    def set_tc(self, tc):
        w = self.world
        if tc > 4 and any(e.alive and e.state != "screen" for e in w.escorts):
            w.report("Can't speed up time with escorts hunting us.", "warn", "tcwarn", 5)
            tc = 4
        w.tc = tc

    def cycle_tc(self):
        order = (1, 4, 16)
        self.set_tc(order[(order.index(self.world.tc) + 1) % 3] if self.world.tc in order else 1)

    def open_pause(self):
        if self.state == "play" and not self.result_shown:
            self.paused = True
            self._build_pause()

    def resume(self):
        self.paused = False
        self.overlay_buttons = []

    def to_menu(self, step="nation"):
        self.state = "menu"
        self.paused = False
        self.result_shown = False
        self.in_patrol = False
        self.menu_step = step
        self.overlay_buttons = []
        self.audio.ambience(False)
        if step == "nation":
            self._demo_world()
        self._build_menu()

    # ----------------------------------------------------------------- menus
    MENU = pygame.Rect(110, 52, 1060, 700)

    def _build_menu(self):
        M = self.MENU
        self.menu_buttons = []
        self.menu_cards = []
        if self.menu_step == "nation":
            for i, nid in enumerate(NATION_ORDER):
                r = pygame.Rect(M.x + 28 + i * 254, M.y + 150, 242, 470)
                self.menu_cards.append((r, nid))
        elif self.menu_step == "target":
            nat = NATIONS[self.nat_id]
            for i, tg in enumerate(nat.targets):
                r = pygame.Rect(M.x + 28, M.y + 140 + i * 106, M.w - 56, 98)
                self.menu_cards.append((r, tg.id))
            self.menu_buttons.append(Button((M.right - 140, M.y + 92, 112, 32), "BACK",
                                            on_click=lambda: self._menu_go("nation")))
        elif self.menu_step == "brief":
            self.menu_buttons.append(Button((M.right - 268, M.bottom - 64, 240, 44), "BEGIN PATROL",
                                            style="big", on_click=self._begin))
            self.menu_buttons.append(Button((M.right - 400, M.bottom - 58, 112, 32), "BACK",
                                            on_click=lambda: self._menu_go("target")))

    def _menu_go(self, step):
        self.menu_step = step
        self._build_menu()

    def _pick_card(self, key):
        if self.menu_step == "nation":
            self.nat_id = key
            self._menu_go("target")
        elif self.menu_step == "target":
            self.tgt_id = key
            self._menu_go("brief")

    def _begin(self):
        self.start_mission(self.nat_id, self.tgt_id)

    def _build_pause(self):
        r = pygame.Rect(0, 0, 420, 270)
        r.center = (W // 2, H // 2)
        self.overlay_rect = r
        x = r.x + 40
        self.overlay_buttons = [
            Button((x, r.y + 92, 340, 40), "RESUME PATROL", style="big", on_click=self.resume),
            Button((x, r.y + 144, 340, 34), "ABANDON PATROL", on_click=lambda: self.to_menu("nation")),
            Button((x, r.y + 190, 340, 34), "QUIT TO DESKTOP", on_click=self.quit),
        ]

    def _build_result(self):
        r = pygame.Rect(0, 0, 680, 470)
        r.center = (W // 2, H // 2)
        self.overlay_rect = r
        y = r.bottom - 62
        self.overlay_buttons = [
            Button((r.x + 32, y, 200, 40), "TRY AGAIN", style="big",
                   on_click=lambda: self.start_mission(self.nat_id, self.tgt_id)),
            Button((r.x + 244, y, 200, 40), "NEW TARGET", on_click=lambda: self.to_menu("target")),
            Button((r.x + 456, y, 192, 40), "QUIT", on_click=self.quit),
        ]

    def quit(self):
        pygame.quit()
        sys.exit(0)

    # ----------------------------------------------------------------- input
    def handle(self, ev):
        if ev.type == pygame.QUIT:
            self.quit()
        if ev.type in (pygame.MOUSEMOTION, pygame.MOUSEBUTTONDOWN, pygame.MOUSEBUTTONUP):
            self.mouse = ev.pos
        if ev.type == pygame.KEYDOWN and ev.key == pygame.K_F11:
            pygame.display.toggle_fullscreen()
            return
        if self.state == "menu":
            self._handle_menu(ev)
            return
        if self.paused or self.result_shown:
            for b in self.overlay_buttons:
                if b.handle(ev):
                    return
            if ev.type == pygame.KEYDOWN:
                if self.paused and ev.key == pygame.K_ESCAPE:
                    self.resume()
                elif self.result_shown and ev.key in (pygame.K_RETURN, pygame.K_SPACE):
                    self.start_mission(self.nat_id, self.tgt_id)
            return
        for b in self.play_buttons:
            if b.handle(ev):
                return
        self._handle_play(ev)

    def _handle_menu(self, ev):
        for b in self.menu_buttons:
            if b.handle(ev):
                return
        if ev.type == pygame.MOUSEBUTTONUP and ev.button == 1:
            for r, key in self.menu_cards:
                if r.collidepoint(ev.pos):
                    self._pick_card(key)
                    return
        if ev.type == pygame.KEYDOWN:
            k = ev.key
            if pygame.K_1 <= k <= pygame.K_9:
                i = k - pygame.K_1
                if i < len(self.menu_cards):
                    self._pick_card(self.menu_cards[i][1])
            elif k in (pygame.K_RETURN, pygame.K_KP_ENTER) and self.menu_step == "brief":
                self._begin()
            elif k in (pygame.K_ESCAPE, pygame.K_BACKSPACE):
                if self.menu_step == "brief":
                    self._menu_go("target")
                elif self.menu_step == "target":
                    self._menu_go("nation")

    def _handle_play(self, ev):
        w = self.world
        s = w.sub
        if ev.type == pygame.KEYDOWN:
            k = ev.key
            if k == pygame.K_w:
                w.set_telegraph(s.tel + 1)
            elif k == pygame.K_s:
                w.set_telegraph(s.tel - 1)
            elif k == pygame.K_a:
                w.set_rudder(s.rud_i - 1)
            elif k == pygame.K_d:
                w.set_rudder(s.rud_i + 1)
            elif k == pygame.K_r:
                w.depth_step(-1)
            elif k == pygame.K_f:
                w.depth_step(1)
            elif k == pygame.K_c:
                self.crash_dive()
            elif k == pygame.K_p:
                w.toggle_scope()
            elif k == pygame.K_z:
                self.toggle_zoom()
            elif k == pygame.K_l:
                w.lock_nearest()
            elif k == pygame.K_SPACE:
                w.fire(1)
            elif k == pygame.K_x:
                w.fire(3)
            elif k == pygame.K_b:
                self.scope_bow()
            elif k == pygame.K_t:
                self.cycle_tc()
            elif k == pygame.K_m:
                self._set_chart(CHART_SCALES[(CHART_SCALES.index(self.chart_r) + 1) % 3])
            elif k == pygame.K_v:
                self.toggle_sound()
            elif k == pygame.K_ESCAPE:
                self.open_pause()
        elif ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1 and SCOPE.collidepoint(ev.pos):
            self.drag = {"moved": 0}
        elif ev.type == pygame.MOUSEMOTION and self.drag is not None:
            dx = ev.rel[0]
            self.drag["moved"] += abs(dx) + abs(ev.rel[1])
            ppd = (2 * self.scope.rx) / fov_of(s)
            s.scope_rel = wrap(s.scope_rel - dx / ppd)
        elif ev.type == pygame.MOUSEBUTTONUP and ev.button == 1 and self.drag is not None:
            if self.drag["moved"] < 5 and s.can_see:
                lx, ly = ev.pos[0] - SCOPE.x, ev.pos[1] - SCOPE.y
                for sh in w.ships:
                    if sh.box is not None and sh.alive and sh.box.inflate(16, 16).collidepoint(lx, ly):
                        w.lock_ship(sh)
                        break
            self.drag = None
        elif ev.type == pygame.MOUSEWHEEL:
            if CHART.collidepoint(self.mouse):
                i = CHART_SCALES.index(self.chart_r) + (-1 if ev.y > 0 else 1)
                self._set_chart(CHART_SCALES[int(clamp(i, 0, 2))])
            elif SCOPE.collidepoint(self.mouse):
                s.zoom = ev.y > 0

    # ------------------------------------------------------------------ tick
    def tick(self, dt):
        self.real_t += dt
        w = self.world
        playing = self.state == "play" and not self.paused and not self.result_shown
        if playing:
            keys = pygame.key.get_pressed()
            tr = self.train_btn
            if keys[pygame.K_LEFT] or keys[pygame.K_q]:
                tr -= 1
            if keys[pygame.K_RIGHT] or keys[pygame.K_e]:
                tr += 1
            if tr:
                fast = 2.5 if (keys[pygame.K_LSHIFT] or keys[pygame.K_RSHIFT]) else 1.0
                w.sub.scope_rel = wrap(w.sub.scope_rel + clamp(tr, -1, 1) * (10 if w.sub.zoom else 40) * dt * fast)
            sim = dt * w.tc
            while sim > 1e-9:
                st = min(0.1, sim)
                w.update(st)
                sim -= st
            for kind, vol in w.events:
                self.audio.play(kind, vol)
            w.events.clear()
            if w.result:
                self.end_timer += dt
                if self.end_timer >= w.end_delay:
                    self.result_shown = True
                    self._build_result()
        self.audio.ambience(playing, w.sub.spd)

    # ------------------------------------------------------------------ draw
    def draw(self):
        scr = self.screen
        scr.fill(THEME.hull)
        self._draw_console(scr)
        if self.state == "menu":
            self._draw_menu(scr)
        elif self.paused:
            self._draw_pause(scr)
        elif self.result_shown:
            self._draw_result(scr)

    def _draw_console(self, scr):
        w = self.world
        s = w.sub
        mouse = self.mouse

        # Top bar.
        pygame.draw.rect(scr, THEME.plate, TOP)
        pygame.draw.line(scr, THEME.seam, (0, TOP.bottom - 1), (W, TOP.bottom - 1), 2)
        r = text(scr, spaced("SILENT BEARING"), font(20, "display", True), THEME.brass, (16, 20), "midleft")
        if not w.demo:
            msg = f"{w.nat.boat}   vs   {w.target.name}"
            text(scr, msg, font(15), THEME.text, (r.right + 26, 20), "midleft")
            lbl, kind = w.threat()
            pill = pygame.Rect(0, 0, 124, 24)
            pill.midright = (self.tc_left - 100, 20)
            col = THEME.kind(kind)
            pygame.draw.rect(scr, THEME.seam, pill, border_radius=12)
            pygame.draw.rect(scr, col, pill, 1, border_radius=12)
            pygame.draw.circle(scr, col, (pill.left + 12, pill.centery), 4)
            text(scr, lbl, font(13, "ui", True), col, (pill.centerx + 6, pill.centery), "center")
            text(scr, fmt_clock(w.t), font(17, "mono", True), THEME.amber, (self.tc_left - 12, 20), "midright")

        # Periscope.
        scr.blit(self.scope.draw(w, self.real_t), SCOPE.topleft)
        pygame.draw.rect(scr, THEME.seam, SCOPE.inflate(4, 4), 2, border_radius=4)

        # Scope strip and tubes.
        plate(scr, STRIP)
        x = self.tubes_x
        text(scr, "TUBES", font(12, "ui", True), THEME.brass, (x, STRIP.centery), "midleft")
        x += 48
        for i, v in enumerate(s.tubes):
            rr = pygame.Rect(x + i * 27, STRIP.y + 9, 23, 24)
            pygame.draw.rect(scr, THEME.seam, rr, border_radius=3)
            if v == 0:
                pygame.draw.rect(scr, (60, 120, 70), rr.inflate(-4, -4), border_radius=2)
                tc = (220, 250, 220)
            elif v > 0:
                fill = rr.inflate(-4, -4)
                frac = 1 - v / 45.0
                f2 = fill.copy()
                f2.h = int(fill.h * frac)
                f2.bottom = fill.bottom
                pygame.draw.rect(scr, (90, 70, 30), f2)
                tc = THEME.amber
            else:
                tc = THEME.muted
            text(scr, str(i + 1), font(13, "mono", True), tc, rr.center, "center")
        text(scr, f"+{s.spares}", font(12, "mono", True), THEME.muted, (x + len(s.tubes) * 27 + 2, STRIP.centery), "midleft")

        # Hydrophones.
        plate(scr, SONAR, "Hydrophones", "bearing only, bow up")
        draw_sonar(scr, pygame.Rect(SONAR.x, SONAR.y + 22, SONAR.w, SONAR.h - 24), w, self.real_t)

        # Plot table.
        plate(scr, CHART, "Plot table")
        draw_chart(scr, CHART_PAPER, w, self.chart_r)

        # Conn log.
        plate(scr, LOG, "Conn")
        self._draw_log(scr)

        # Control panel.
        plate(scr, PANEL, "Control room")
        N = w.nat
        vmax = 150 if N.crush <= 160 else 300
        major, minor = (25, 5) if vmax <= 150 else (50, 10)
        cy = PANEL.y + 96
        draw_dial(scr, (PANEL.x + 82, cy), 66, s.depth, 0, vmax, "DEPTH M", f"{s.depth:3.0f} m",
                  major, minor, red_from=N.test, order=s.dep_ord)
        want = abs(TELEGRAPH[s.tel][1]) * (N.surf_kn if s.surfaced else N.sub_kn)
        draw_dial(scr, (PANEL.x + 224, cy), 66, abs(s.spd), 0, 25, "KNOTS" if s.spd >= -0.05 else "ASTERN",
                  f"{abs(s.spd):4.1f}", 5, 1, order=want)
        draw_compass(scr, (PANEL.x + 366, cy), 66, s.hdg, s.rud)
        by = PANEL.y + 174
        hc = THEME.good if s.hull > 60 else THEME.amber if s.hull > 30 else THEME.alarm
        draw_bar(scr, pygame.Rect(PANEL.x + 20, by, 118, 30), s.hull / 100, "Hull", hc, f"{s.hull:.0f}%")
        bc = THEME.phos if s.bat > 25 else THEME.amber if s.bat > 8 else THEME.alarm
        draw_bar(scr, pygame.Rect(PANEL.x + 160, by, 118, 30), s.bat / 100, "Battery", bc, f"{s.bat:.0f}%")
        ac = THEME.phos if s.air > 30 else THEME.amber
        draw_bar(scr, pygame.Rect(PANEL.x + 300, by, 118, 30), s.air / 100, "Air", ac, f"{s.air:.0f}%")
        lx = PANEL.x + 438
        fl = font(11, "ui", True)
        text(scr, spaced("ENGINE TELEGRAPH") + "     W / S", fl, THEME.muted, (lx, PANEL.y + 16))
        text(scr, spaced("HELM") + "     A / D", fl, THEME.muted, (lx, PANEL.y + 68))
        text(scr, spaced("DIVING") + "     R / F    C crash dive", fl, THEME.muted, (lx, PANEL.y + 120))
        text(scr, "Space fire  X spread  L lock  P scope  Z power  T time  Esc menu",
             font(12), THEME.muted, (lx, PANEL.y + 176))
        text(scr, "Arrows or drag to train the scope. Click a ship to lock.", font(12), THEME.muted,
             (lx, PANEL.y + 192))

        for b in self.play_buttons:
            b.draw(scr, mouse)

    def _draw_log(self, scr):
        w = self.world
        x, y0 = LOG.x + 14, LOG.y + 26
        maxy = LOG.bottom - 8
        f = font(13)
        ft = font(11, "mono")
        y = y0
        width = LOG.w - 70
        for t, msg, kind in reversed(w.log):
            lines = wrap_text(msg, f, width)
            hgt = len(lines) * 15
            if y + hgt > maxy:
                break
            text(scr, fmt_clock(t)[3:], ft, THEME.muted, (x, y + 1))
            col = THEME.kind(kind)
            for ln in lines:
                text(scr, ln, f, col, (x + 44, y))
                y += 15
            y += 3
            col = THEME.muted

    # -------------------------------------------------------------- overlays
    def _dim(self, scr, a=210):
        ov = pygame.Surface((W, H), pygame.SRCALPHA)
        ov.fill((6, 8, 9, a))
        scr.blit(ov, (0, 0))

    def _draw_menu(self, scr):
        self._dim(scr, 200)
        M = self.MENU
        plate(scr, M)
        mouse = self.mouse
        text(scr, spaced("SILENT BEARING", 1), font(46, "display", True), THEME.brass, (M.x + 30, M.y + 22))
        text(scr, "Take the conn of a wartime submarine. Find the warship, slip the escorts, and sink her.",
             font(16), THEME.text, (M.x + 32, M.y + 82))
        if self.menu_step == "nation":
            text(scr, spaced("CHOOSE YOUR NAVY"), font(14, "ui", True), THEME.muted, (M.x + 32, M.y + 120))
            for i, (r, nid) in enumerate(self.menu_cards):
                self._nation_card(scr, r, NATIONS[nid], i, r.collidepoint(mouse))
        elif self.menu_step == "target":
            nat = NATIONS[self.nat_id]
            draw_badge(scr, nat.id, (M.x + 50, M.y + 115), 16)
            text(scr, f"{nat.boat}.  {spaced('CHOOSE YOUR TARGET')}", font(15, "ui", True), THEME.text,
                 (M.x + 76, M.y + 106))
            for i, (r, tid) in enumerate(self.menu_cards):
                tg = next(t for t in nat.targets if t.id == tid)
                self._target_card(scr, r, tg, i, r.collidepoint(mouse))
        elif self.menu_step == "brief":
            self._brief(scr, M)
        for b in self.menu_buttons:
            b.draw(scr, mouse)

    def _nation_card(self, scr, r, nat, i, hover):
        pygame.draw.rect(scr, THEME.plate2 if not hover else (52, 60, 62), r, border_radius=6)
        pygame.draw.rect(scr, THEME.brass if hover else THEME.seam, r, 2, border_radius=6)
        draw_badge(scr, nat.id, (r.centerx, r.y + 52), 34)
        text(scr, nat.name, font(22, "display", True), THEME.text, (r.centerx, r.y + 104), "midtop")
        text(scr, nat.boat, font(14), THEME.brass, (r.centerx, r.y + 134), "midtop")
        rows = [("Submerged", f"{nat.sub_kn:g} kn"), ("Surfaced", f"{nat.surf_kn:g} kn"),
                ("Test depth", f"{nat.test:g} m"), ("Tubes / load", f"{nat.tubes} / {nat.torps}"),
                ("Torpedo", nat.torp.name), ("Run", f"{nat.torp.range_m / 1000:.1f} km at {nat.torp.kn:g} kn"),
                ("Dud rate", f"{nat.torp.dud * 100:.0f}%"), ("Wake", "visible" if nat.torp.wake else "none")]
        y = r.y + 166
        fl, fv = font(13), font(13, "mono", True)
        for k, v in rows:
            text(scr, k, fl, THEME.muted, (r.x + 16, y))
            text(scr, v, fv, THEME.text, (r.right - 16, y), "topright")
            y += 19
            pygame.draw.line(scr, THEME.seam, (r.x + 16, y - 2), (r.right - 16, y - 2))
        text_block(scr, nat.blurb, font(13), THEME.text, r.x + 16, y + 8, r.w - 32)
        text(scr, f"Press {i + 1}", font(12, "ui", True), THEME.brass if hover else THEME.muted,
             (r.centerx, r.bottom - 12), "midbottom")

    def _target_card(self, scr, r, tg, i, hover):
        pygame.draw.rect(scr, THEME.plate2 if not hover else (52, 60, 62), r, border_radius=6)
        pygame.draw.rect(scr, THEME.brass if hover else THEME.seam, r, 2, border_radius=6)
        text(scr, str(i + 1), font(26, "display", True), THEME.brass_lo, (r.x + 22, r.centery), "center")
        x = r.x + 46
        text(scr, spaced(TYPE_NAMES[tg.type].upper()), font(11, "ui", True), THEME.muted, (x, r.y + 10))
        nr = text(scr, PREFIX[tg.nation] + tg.name, font(24, "display", True), THEME.text, (x, r.y + 24))
        tag = "HISTORICAL" if tg.historical else "WHAT IF"
        tcol = THEME.good if tg.historical else THEME.amber
        pill = pygame.Rect(nr.right + 14, nr.y + 6, font(11, "ui", True).size(tag)[0] + 16, 18)
        pygame.draw.rect(scr, tcol, pill, 1, border_radius=9)
        text(scr, tag, font(11, "ui", True), tcol, pill.center, "center")
        text(scr, tg.credit, font(13), THEME.brass, (pill.right + 12, nr.y + 7))
        lines = wrap_text(tg.note, font(13), 640)
        y = r.y + 58
        for ln in lines[:2]:
            text(scr, ln, font(13), THEME.text, (x, y))
            y += 17
        rx = r.right - 190
        info = [("Escorts", str(tg.escorts) if tg.escorts else "none"), ("Conditions", TOD_NAMES[tg.tod]),
                ("Speed", "at anchor" if tg.kn == 0 else f"{tg.kn:g} kn"), ("Hits to sink", str(tg.hp))]
        y = r.y + 12
        for k, v in info:
            text(scr, k, font(12), THEME.muted, (rx, y))
            text(scr, v, font(12, "mono", True), THEME.text, (r.right - 16, y), "topright")
            y += 19

    def _brief(self, scr, M):
        nat = NATIONS[self.nat_id]
        tg = next(t for t in nat.targets if t.id == self.tgt_id)
        x = M.x + 32
        text(scr, spaced("PATROL ORDERS"), font(14, "ui", True), THEME.muted, (x, M.y + 120))
        text(scr, PREFIX[tg.nation] + tg.name, font(38, "display", True), THEME.text, (x, M.y + 142))
        text(scr, f"{TYPE_NAMES[tg.type]}   |   {tg.credit}", font(15), THEME.brass, (x, M.y + 190))
        y = text_block(scr, tg.note, font(15), THEME.text, x, M.y + 222, 520)
        esc = f"{tg.escorts} destroyer{'s' if tg.escorts != 1 else ''}" if tg.escorts else "no escort"
        cond = [("Your boat", f"{nat.boat}, {nat.torps} {nat.torp.name} torpedoes"),
                ("Conditions", TOD_NAMES[tg.tod] + (", red lighting below" if tg.tod == "night" else "")),
                ("Target", ("at anchor" if tg.kn == 0 else f"about {tg.kn:g} knots")
                 + (", zigzagging" if tg.zig else "")),
                ("Screen", esc), ("To sink her", f"{tg.hp} torpedo hit{'s' if tg.hp > 1 else ''}")]
        y += 14
        for k, v in cond:
            text(scr, k, font(14), THEME.muted, (x, y))
            text(scr, v, font(14, "ui", True), THEME.text, (x + 120, y))
            y += 22
        y += 12
        tip = ("Approach at periscope depth and keep the scope up only in short looks. Lock her on the TDC "
               "and give the solution time to settle. Fire from 1,000 to 2,500 metres off her beam. When the "
               "escorts turn on you, go deep, slow down and change course.")
        text_block(scr, tip, font(14), THEME.muted, x, y, 520)

        cx = M.x + 600
        text(scr, spaced("CONTROLS"), font(14, "ui", True), THEME.muted, (cx, M.y + 120))
        y = M.y + 148
        for k, v in CONTROLS:
            text(scr, k, font(14, "mono", True), THEME.amber, (cx, y))
            text(scr, v, font(14), THEME.text, (cx + 200, y))
            y += 25
        text(scr, "Enter to begin, Esc to go back", font(13), THEME.muted, (M.x + 32, M.bottom - 46))

    def _draw_pause(self, scr):
        self._dim(scr, 170)
        r = self.overlay_rect
        plate(scr, r)
        text(scr, spaced("PATROL PAUSED"), font(30, "display", True), THEME.brass, (r.centerx, r.y + 30), "midtop")
        for b in self.overlay_buttons:
            b.draw(scr, self.mouse)

    def _draw_result(self, scr):
        self._dim(scr, 180)
        w = self.world
        tg = w.target
        r = self.overlay_rect
        plate(scr, r)
        N = w.nat
        heads = {
            "win": ("SUNK", f"{tg.name} went down after {tg.max_hp} torpedo hit{'s' if tg.max_hp > 1 else ''}.", THEME.good),
            "lost": ("LOST WITH ALL HANDS", "The depth charges broke your hull.", THEME.alarm),
            "crushed": ("CRUSH DEPTH", f"The pressure hull gave way below {N.crush:g} metres.", THEME.alarm),
            "escaped": ("TARGET ESCAPED", f"{tg.name} outran you and slipped away.", THEME.amber),
            "dry": ("OUT OF TORPEDOES", f"Every tube is empty and {tg.short} is still afloat.", THEME.amber),
        }
        h, sub, col = heads.get(w.result, ("PATROL OVER", "", THEME.text))
        x = r.x + 32
        text(scr, spaced(h), font(40, "display", True), col, (x, r.y + 26))
        text(scr, sub, font(17), THEME.text, (x, r.y + 82))
        stats = [("Patrol time", fmt_clock(w.t)), ("Torpedoes fired", str(w.fired)), ("Hits", str(w.hits)),
                 ("Duds", str(w.duds)), ("Escorts sunk", str(w.esc_sunk)), ("Hull", f"{w.sub.hull:.0f}%")]
        y = r.y + 124
        for i, (k, v) in enumerate(stats):
            cx = x + (i % 3) * 210
            cy = y + (i // 3) * 46
            text(scr, k.upper(), font(11, "ui", True), THEME.muted, (cx, cy))
            text(scr, v, font(20, "mono", True), THEME.text, (cx, cy + 14))
        y += 104
        pygame.draw.line(scr, THEME.seam, (x, y), (r.right - 32, y), 2)
        spec = w.spec
        label = "IN HISTORY" if spec.historical else "WHAT REALLY HAPPENED"
        text(scr, spaced(label), font(12, "ui", True), THEME.brass, (x, y + 14))
        text(scr, spec.credit, font(15, "ui", True), THEME.text, (x, y + 34))
        text_block(scr, spec.note, font(14), THEME.text, x, y + 58, r.w - 64)
        for b in self.overlay_buttons:
            b.draw(scr, self.mouse)

    # ------------------------------------------------------------------ loop
    def run(self):
        while True:
            dt = min(self.clock.tick(60) / 1000.0, 0.1)
            for ev in pygame.event.get():
                self.handle(ev)
            self.tick(dt)
            self.draw()
            pygame.display.flip()


def main():
    App().run()
