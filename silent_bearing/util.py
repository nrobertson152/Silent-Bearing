"""Small math and formatting helpers shared across the game.

World coordinates are metres with x pointing east and y pointing north.
Bearings and headings are in degrees, measured clockwise from north.
"""
import math
import random

RAD = math.pi / 180.0
KN = 0.514444  # metres per second in one knot


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def wrap(a):
    return a % 360.0


def adiff(a, b):
    """Signed difference a - b in degrees, in the range [-180, 180)."""
    return (a - b + 540.0) % 360.0 - 180.0


def bearing(ax, ay, bx, by):
    return math.degrees(math.atan2(bx - ax, by - ay)) % 360.0


def dist(ax, ay, bx, by):
    return math.hypot(bx - ax, by - ay)


def gauss():
    return random.gauss(0.0, 1.0)


def p3(a):
    """Format a bearing as three digits, e.g. 7 -> '007'."""
    return f"{int(round(a)) % 360:03d}"


def fmt_clock(seconds):
    s = int(seconds)
    return f"{s // 3600:02d}:{(s // 60) % 60:02d}:{s % 60:02d}"


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_color(a, b, t):
    t = clamp(t, 0.0, 1.0)
    return (int(a[0] + (b[0] - a[0]) * t),
            int(a[1] + (b[1] - a[1]) * t),
            int(a[2] + (b[2] - a[2]) * t))
