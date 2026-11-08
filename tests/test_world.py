"""Headless checks for the simulation. Run with: python -m pytest"""
import math

from silent_bearing.data import NATIONS
from silent_bearing.util import adiff, bearing
from silent_bearing.world import World


def every_mission():
    for nat in NATIONS.values():
        for spec in nat.targets:
            yield nat, spec


def test_every_mission_runs_without_errors():
    for nat, spec in every_mission():
        w = World(nat, spec)
        for _ in range(3000):        # five minutes of game time
            w.update(0.1)
        assert w.sub.hull >= 0


def test_solution_leads_a_crossing_target():
    nat = NATIONS["uk"]
    w = World(nat, nat.targets[0])
    s, tg = w.sub, w.target
    tg.x, tg.y, tg.hdg, tg.spd = -1500.0, 1500.0, 90.0, 15.0
    w.lock = tg
    w.lock_obs = 20
    sol = w.solution()
    assert sol is not None
    # Target moves east, so the aim point must be east of her present bearing.
    assert adiff(sol["hdg"], bearing(s.x, s.y, tg.x, tg.y)) > 0


def test_a_torpedo_on_the_solution_hits_a_steady_target():
    nat = NATIONS["jp"]
    spec = next(t for t in nat.targets if t.id == "indianapolis")
    w = World(nat, spec)
    s, tg = w.sub, w.target
    tg.x, tg.y, tg.hdg, tg.spd, tg.want_spd, tg.cruise = -1800.0, 1800.0, 90.0, 17.0, 17.0, 17.0
    tg.leg = 90.0
    s.hdg = 0.0
    s.scope_rel = adiff(bearing(0, 0, tg.x, tg.y), s.hdg)
    w.lock = tg
    w.lock_obs = 30
    hp = tg.hp
    w.fire(1)
    for _ in range(1200):
        w.update(0.1)
    assert tg.hp < hp or w.duds > 0


def test_crush_depth_ends_the_patrol():
    nat = NATIONS["us"]
    w = World(nat, nat.targets[0])
    w.sub.depth = nat.crush + 1
    w.update(0.1)
    assert w.result == "crushed"
