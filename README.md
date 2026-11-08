# Silent Bearing

A free and open source WWII submarine game. You command from inside the boat: work the
periscope, listen on the hydrophones, plot the target, then slip past the escorts and
sink a famous warship.

Pick a navy (United States, United Kingdom, Germany or Japan), each with its own boat
and torpedo, and go after one of twenty real warships. Most are the actual submarine
kills of the war, like *Shinano*, *Royal Oak*, *Ark Royal* and *Indianapolis*. A few are
what-ifs, like *Yamato* and *Tirpitz*.

## Running it

### From source (Linux, also works on Windows and macOS)

You need Python 3.10 or newer.

```bash
git clone https://github.com/nrobertson152/Silent-Bearing.git
cd Silent-Bearing
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

### Prebuilt executables

Every push to `main` builds standalone Linux and Windows executables with GitHub
Actions. Download them from the **Actions** tab (latest run, then *Artifacts*).
Pushing a tag such as `v0.1.0` also attaches them to a GitHub release.

On Linux, unpack and run:

```bash
tar -xzf SilentBearing-linux-x86_64.tar.gz
./SilentBearing
```

## How to play

You start at periscope depth with the target somewhere over the horizon.

1. **Find her.** Listen on the hydrophones, then raise the scope (`P`) and train it
   (arrow keys or drag the view) toward the strongest bearing.
2. **Lock on.** Put the ship in the reticle and press `L`, or click her. Keep her in
   sight for a while so the torpedo data computer can refine her course and speed.
   The data strip at the bottom of the lens shows range, angle on the bow, gyro angle
   and whether the shot is in range.
3. **Get close.** Torpedoes are slow. Close to 1,000 to 2,500 metres off her beam.
   Short looks with the scope are safer than leaving it up.
4. **Fire.** `Space` fires one torpedo on the solution, `X` fires a spread of three.
   Tubes take 45 seconds to reload.
5. **Survive.** When the escorts turn toward you, go deep (`F` or `C` for a crash
   dive), slow to 1/3 or stop, and change course. Destroyers hear fast, shallow boats
   easily. Going below 70 metres halves their sonar's chances, and the German Type VIIC
   can go much deeper than the rest. Don't go below test depth for long.

Watch your battery: running fast underwater drains it quickly. Surface to recharge,
if you dare.

### Controls

| Key | Action |
| --- | --- |
| `W` / `S` | Engine telegraph up / down |
| `A` / `D` | Rudder left / right |
| `R` / `F` | Order shallower / deeper |
| `C` | Crash dive |
| `P` | Raise or lower the periscope |
| `Left` / `Right` or drag | Train the periscope (hold `Shift` to train faster) |
| `B` | Swing the scope back to the bow |
| `Z` or mouse wheel on scope | Low / high power |
| `L` or click a ship | Lock target on the TDC |
| `Space` | Fire one torpedo |
| `X` | Fire a spread of three |
| `T` | Time compression (1x, 4x, 16x) |
| `M` or mouse wheel on chart | Plot table scale |
| `V` | Sound on / off |
| `Esc` | Pause menu |
| `F11` | Fullscreen |

Everything can also be done with the on-screen buttons.

## The navies

| Navy | Boat | Torpedo | Notes |
| --- | --- | --- | --- |
| United States | Gato-class | Mk 14, 46 kn, 4.1 km | Big torpedo load, but 15% duds |
| United Kingdom | T-class | Mk VIII, 45 kn, 4.6 km | Reliable, six-tube bow salvo |
| Germany | Type VIIC | G7e, 30 kn, 5 km | Slow, wakeless, dives very deep |
| Japan | Type B1 | Type 95, 49 kn, 9 km | Long range, fast, nearly wakeless |

Figures are rounded from published wartime specifications and adjusted where needed
for play.

## Project layout

```
main.py                     entry point
silent_bearing/
  data.py                   navies, boats, torpedoes and target warships
  world.py                  simulation: boat, ships, escort AI, torpedoes, depth charges
  scope.py                  periscope rendering and ship silhouettes
  instruments.py            hydrophone scope, plot table, dials and bars
  game.py                   window, layout, menus and input
  audio.py                  procedurally generated sound (needs numpy)
  ui.py                     palette, fonts and buttons
tests/                      headless simulation tests (python -m pytest)
```

The simulation in `world.py` doesn't depend on pygame, so it can be tested or reused
on its own. Adding a new target is a single entry in `data.py`.

## License

GPL-3.0. See [LICENSE](LICENSE).
