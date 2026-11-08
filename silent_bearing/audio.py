"""Procedurally generated sound. No audio files to ship.

Needs numpy. If numpy or a sound device is missing, the game runs silent.
"""
import pygame

RATE = 22050


class Audio:
    def __init__(self):
        self.ok = False
        self.on = True
        self.sounds = {}
        self.hum = None
        self.hum_ch = None
        try:
            import numpy as np
            self.np = np
            if not pygame.mixer.get_init():
                pygame.mixer.init(RATE, -16, 2, 512)
            pygame.mixer.set_num_channels(16)
            self._build()
            self.ok = True
        except Exception:
            self.ok = False

    # ---------------------------------------------------------------- build
    def _sound(self, mono):
        np = self.np
        peak = float(np.max(np.abs(mono))) or 1.0
        a = (mono / peak * 0.9 * 32767).astype(np.int16)
        st = np.ascontiguousarray(np.column_stack([a, a]))
        return pygame.sndarray.make_sound(st)

    def _t(self, secs):
        return self.np.arange(int(RATE * secs)) / RATE

    def _lowpass(self, x, n):
        np = self.np
        k = np.exp(-np.arange(n) / (n / 4.0))
        k /= k.sum()
        return np.convolve(x, k, mode="same")

    def _build(self):
        np = self.np
        rng = np.random.default_rng(7)

        t = self._t(2.4)
        ping = np.sin(2 * np.pi * 1250 * t) * np.minimum(1, t * 80) * np.exp(-t * 2.4)
        echo = np.zeros_like(ping)
        d = int(0.42 * RATE)
        echo[d:] = ping[:-d] * 0.3
        self.sounds["ping"] = self._sound(ping + echo)

        def boom(secs, lp, decay, crack):
            tt = self._t(secs)
            n = rng.uniform(-1, 1, len(tt))
            body = self._lowpass(n, lp) * np.exp(-tt * decay)
            thump = np.sin(2 * np.pi * (38 + 30 * np.exp(-tt * 6)) * tt) * np.exp(-tt * 3.5) * 0.8
            hi = n * np.exp(-tt * 30) * crack
            return body * 3 + thump + hi

        self.sounds["boom"] = self._sound(boom(3.5, 160, 1.3, 0.15))
        self.sounds["dc"] = self._sound(boom(2.8, 90, 1.9, 0.6))

        tt = self._t(0.9)
        n = rng.uniform(-1, 1, len(tt))
        whoosh = (self._lowpass(n, 6) - self._lowpass(n, 60)) * np.exp(-tt * 3.5) * np.minimum(1, tt * 20)
        thunk = np.sin(2 * np.pi * 70 * tt) * np.exp(-tt * 9)
        self.sounds["launch"] = self._sound(whoosh * 3 + thunk)

        tt = self._t(0.5)
        self.sounds["thud"] = self._sound(np.sin(2 * np.pi * 85 * tt) * np.exp(-tt * 10)
                                          + self._lowpass(rng.uniform(-1, 1, len(tt)), 30) * np.exp(-tt * 14) * 2)

        tt = self._t(1.8)
        f = 110 - 25 * tt
        creak = np.sin(2 * np.pi * np.cumsum(f) / RATE) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * tt)) \
            * np.minimum(1, tt * 4) * np.exp(-tt * 1.2)
        self.sounds["creak"] = self._sound(creak + self._lowpass(rng.uniform(-1, 1, len(tt)), 40) * 0.6)

        tt = self._t(1.6)
        kl = np.sign(np.sin(2 * np.pi * 420 * tt)) * ((tt % 0.4) < 0.28) * 0.5
        self.sounds["klaxon"] = self._sound(self._lowpass(kl, 4))

        # Seamless motor hum: whole cycles of each partial in a 2 s loop.
        tt = self._t(2.0)
        hum = sum(np.sin(2 * np.pi * f0 * tt) / (i + 1) for i, f0 in enumerate((50, 100, 150, 300)))
        hum += self._lowpass(rng.uniform(-1, 1, len(tt)), 200) * 2
        self.hum = self._sound(hum)

    # ----------------------------------------------------------------- play
    def play(self, name, vol=1.0):
        if not (self.ok and self.on):
            return
        snd = self.sounds.get(name)
        if snd:
            ch = snd.play()
            if ch:
                ch.set_volume(max(0.0, min(1.0, vol)))

    def ambience(self, active, speed=0.0):
        if not self.ok:
            return
        if active and self.on:
            if self.hum_ch is None or not self.hum_ch.get_busy():
                self.hum_ch = self.hum.play(-1)
            if self.hum_ch:
                self.hum_ch.set_volume(0.05 + min(abs(speed), 20) * 0.012)
        elif self.hum_ch is not None:
            self.hum_ch.stop()
            self.hum_ch = None

    def toggle(self):
        self.on = not self.on
        if not self.on:
            pygame.mixer.stop()
            self.hum_ch = None
        return self.on
