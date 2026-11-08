# Silent Bearing

A free and open source WWII submarine game built with [Godot 4](https://godotengine.org).
You command from inside the boat: walk the control room, raise the periscope, plot the
target, fire a spread, then dive away from the destroyers, sub-chasers and aircraft
hunting you. Surface to charge your batteries, man the deck gun or fight off planes
with the AA gun, if you dare.

Pick a navy (United States, United Kingdom, Germany or Japan), each with its own boat,
torpedo and deck gun, and go after one of twenty famous warships. Most are the real
submarine kills of the war, like *Shinano*, *Royal Oak*, *Ark Royal* and
*Indianapolis*. A few are what-ifs, like *Yamato* and *Tirpitz*.

The original 2D pygame version is preserved at the `v1.0.0` tag.

## Running it

### Prebuilt (Linux and Windows)

Every push to `main` builds standalone executables with GitHub Actions. Open the
**Actions** tab, pick the latest run and download an artifact. Pushing a tag such as
`v2.0.0` also attaches the builds to a GitHub release.

```bash
tar -xzf SilentBearing-linux-x86_64.tar.gz
./SilentBearing.x86_64
```

### From source

Install [Godot 4.7](https://godotengine.org/download) (the standard build, not .NET),
then either open `project.godot` in the editor and press Play, or run:

```bash
godot --path /path/to/Silent-Bearing
```

The project uses the Compatibility (OpenGL 3) renderer so it runs on older and
integrated GPUs. If you have a modern GPU you can switch to Forward+ in
Project Settings > Rendering.

## How to play

You start at periscope depth with the target over the horizon, somewhere ahead.

1. **Listen.** Press `7` for the hydrophones. Long strobes are loud, close ships.
2. **Look.** Press `2` (or walk to the attack periscope and press `E`). Train the scope
   with the mouse and switch power with the wheel. Keep looks short: escorts and
   aircraft can spot a periscope, especially if you're moving fast.
3. **Lock.** Put the ship in the reticle and press `L` or click. Keep her in sight so
   the torpedo data computer can refine her course and speed (the SOLN percentage).
4. **Set depth.** Torpedoes run under a ship if set deeper than her draft. `[` and `]`
   set the running depth. The TDC (`8`) tells you if it's too deep.
5. **Fire.** Close to 1,000 to 2,500 metres off her beam and press `Space` for one
   torpedo or `X` for a spread of three. Warheads don't arm for the first 250 metres.
6. **Survive.** When escorts turn on you, go deep (`F`, or `C` to crash dive), slow to
   1/3 or stop, and turn. Below the thermal layer their sonar works half as well.
   Don't stay below test depth for long.

### On the surface

Order the boat up with `R` until you surface. The diesels start and the battery charges.
Climb the ladder in the control room (or press `3`) to come out on the bridge. From
there you can walk the whole deck: climb down the ladders at the back of the conning
tower, walk to the deck gun and press `E` to man it, then aim with the mouse and fire
with the left button (right button for the sight). `E` or `Esc` steps you back off the
gun. The AA gun is manned the same way from the back of the bridge. `4` and `5` jump
straight to the guns.

Surfacing is dangerous: warships open fire and bracket you with each salvo until you
change course or speed, and aircraft spot surfaced boats from far away, then bomb and
strafe. **You are the captain, and if you die the patrol is over.** A bomb or shell
bursting close to you, or a strafing run across your part of the deck, can kill you.
When the lookouts call aircraft, dive, but get yourself below first: walk to the
conning tower hatch on the bridge (or the deck hatch near the gun) and press `E`.
Diving takes time (27 seconds for a Type VII, nearly a minute for an I-boat), a
countdown shows how long until the deck goes under, and anyone still up there drowns.

Press `V` at any time for a third-person view that follows the boat. Drag the mouse
to swing around her and use the wheel to zoom.

### Inside the boat

The whole pressure hull is walkable, bow to stern, through the oval watertight doors:
forward torpedo room, officers' country with the wardroom and radio room, control room,
galley, mess and crew berthing, the two engine rooms, the maneuvering room and the after
torpedo room (steering gear on the boats without stern tubes). The planesmen and
helmsman turn their wheels as the boat answers, torpedoes slide into the tubes while
reloading, the diesels clatter on the surface, and the lights go red at night or when
she's badly hurt.

### Controls

| Key | Action |
| --- | --- |
| `W A S D`, `Shift` | Walk around inside the boat or on deck |
| Mouse | Look, train the periscope, aim the guns |
| `E` | Use the station, ladder or hatch you're facing; step off a gun |
| `1` to `5` | Control room, periscope, go on deck, deck gun, AA gun |
| `6` to `9` | Plot table, hydrophones, TDC, damage board |
| `V` or `0` | Third-person view of the boat |
| `Up` / `Down` | Engine telegraph |
| `Left` / `Right` | Rudder |
| `R` / `F` | Order shallower / deeper (all the way up surfaces) |
| `C` | Crash dive |
| `P` | Raise or lower the periscope |
| `Z`, mouse wheel | Periscope power |
| `L`, left click | Lock target (periscope or binoculars on deck) |
| `Space` / `X` | Fire one torpedo / a spread of three |
| `[` `]` | Torpedo running depth |
| Left / right mouse | Fire / gun sight or binoculars |
| `T` | Time compression 1x, 4x, 16x |
| `Tab` | Plot table |
| `M` | Sound on or off |
| `F1` | Help |
| `F11` | Fullscreen |
| `Esc` | Leave a station or pause |

## What's simulated

- **Your boat:** separate surface (diesel) and submerged (electric) speeds, battery
  drain and charging, air going foul on long dives, dive and surface times per class,
  test and crush depth, flooding and pumps, and damage to individual systems
  (periscope, hydrophones, diesels, motors, planes, tubes, deck gun, pumps) that the
  crew repairs over time.
- **Torpedoes:** speed, range, wake or no wake, arming distance, running depth versus
  target draft, dud rates, gyro angles up to 90 degrees.
- **Escorts:** destroyers and sub-chasers with sonar and hydrophones, hunting and
  depth-charge runs, a thermal layer, ramming, and guns that fire on a surfaced boat or
  a periscope.
- **Aircraft:** patrol planes that spot surfaced boats, periscopes and shallow hulls,
  then bomb, strafe and call in the escorts. More arrive once the alarm is raised.
- **Lookouts:** targets that spot torpedo wakes in daylight and turn away, escorts that
  bracket you with gunfire, and crew reports for everything.

## The navies

| Navy | Boat | Torpedo | Deck gun | Notes |
| --- | --- | --- | --- | --- |
| United States | Gato-class | Mk 14, 46 kn, 4.1 km | 4-inch/50 | Big torpedo load |
| United Kingdom | T-class | Mk VIII, 45 kn, 4.6 km | 4-inch QF | Reliable six-tube salvo |
| Germany | Type VIIC | G7e, 30 kn, 5 km | 8.8 cm | Fast dive, very deep, wakeless |
| Japan | Type B1 | Type 95, 49 kn, 9 km | 14 cm | Long range, slow to dive |

Figures are rounded from published wartime specifications and adjusted for play.

## Project layout

```
project.godot              Godot project
scenes/main.tscn           entry scene (everything else is built in code)
scripts/
  data.gd                  navies, boats, aircraft, targets and ship layouts
  util.gd                  bearing and ballistics helpers
  sim/world.gd             the simulation: no rendering, fully testable
  build/                   procedural models: warships, your boat, aircraft, crew, islands
  view/                    ocean, sky, effects and the 3D world
  interior/                walkable eight-compartment interior, its textures and props, the player
  deck/                    walkable deck, bridge and hatches; lookouts and gun crew
  ui/                      HUD, sights, live instruments, menus
  audio/sfx.gd             procedurally synthesised sound
  game.gd                  modes, cameras, input and the game loop
shaders/                   ocean and sky
tests/run_tests.gd         headless simulation tests
tools/                     screenshot tools, plus walk and deck tests
```

Every model, sound and texture is generated in code, so there are no binary assets.
Ships are described as data in `scripts/data.gd`: turret positions, superstructure,
funnels and masts along the hull. Adding a ship is one entry there.

### Running the tests

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . -s tools/walk_test.gd -- us shokaku
godot --headless --path . -s tools/deck_test.gd -- - us shokaku
```

### Rendering previews

```bash
xvfb-run godot --path . --rendering-driver opengl3 -s tools/model_preview.gd -- /tmp/out
xvfb-run godot --path . --rendering-driver opengl3 -s tools/game_preview.gd -- /tmp/out de barham
xvfb-run godot --path . --rendering-driver opengl3 -s tools/interior_preview.gd -- /tmp/out us shokaku
```

## License

GPL-3.0. See [LICENSE](LICENSE).
