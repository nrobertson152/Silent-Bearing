"""Palette, fonts, buttons and small drawing helpers for the control room."""
import pygame


class Theme:
    """Control room colours. Night patrols switch the boat to red lighting."""

    def __init__(self):
        self.set_red(False)

    def set_red(self, red):
        self.red = red
        self.hull = (18, 22, 24) if not red else (22, 14, 14)
        self.plate = (30, 37, 40) if not red else (40, 24, 23)
        self.plate2 = (41, 50, 54) if not red else (56, 33, 31)
        self.seam = (10, 13, 14) if not red else (14, 7, 7)
        self.rivet = (66, 80, 82) if not red else (92, 52, 48)
        self.brass = (201, 165, 92) if not red else (214, 130, 92)
        self.brass_lo = (120, 97, 55) if not red else (128, 70, 50)
        self.text = (218, 214, 200) if not red else (236, 196, 184)
        self.muted = (138, 146, 141) if not red else (160, 116, 106)
        self.phos = (143, 220, 170)
        self.amber = (240, 180, 76)
        self.alarm = (232, 90, 64)
        self.good = (150, 205, 128)
        self.dial = (232, 224, 200) if not red else (226, 196, 180)
        self.ink = (33, 29, 22)

    def kind(self, k):
        return {"alarm": self.alarm, "warn": self.amber, "good": self.good}.get(k, self.text)


THEME = Theme()

_fonts = {}

_FACES = {
    "ui": "dejavusanscondensed,liberationsansnarrow,ubuntucondensed,arialnarrow,dejavusans,arial",
    "mono": "dejavusansmono,liberationmono,ubuntumono,consolas,couriernew",
    "display": "dejavusanscondensed,liberationsansnarrow,impact,arialnarrow,dejavusans",
}


def font(size, kind="ui", bold=False):
    key = (size, kind, bold)
    f = _fonts.get(key)
    if f is None:
        try:
            f = pygame.font.SysFont(_FACES[kind], size, bold=bold)
        except Exception:
            f = pygame.font.Font(None, int(size * 1.3))
        _fonts[key] = f
    return f


def text(surf, s, f, color, pos, anchor="topleft"):
    img = f.render(s, True, color)
    r = img.get_rect(**{anchor: pos})
    surf.blit(img, r)
    return r


def spaced(s, n=1):
    """Letter-space an uppercase label."""
    return (" " * n).join(s)


