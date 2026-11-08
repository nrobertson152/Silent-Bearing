"""The simulation: your boat, the target, its escorts, torpedoes and depth charges.

Nothing in here touches pygame, so the simulation can be stepped and tested
on its own. The renderer reads state; the game loop calls ``update`` and
drains ``events`` for sound.
"""
import math
import random

from .data import ESCORT_NAMES, PREFIX
from .util import KN, RAD, adiff, bearing, clamp, dist, gauss, p3, wrap

PERI_MAX = 14.5      # deepest keel depth with the periscope above water
FIRE_MAX = 40.0      # deepest depth tubes can be fired from
RELOAD = 45.0        # seconds to reload a tube
ARM_DIST = 250.0     # torpedo warheads arm after this run
ESCAPE = 18000.0     # target is lost beyond this range

TELEGRAPH = [("B.FULL", -0.5), ("B.1/3", -0.2), ("STOP", 0.0), ("1/3", 0.3),
             ("2/3", 0.55), ("STD", 0.75), ("FULL", 0.9), ("FLANK", 1.0)]
RUDDER = [(-35, "HARD L"), (-15, "L 15"), (0, "MID"), (15, "R 15"), (35, "HARD R")]

# Escort screen stations as (metres ahead, metres to starboard) of the target.
STATIONS = [(2000, 0), (600, 1500), (600, -1500), (-1200, 1200), (-1200, -1200)]

VISIBILITY = {"day": 14000.0, "dusk": 8000.0, "night": 5000.0}


class Sub:
    def __init__(self, nat):
        self.x = 0.0
        self.y = 0.0
        self.hdg = wrap(random.uniform(-20, 20))
        self.spd = 2.0
        self.tel = 3
        self.rud_i = 2
        self.rud = 0.0
        self.depth = 12.0
        self.dep_ord = 12.0
        self.crash = False
        self.hull = 100.0
        self.bat = 100.0
        self.air = 100.0
        self.scope = True
        self.scope_rel = 0.0
        self.zoom = False
        self.tubes = [0.0] * nat.tubes    # 0 loaded, >0 reloading, -1 empty
        self.spares = nat.torps - nat.tubes

    @property
    def surfaced(self):
        return self.depth < 1.5

    @property
    def can_see(self):
        return self.surfaced or (self.scope and self.depth <= PERI_MAX)


class Ship:
    _ids = 0

    def __init__(self, **kw):
        Ship._ids += 1
        self.id = Ship._ids
        self.x = self.y = self.hdg = self.spd = self.want_spd = 0.0
        self.hp = self.max_hp = 1
        self.sinking = 0.0
        self.dead = False
        self.is_target = False
        self.plot = None
        self.heard = False
        self.ever_heard = False
        self.ever_seen = False
        # escort AI
        self.state = "screen"
        self.detect = 0.0
        self.est = None
        self.est_depth = 30.0
        self.last_fix = -999.0
        self.to_drop = 0
        self.next_dc = 0.0
        self.run_until = 0.0
        self.search_until = 0.0
        self.orbit = False
        self.orb_a = self.orb_r = 0.0
        self.orb_dir = 1
        self.off = (0, 0)
        # target AI
        self.leg = 0.0
        self.base_hdg = 0.0
        self.next_zig = 0.0
        self.zig = False
        self.box = None          # screen rect from the last periscope frame
        self.__dict__.update(kw)

    @property
    def alive(self):
        return not self.dead and self.hp > 0

    @property
    def hunting(self):
        return self.state in ("hunt", "run")


class Torpedo:
    def __init__(self, x, y, hdg, spec):
        self.x, self.y, self.hdg = x, y, hdg
        self.kn = spec.kn
        self.rng = spec.range_m
        self.wake = spec.wake
        self.run = 0.0
        self.trail = [(x, y)]


class DepthCharge:
    def __init__(self, x, y, set_depth):
        self.x, self.y = x, y
        self.z = 0.0
        self.set = set_depth