def wrap_text(s, f, width):
    words = s.split()
    lines, cur = [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if f.size(t)[0] <= width:
            cur = t
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def text_block(surf, s, f, color, x, y, width, line_gap=4):
    for line in wrap_text(s, f, width):
        text(surf, line, f, color, (x, y))
        y += f.get_linesize() + line_gap - 2
    return y


def plate(surf, rect, title=None, sub=None):
    """A riveted steel instrument plate with an engraved label."""
    t = THEME
    pygame.draw.rect(surf, t.seam, rect.inflate(4, 4), border_radius=6)
    pygame.draw.rect(surf, t.plate, rect, border_radius=5)
    pygame.draw.line(surf, t.plate2, (rect.left + 5, rect.top + 1), (rect.right - 6, rect.top + 1))
    for cx, cy in ((rect.left + 7, rect.top + 7), (rect.right - 8, rect.top + 7),
                   (rect.left + 7, rect.bottom - 8), (rect.right - 8, rect.bottom - 8)):
        pygame.draw.circle(surf, t.seam, (cx, cy + 1), 3)
        pygame.draw.circle(surf, t.rivet, (cx, cy), 3)
    if title:
        r = text(surf, spaced(title.upper()), font(13, "ui", True), t.brass, (rect.left + 18, rect.top + 6))
        if sub:
            text(surf, sub, font(12), t.muted, (r.right + 10, rect.top + 7))


class Button:
    def __init__(self, rect, label, on_click=None, active=None, hold=None, enabled=None,
                 style="normal", key_hint=None):
        self.rect = pygame.Rect(rect)
        self.label = label
        self.on_click = on_click
        self.active = active
        self.hold = hold            # callable(bool) for press-and-hold buttons
        self.enabled = enabled
        self.style = style
        self.key_hint = key_hint
        self.pressed = False

    def get_label(self):
        return self.label() if callable(self.label) else self.label

    def is_enabled(self):
        return self.enabled() if self.enabled else True

    def is_active(self):
        return bool(self.active()) if self.active else False

    def draw(self, surf, mouse):
        t = THEME
        en = self.is_enabled()
        act = self.is_active()
        hover = self.rect.collidepoint(mouse) and en
        r = self.rect
        if self.style == "fire":
            base = (120, 36, 26) if en else (60, 36, 32)
            if hover:
                base = (150, 46, 32)
            if self.pressed:
                base = (190, 60, 40)
            edge = t.alarm if en else t.seam
            fg = (255, 228, 212) if en else t.muted
        elif self.style == "big":
            base = t.brass if en else t.plate2
            if hover:
                base = tuple(min(255, c + 20) for c in base)
            edge = t.brass_lo
            fg = t.ink
        else:
            base = t.plate2
            if hover:
                base = tuple(min(255, c + 14) for c in base)
            if act:
                base = (64, 54, 34) if not t.red else (84, 40, 30)
            if self.pressed:
                base = tuple(min(255, c + 30) for c in base)
            edge = t.brass if act else t.seam
            fg = t.amber if act else (t.text if en else t.muted)
        pygame.draw.rect(surf, t.seam, r.move(0, 2), border_radius=4)
        pygame.draw.rect(surf, base, r, border_radius=4)
        pygame.draw.rect(surf, edge, r, 1, border_radius=4)
        if act and self.style == "normal":
            pygame.draw.circle(surf, t.amber, (r.left + 6, r.top + 6), 2)
        size = 15 if self.style != "big" else 18
        lbl = self.get_label()
        f = font(size, "ui", True)
        while f.size(lbl)[0] > r.w - 8 and size > 10:
            size -= 1
            f = font(size, "ui", True)
        text(surf, lbl, f, fg, r.center, "center")

    def handle(self, ev):
        if ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1 and self.rect.collidepoint(ev.pos):
            if not self.is_enabled():
                return True
            self.pressed = True
            if self.hold:
                self.hold(True)
            return True
        if ev.type == pygame.MOUSEBUTTONUP and ev.button == 1 and self.pressed:
            self.pressed = False
            if self.hold:
                self.hold(False)
            elif self.rect.collidepoint(ev.pos) and self.on_click:
                self.on_click()
            return True
        return False


def draw_badge(surf, nation, center, r):
    """Simple period national markings, drawn rather than imported."""
    cx, cy = center
    if nation == "us":
        pygame.draw.circle(surf, (32, 52, 104), center, r)
        _star(surf, (240, 240, 236), center, r * 0.86, r * 0.35)
    elif nation == "uk":
        pygame.draw.circle(surf, (32, 52, 104), center, r)
        pygame.draw.circle(surf, (236, 236, 230), center, int(r * 0.66))
        pygame.draw.circle(surf, (186, 40, 36), center, int(r * 0.34))
    elif nation == "de":
        pygame.draw.circle(surf, (66, 70, 66), center, r)
        w, a = r * 0.86, r * 0.30
        for rect in (pygame.Rect(0, 0, 2 * a + 6, 2 * w + 6), pygame.Rect(0, 0, 2 * w + 6, 2 * a + 6)):
            rect.center = center
            pygame.draw.rect(surf, (236, 236, 230), rect)
        for rect in (pygame.Rect(0, 0, 2 * a, 2 * w), pygame.Rect(0, 0, 2 * w, 2 * a)):
            rect.center = center
            pygame.draw.rect(surf, (20, 20, 20), rect)
    elif nation == "jp":
        pygame.draw.circle(surf, (236, 236, 230), center, r)
        pygame.draw.circle(surf, (188, 32, 40), center, int(r * 0.6))
    pygame.draw.circle(surf, THEME.brass, center, r, 2)


def _star(surf, color, c, ro, ri):
    import math
    pts = []
    for i in range(10):
        rr = ro if i % 2 == 0 else ri
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr))
    pygame.draw.polygon(surf, color, pts)