class Fx:
    def __init__(self, kind, x, y, t0, life, size=1.0):
        self.kind, self.x, self.y, self.t0, self.life, self.size = kind, x, y, t0, life, size


class World:
    def __init__(self, nat, spec, demo=False):
        self.nat = nat
        self.spec = spec
        self.demo = demo
        self.t = 0.0
        self.tc = 1
        self.tod = spec.tod
        self.vis = VISIBILITY[spec.tod]
        self.sub = Sub(nat)
        self.ships = []
        self.torps = []
        self.dcs = []
        self.fx = []
        self.log = []
        self.events = []
        self.lock = None
        self.lock_obs = 0.0
        self.lock_err = (0.0, 0.0)
        self.alert = False
        self.fired = self.hits = self.duds = self.esc_sunk = 0
        self.result = None
        self.end_delay = 0.0
        self.shake = 0.0
        self.ping_flash = 0.0
        self.next_ping = 0.0
        self.ram_cool = 0.0
        self._throttle = {}
        self._once = set()
        self.depths = [d for d in (0, 12, 30, 60, 100, 150, 200) if d < nat.test] + [int(nat.test)]
        self._spawn()
        if not demo:
            self.report(f"Conn: patrol station reached. Hunting {self.target.name}.", "good")
            self.report("Sonar: listening. Raise the scope and find her.", "info")
        self._observe(0.0)

    # ------------------------------------------------------------------ setup
    def _spawn(self):
        sp = self.spec
        s = self.sub
        tgt = Ship(name=PREFIX[sp.nation] + sp.name, short=sp.name, nation=sp.nation,
                   type=sp.type, length=sp.length, beam=sp.beam, hp=sp.hp, max_hp=sp.hp,
                   is_target=True, max_kn=sp.kn, zig=sp.zig)
        tgt.cruise = sp.kn if sp.kn < 4 else sp.kn * 0.85
        if sp.kn < 4:
            tgt.x = random.uniform(-1200, 1200)
            tgt.y = random.uniform(5200, 6600)
            tgt.hdg = random.uniform(0, 360)
        else:
            side = random.choice((-1, 1))
            tgt.y = random.uniform(2800, 4200)
            tgt.x = -side * random.uniform(7200, 8600)
            tgt.hdg = 90.0 if side > 0 else 270.0
        tgt.base_hdg = tgt.leg = tgt.hdg
        tgt.spd = tgt.want_spd = tgt.cruise
        tgt.next_zig = random.uniform(90, 200)
        self.target = tgt
        self.ships.append(tgt)

        names = ESCORT_NAMES[sp.nation]
        for i in range(sp.escorts):
            e = Ship(name=PREFIX[sp.nation] + names[i], short=names[i], nation=sp.nation,
                     type="dd", length=115, beam=11, hp=1, max_hp=1, max_kn=33)
            if tgt.cruise < 4:
                e.orbit = True
                e.orb_a = i / sp.escorts * math.tau
                e.orb_r = random.uniform(1200, 1600)
                e.orb_dir = 1 if i % 2 == 0 else -1
                e.x = tgt.x + math.sin(e.orb_a) * e.orb_r
                e.y = tgt.y + math.cos(e.orb_a) * e.orb_r
                e.hdg = wrap(math.degrees(e.orb_a) + 90 * e.orb_dir)
                e.spd = e.want_spd = 10
            else:
                e.off = STATIONS[i]
                e.x, e.y = self._station(tgt, e.off)
                e.hdg = tgt.hdg
                e.spd = e.want_spd = tgt.cruise
            self.ships.append(e)

    @staticmethod
    def _station(tgt, off):
        f, r = off
        h = tgt.hdg * RAD
        return (tgt.x + math.sin(h) * f + math.cos(h) * r,
                tgt.y + math.cos(h) * f - math.sin(h) * r)

    @property
    def escorts(self):
        return [e for e in self.ships if not e.is_target]

    # ------------------------------------------------------------- messages
    def report(self, text, kind="info", key=None, every=0.0):
        if self.demo:
            return
        if key is not None:
            last = self._throttle.get(key, -1e9)
            if self.t - last < every:
                return
            self._throttle[key] = self.t
        self.log.append((self.t, text, kind))
        if len(self.log) > 80:
            del self.log[:20]

    def once(self, key, text, kind="info"):
        if key in self._once:
            return
        self._once.add(key)
        self.report(text, kind)

    def emit(self, kind, vol=1.0):
        if not self.demo:
            self.events.append((kind, vol))

    # ---------------------------------------------------------------- orders
    def set_telegraph(self, i):
        self.sub.tel = int(clamp(i, 0, len(TELEGRAPH) - 1))

    def set_rudder(self, i):
        self.sub.rud_i = int(clamp(i, 0, len(RUDDER) - 1))

    def set_depth(self, d, crash=False):
        s = self.sub
        s.dep_ord = float(d)
        s.crash = crash
        if crash:
            self.report("Dive, dive! Flood negative, all hands forward!", "warn")
            self.emit("klaxon")
        elif d == 0:
            self.report("Diving officer: surfacing. Blow main ballast.", "info")
        else:
            self.report(f"Diving officer: make my depth {int(d)} metres.", "info")

    def depth_step(self, step):
        s = self.sub
        ds = self.depths
        cur = min(range(len(ds)), key=lambda i: abs(ds[i] - s.dep_ord))
        self.set_depth(ds[int(clamp(cur + step, 0, len(ds) - 1))])

    def toggle_scope(self):
        s = self.sub
        if s.surfaced:
            self.report("On the surface. You're looking from the bridge.", "info")
            return
        if s.scope:
            s.scope = False
            self.report("Down scope.", "info")
        elif s.depth > PERI_MAX:
            self.report(f"Too deep to raise the scope. Come up to {int(PERI_MAX - 2.5)} metres.", "warn")
        else:
            s.scope = True
            self.report("Up scope.", "info")

    # --------------------------------------------------------------- weapons
    def lock_ship(self, sh):
        if sh is None or not sh.alive:
            return
        if self.lock is not sh:
            self.lock_obs = 0.0
            self.lock_err = (gauss(), gauss())
        self.lock = sh
        self.report(f"TDC: locked on {sh.name}. Keep her in sight to refine the solution.", "good")

    def lock_nearest(self):
        s = self.sub
        if not s.can_see:
            self.report("Can't take a bearing with the scope down.", "warn")
            return
        view = wrap(s.hdg + s.scope_rel)
        fov = 7.5 if s.zoom else 30.0
        best, score = None, 1e9
        for sh in self.ships:
            if not sh.alive:
                continue
            if dist(s.x, s.y, sh.x, sh.y) > self.vis:
                continue
            rel = abs(adiff(bearing(s.x, s.y, sh.x, sh.y), view))
            if rel > fov / 2:
                continue
            sc = rel - (0.75 if sh.is_target else 0)
            if sc < score:
                best, score = sh, sc
        if best:
            self.lock_ship(best)
        else:
            self.report("Nothing in the reticle to lock.", "warn")

    def solution(self):
        sh = self.lock
        if sh is None or not sh.alive:
            return None
        s = self.sub
        q = clamp(self.lock_obs / 12.0, 0.0, 1.0)
        err = 1.0 - q
        vs = sh.spd * (1 + self.lock_err[0] * 0.3 * err)
        hs = sh.hdg + self.lock_err[1] * 15 * err
        vx = math.sin(hs * RAD) * vs * KN
        vy = math.cos(hs * RAD) * vs * KN
        dx, dy = sh.x - s.x, sh.y - s.y
        S = self.nat.torp.kn * KN
        a = vx * vx + vy * vy - S * S
        b = 2 * (dx * vx + dy * vy)
        c = dx * dx + dy * dy
        if abs(a) < 1e-9:
            if abs(b) < 1e-9:
                return None
            ts = [-c / b]
        else:
            disc = b * b - 4 * a * c
            if disc < 0:
                return None
            r = math.sqrt(disc)
            ts = [(-b - r) / (2 * a), (-b + r) / (2 * a)]
        ts = [t for t in ts if t > 0]
        if not ts:
            return None
        t = min(ts)
        hdg = bearing(s.x, s.y, sh.x + vx * t, sh.y + vy * t)
        run = S * t
        return {"hdg": hdg, "t": t, "run": run, "q": q,
                "gyro": adiff(hdg, s.hdg), "in_range": run <= self.nat.torp.range_m}

    def fire(self, n=1):
        if self.result or self.demo:
            return
        s, N = self.sub, self.nat
        if s.depth > FIRE_MAX:
            self.report(f"Too deep to fire. Come above {int(FIRE_MAX)} metres.", "warn")
            return
        loaded = [i for i, v in enumerate(s.tubes) if v == 0]
        if not loaded:
            self.report("Torpedo room: no tubes loaded!", "warn")
            return
        sol = self.solution() if self.lock else None
        base = sol["hdg"] if sol else wrap(s.hdg + s.scope_rel)
        if abs(adiff(base, s.hdg)) > 90:
            self.report("Gyro angle over 90 degrees. Swing the bow toward the target.", "warn")
            return
        offsets = [-1.6, 0.0, 1.6] if n == 3 else [0.0]
        tubes_used = []
        for o in offsets:
            if not loaded:
                break
            i = loaded.pop(0)
            h = wrap(base + o)
            tp = Torpedo(s.x + math.sin(s.hdg * RAD) * 30, s.y + math.cos(s.hdg * RAD) * 30, h, N.torp)
            self.torps.append(tp)
            if s.spares > 0:
                s.tubes[i] = RELOAD
                s.spares -= 1
            else:
                s.tubes[i] = -1
            tubes_used.append(str(i + 1))
        self.fired += len(tubes_used)
        self.emit("launch")
        aim = "on the TDC solution" if sol else f"bearing {p3(base)}"
        what = "Torpedo" if len(tubes_used) == 1 else f"Spread of {len(tubes_used)}"
        self.report(f"{what} away from tube {', '.join(tubes_used)}, {aim}. Running {N.torp.kn:g} knots.", "good")
        if sol and not sol["in_range"]:
            self.report("TDC: target is beyond torpedo range. It may run dry.", "warn")

    # ----------------------------------------------------------------- update
    def update(self, dt):
        if self.demo:
            return
        self.t += dt
        self._update_sub(dt)
        for sh in self.ships:
            if sh.dead:
                continue
            if sh.hp <= 0:
                self._sink(sh, dt)
                continue
            if sh.is_target:
                self._target_ai(sh, dt)
            else:
                self._escort_ai(sh, dt)
            self._move(sh, dt)
        self._update_torps(dt)
        self._update_dcs(dt)
        self._observe(dt)
        self._pings()
        self.fx = [f for f in self.fx if self.t - f.t0 < f.life]
        self.shake = max(0.0, self.shake - dt * 1.2)
        self.ping_flash = max(0.0, self.ping_flash - dt * 1.5)
        if any(e.alive and e.state != "screen" for e in self.escorts):
            self.tc = min(self.tc, 4)
        self._check_end()

    def _update_sub(self, dt):
        s, N = self.sub, self.nat
        surf = s.surfaced
        max_kn = N.surf_kn if surf else N.sub_kn
        if not surf and s.bat <= 0:
            max_kn = 1.5
        if s.hull < 35:
            max_kn *= 0.6
        want = TELEGRAPH[s.tel][1] * max_kn
        s.spd += clamp(want - s.spd, -0.25 * dt, 0.25 * dt)
        s.rud += clamp(RUDDER[s.rud_i][0] - s.rud, -10 * dt, 10 * dt)
        turn = (s.rud / 35.0) * 3.2 * clamp(abs(s.spd) / 4.0, 0, 1) * (1 if s.spd >= 0 else -1)
        s.hdg = wrap(s.hdg + turn * dt)
        v = s.spd * KN
        s.x += math.sin(s.hdg * RAD) * v * dt
        s.y += math.cos(s.hdg * RAD) * v * dt

        rate = 2.2 if s.crash else 0.9
        s.depth += clamp(s.dep_ord - s.depth, -rate * dt, rate * dt)
        if s.crash and abs(s.depth - s.dep_ord) < 0.5:
            s.crash = False
        if s.hull < 25 and not surf:
            s.depth += 0.08 * dt
            self.once("flood", "Flooding in the after torpedo room! We're getting heavy.", "alarm")
        s.depth = max(0.0, s.depth)
        if not surf and s.scope and s.depth > PERI_MAX:
            s.scope = False
            self.report("Scope lowered, we're going under.", "info")
        if surf:
            s.scope = True

        if not surf:
            drain = 0.004 + 0.11 * (abs(s.spd) / N.sub_kn) ** 2
            s.bat = max(0.0, s.bat - drain * dt)
            s.air = max(0.0, s.air - 0.012 * dt)
            if s.bat < 20:
                self.once("bat20", "Electrician: battery under 20 percent. Slow down or surface to charge.", "warn")
            if s.bat <= 0:
                self.once("bat0", "Electrician: battery flat! We can only creep.", "alarm")
        else:
            s.bat = min(100.0, s.bat + 0.12 * dt)
            s.air = min(100.0, s.air + 1.0 * dt)
        if s.air <= 0:
            s.hull -= 0.05 * dt

        if s.depth > N.test:
            over = (s.depth - N.test) / (N.crush - N.test)
            s.hull -= over * 2.5 * dt
            self.report(f"The hull is groaning. We're below test depth ({int(N.test)} m)!", "alarm", "creak", 18)
            if self._throttle.get("creak") == self.t:
                self.emit("creak")
        if s.depth >= N.crush:
            s.hull = 0
            self._end("crushed", 3.0)

        for i, v in enumerate(s.tubes):
            if v > 0:
                v -= dt
                if v <= 0:
                    v = 0.0
                    self.report(f"Torpedo room: tube {i + 1} reloaded.", "info")
                s.tubes[i] = v

    # ------------------------------------------------------------ ship motion
    @staticmethod
    def _steer(sh, want, dt, rate):
        d = adiff(want, sh.hdg)
        sh.hdg = wrap(sh.hdg + clamp(d, -rate * dt, rate * dt))

    @staticmethod
    def _move(sh, dt):
        sh.spd += clamp(sh.want_spd - sh.spd, -0.5 * dt, 0.5 * dt)
        v = sh.spd * KN
        sh.x += math.sin(sh.hdg * RAD) * v * dt
        sh.y += math.cos(sh.hdg * RAD) * v * dt

    def _sink(self, sh, dt):
        sh.want_spd = 0
        sh.spd = max(0.0, sh.spd - dt)
        sh.sinking = min(1.0, sh.sinking + dt / (45.0 if sh.is_target else 30.0))
        if sh.sinking >= 1.0:
            sh.dead = True
            if self.lock is sh:
                self.lock = None

    def _target_ai(self, sh, dt):
        s = self.sub
        if sh.max_kn < 4:
            sh.want_spd = sh.cruise
            self._steer(sh, sh.leg, dt, 0.5)
            return
        if self.alert:
            sh.want_spd = sh.max_kn
            r = dist(s.x, s.y, sh.x, sh.y)
            away = bearing(s.x, s.y, sh.x, sh.y)
            self._steer(sh, away if r < 7000 else sh.leg, dt, 1.0)
            if r >= 7000:
                sh.leg = away
            return
        if sh.zig and self.t > sh.next_zig:
            sh.leg = wrap(sh.base_hdg + random.uniform(-35, 35))
            sh.next_zig = self.t + random.uniform(150, 260)
        sh.want_spd = sh.cruise
        self._steer(sh, sh.leg, dt, 1.0)

    def _escort_ai(self, e, dt):
        s, tgt = self.sub, self.target
        r = dist(e.x, e.y, s.x, s.y)
        self._detect(e, r, dt)
        if e.state == "screen":
            if e.orbit:
                e.orb_a += e.orb_dir * (11 * KN / e.orb_r) * dt
                lead = e.orb_a + e.orb_dir * 0.25
                px = tgt.x + math.sin(lead) * e.orb_r
                py = tgt.y + math.cos(lead) * e.orb_r
            else:
                px, py = self._station(tgt, e.off)
            d = dist(e.x, e.y, px, py)
            want = bearing(e.x, e.y, px, py) if (d > 80 or e.orbit) else tgt.hdg
            self._steer(e, want, dt, 3.0)
            base = 11.0 if e.orbit else tgt.spd
            e.want_spd = clamp(base + d / 120.0, 5, 30)
        elif e.state == "hunt":
            ex, ey = e.est
            d = dist(e.x, e.y, ex, ey)
            self._steer(e, bearing(e.x, e.y, ex, ey), dt, 3.5)
            e.want_spd = 24 if d > 900 else 13
            if d < 110:
                e.state = "run"
                e.to_drop = 5
                e.next_dc = self.t
                e.run_until = self.t + 35
                if r < 3000:
                    self.report("Splashes astern of the destroyer. Depth charges!", "alarm", "dcdrop", 10)
                    self.tc = 1
            elif self.t - e.last_fix > 75:
                e.state = "search"
                e.search_until = self.t + 100
        elif e.state == "run":
            e.want_spd = 20
            if e.to_drop > 0 and self.t >= e.next_dc:
                self._drop(e)
                e.to_drop -= 1
                e.next_dc = self.t + 2.2
            if self.t > e.run_until and e.to_drop == 0:
                if self.t - e.last_fix < 45:
                    e.state = "hunt"
                else:
                    e.state = "search"
                    e.search_until = self.t + 100
        elif e.state == "search":
            ex, ey = e.est
            a = self.t * 0.06 + e.id
            px, py = ex + math.sin(a) * 600, ey + math.cos(a) * 600
            self._steer(e, bearing(e.x, e.y, px, py), dt, 3.0)
            e.want_spd = 12
            if self.t > e.search_until:
                e.state = "screen"
                e.detect = 0.0
                self.report(f"Sonar: {e.short} has slowed and is rejoining the screen. I think we lost them.", "good")
        if r < 35 and s.depth < 9 and self.t > self.ram_cool:
            s.hull -= 55
            self.ram_cool = self.t + 15
            self.shake = 1.0
            self.emit("boom", 1.0)
            self.report(f"Collision! {e.short} rammed us!", "alarm")

    def _detect(self, e, r, dt):
        s = self.sub
        spd = abs(s.spd)
        rate = 0.0
        if s.surfaced:
            R = self.vis * 0.8
            if r < R:
                rate += 0.25 * (1 - r / R) + 0.05
        else:
            if s.scope and s.depth <= PERI_MAX:
                R = self.vis * 0.3
                if r < R:
                    rate += 0.045 * (1 - r / R) * (1 + spd / 4)
            A = 1600.0
            if r < A:
                f = (1 - r / A) * (0.12 + (spd / 8) ** 2 * 0.8) * 0.25
                if s.depth > 70:
                    f *= 0.5
                if e.spd > 18:
                    f *= 0.3
                rate += f
            if spd > 4 and r < 2800:
                rate += (spd - 4) / 12 * (1 - r / 2800) * 0.25
        # Contact builds only while the signal beats the operators' fatigue and
        # clutter; a quiet, deep boat lets the meter bleed away even when close.
        e.detect = clamp(e.detect + (rate - 0.02) * dt, 0.0, 1.3)
        if e.detect >= 0.7 and rate > 0.02 and self.t - e.last_fix > 3:
            err = 25 + r * 0.04
            e.est = (s.x + gauss() * err, s.y + gauss() * err)
            e.est_depth = s.depth + gauss() * (8 + s.depth * 0.12)
            e.last_fix = self.t
        if e.detect >= 1.0 and e.state in ("screen", "search") and e.est is not None:
            e.state = "hunt"
            b = bearing(s.x, s.y, e.x, e.y)
            self.report(f"Sonar: {e.short} bearing {p3(b)} is turning toward us. Fast screws!", "alarm")
            self.tc = 1

    def _drop(self, e):
        fresh = self.t - e.last_fix < 20
        sd = e.est_depth + gauss() * (6 if fresh else 25)
        self.dcs.append(DepthCharge(e.x + gauss() * 15, e.y + gauss() * 15, clamp(sd, 10, 260)))

    def _pings(self):
        s = self.sub
        if self.t < self.next_ping:
            return
        for e in self.escorts:
            if e.alive and e.hunting and dist(e.x, e.y, s.x, s.y) < 3000:
                self.emit("ping", 0.8)
                self.ping_flash = 1.0
                self.next_ping = self.t + 3.5
                return

    # --------------------------------------------------------------- weapons
    def _update_torps(self, dt):
        for tp in list(self.torps):
            step = tp.kn * KN * dt
            tp.x += math.sin(tp.hdg * RAD) * step
            tp.y += math.cos(tp.hdg * RAD) * step
            tp.run += step
            lx, ly = tp.trail[-1]
            if dist(lx, ly, tp.x, tp.y) > 60:
                tp.trail.append((tp.x, tp.y))
            hit = None
            for sh in self.ships:
                if sh.alive and self._inside(sh, tp.x, tp.y):
                    hit = sh
                    break
            if hit:
                self.torps.remove(tp)
                self._torp_hit(tp, hit)
            elif tp.run > tp.rng:
                self.torps.remove(tp)
                if not self.result:
                    self.report("Sonar: a torpedo has run its course and sunk. Miss.", "warn")

    @staticmethod
    def _inside(sh, x, y):
        h = sh.hdg * RAD
        dx, dy = x - sh.x, y - sh.y
        along = dx * math.sin(h) + dy * math.cos(h)
        across = dx * math.cos(h) - dy * math.sin(h)
        return abs(along) < sh.length / 2 and abs(across) < sh.beam / 2 + 3

    def _torp_hit(self, tp, sh):
        s = self.sub
        r = dist(s.x, s.y, sh.x, sh.y)
        if tp.run < ARM_DIST:
            self.duds += 1
            self.emit("thud", 0.6)
            self.report(f"A clang against {sh.short}... the warhead hadn't armed yet. Too close!", "warn")
        elif random.random() < self.nat.torp.dud:
            self.duds += 1
            self.emit("thud", 0.6)
            self.report(f"Hit on {sh.short}, but no explosion. A dud!", "warn")
        else:
            sh.hp -= 1
            self.hits += 1
            sh.max_kn *= 0.85
            sh.cruise = min(getattr(sh, "cruise", sh.max_kn), sh.max_kn)
            self.fx.append(Fx("boom", tp.x, tp.y, self.t, 7.0, sh.length / 200.0))
            self.emit("boom", clamp(1.2 - r / 8000, 0.3, 1.0))
            self.tc = 1
            if sh.hp <= 0:
                if sh.is_target:
                    self.report(f"She's breaking up! {sh.name} is going down!", "good")
                    self._end("win", 9.0)
                else:
                    self.esc_sunk += 1
                    self.report(f"{sh.name} is sinking! Escort destroyed.", "good")
            else:
                left = sh.hp
                self.report(f"Explosion! Torpedo hit on {sh.short}. She's slowing. "
                            f"Damage estimate: {left} more hit{'s' if left > 1 else ''} needed.", "good")
        self.alert = True
        err = 350 if self.nat.torp.wake else 700
        for e in self.escorts:
            if e.alive and e.state in ("screen", "search"):
                e.state = "hunt"
                e.est = (s.x + gauss() * err, s.y + gauss() * err)
                e.est_depth = s.depth + gauss() * 20
                e.last_fix = self.t
                e.detect = max(e.detect, 0.8)
        if self.escorts:
            self.once("escorts_alert", "Sonar: all escorts increasing speed! They're coming for us.", "alarm")

    def _update_dcs(self, dt):
        s = self.sub
        for dc in list(self.dcs):
            dc.z += 3.2 * dt
            if dc.z < dc.set:
                continue
            self.dcs.remove(dc)
            d3 = math.sqrt((dc.x - s.x) ** 2 + (dc.y - s.y) ** 2 + (dc.z - s.depth) ** 2)
            dmg = 38 if d3 < 10 else 20 if d3 < 25 else 9 if d3 < 45 else 3 if d3 < 80 else 0
            s.hull = max(0.0, s.hull - dmg)
            self.shake = max(self.shake, clamp(1 - d3 / 160, 0, 1))
            self.fx.append(Fx("dc", dc.x, dc.y, self.t, 6.0))
            self.emit("dc", clamp(1.1 - d3 / 500, 0.15, 1.0))
            if dmg >= 20:
                self.report(f"Very close! Gauges smashed, leaks forward. Hull at {s.hull:.0f}%.", "alarm")
            elif dmg > 0:
                self.report(f"Close one. Hull at {s.hull:.0f}%.", "warn")
            elif d3 < 250:
                self.report("Depth charge, not close.", "info", "dcfar", 6)

    # ------------------------------------------------------------- sensors
    def _observe(self, dt):
        s = self.sub
        see = s.can_see
        own = abs(s.spd)
        hear_r = (6000 if own > 7 else 13000) * (0.5 if s.surfaced else 1.0)
        for sh in self.ships:
            if sh.dead:
                sh.heard = False
                continue
            r = dist(s.x, s.y, sh.x, sh.y)
            sh.heard = r < hear_r and (sh.spd > 0.6 or r < 2500 or sh.sinking > 0)
            if sh.heard and not sh.ever_heard:
                sh.ever_heard = True
                b = p3(bearing(s.x, s.y, sh.x, sh.y))
                if sh.type == "dd":
                    self.report(f"Sonar: fast, light screws bearing {b}. Destroyer.", "info")
                else:
                    self.report(f"Sonar: heavy screws bearing {b}. Big ship!", "good")
            if see and r < self.vis:
                sh.plot = (sh.x, sh.y, sh.hdg, sh.spd, self.t)
                if not sh.ever_seen:
                    sh.ever_seen = True
                    b = p3(bearing(s.x, s.y, sh.x, sh.y))
                    if sh.is_target:
                        self.report(f"Conn: {sh.name} in sight, bearing {b}! Range {r / 1000:.1f} km.", "good")
                    else:
                        self.report(f"Conn: escort destroyer in sight, bearing {b}.", "info")
        if self.lock is not None:
            if not self.lock.alive:
                self.lock = None
            elif see and dist(s.x, s.y, self.lock.x, self.lock.y) < self.vis:
                self.lock_obs += dt

    def threat(self):
        s = self.sub
        attacking = searching = False
        for e in self.escorts:
            if not e.alive:
                continue
            if e.hunting and dist(e.x, e.y, s.x, s.y) < 3500:
                attacking = True
            elif e.state != "screen":
                searching = True
        if attacking:
            return "UNDER ATTACK", "alarm"
        if searching:
            return "HUNTED", "warn"
        return "UNDETECTED", "good"

    # -------------------------------------------------------------- endings
    def _end(self, kind, delay):
        if self.result:
            return
        self.result = kind
        self.end_delay = delay
        self.tc = 1
        if kind in ("lost", "crushed"):
            self.emit("boom", 1.0)

    def _check_end(self):
        if self.result:
            return
        s, tgt = self.sub, self.target
        if s.hull <= 0:
            self.report("We're breaking up! All hands...", "alarm")
            self._end("lost", 3.0)
        elif tgt.alive and dist(s.x, s.y, tgt.x, tgt.y) > ESCAPE:
            self.report(f"Sonar: lost {tgt.short}'s screws. She got away.", "warn")
            self._end("escaped", 2.5)
        elif tgt.alive and not self.torps and all(v < 0 for v in s.tubes):
            self.report("Torpedo room: that was our last fish.", "warn")
            self._end("dry", 2.5)
