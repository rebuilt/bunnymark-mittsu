# Mittsu Bunnymark

A bunnymark sprite-rendering benchmark for Ruby using [Mittsu](https://github.com/danini-the-panini/mittsu)
(the local checkout in `mittsu/`) and the [`mittsu-opengl`](https://github.com/danini-the-panini/mittsu-opengl)
renderer. It pushes as many bouncing tinted bunnies as possible, modelled on the
classic raylib bunnymark and the Ruby/raylib port in the sibling
`bunnymark` project.

Each bunny is a `Mittsu::Sprite` with its own `SpriteMaterial` cloned from a
single texture-sharing base material (so per-bunny tinting costs one draw
call each).

## Requirements

- Ruby >= 2.6
- OpenGL 3.3+ capable hardware / drivers
- GLFW 3.3 runtime. On Ubuntu/Debian:

  ```sh
  sudo apt install libglfw3
  ```

  If GLFW is not installed in a standard location, point the renderer at it
  directly:

  ```sh
  export MITTSU_LIBGLFW_PATH=/path/to/libglfw.so.3
  ```

## Run

Mittsu is pulled in as a git submodule, so clone with it, or fetch it after a
plain clone:

```sh
git clone --recurse-submodules <repo-url>
cd bunnymark-mittsu

# ...or, in an existing checkout:
git submodule update --init

bundle install
bundle exec ruby main.rb
```

## Controls

| Input | Action |
| --- | --- |
| Left mouse (hold) | Spawn 100 bunnies at the cursor (up to 200,000 total) |
| Right mouse (hold) | Destroy 10 bunnies |
| `P` | Pause / resume |
| `F5` | Reset to the initial bunny count |
| `Q` / `Esc` | Quit |

Mittsu has no text rendering, so the stats the raylib version paints on screen
are printed to the console once per second:

```
bunnies:  2500 | fps:  60 | draw calls:   2501
```

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `BUNNY_COUNT` | `2500` | Number of bunnies spawned at start / on reset |
| `ADAPTIVE` | off | `1` adds 100 bunnies/s while fps >= 60, removes 5/s otherwise |
| `FAST` | on | `0` disables `lib/fast_sprites.rb` and uses the stock per-sprite renderer |
| `VSYNC` | off | `1` re-enables the gem's `SwapInterval 1` (frames counted uncapped) |
| `SCREENSHOT` | off | Save a screenshot after ~20 frames, then quit (headless verification) |
| `DURATION` | off | Seconds to run before quitting (timed benchmark runs) |
| `MITTSU_LIBGLFW_PATH` | auto | Path to `libglfw.so.3` if GLFW isn't on the default search path |
| `DEBUG` | off | `true` enables mittsu-opengl debug output |

The window is requested at 1280×720, but the benchmark adapts to the size the
platform actually grants (window managers and DPI setups can resize it); the
camera, simulation bounds and screenshots all use the real framebuffer size.

## Performance

The stock per-sprite `SpritePlugin` path re-uploads every uniform, re-binds the
shared texture, depth-sorts, and allocates a fresh Fiddle buffer per sprite
(~40 µs/sprite). `lib/fast_sprites.rb` replaces that hot loop with a batched
version: constants are uploaded once, the texture is bound once, and each
sprite costs a single reusable matrix upload + tint + draw call (no sort, no
matrix compose — `game_logic.rb` writes `matrix_world` directly). Toggle with
`FAST=0` to compare. Frame-time split at 4000 bunnies:

| phase | FAST=0 | FAST=1 |
| --- | ---: | ---: |
| game update (bounce loop) | 3.3 ms | 4.6 ms |
| scene matrix compose | 21.9 ms | skipped |
| sprite sort + view matrix | 18.3 ms | ~0 ms |
| sprite draw loop | 154.6 ms | **37.2 ms** |
| frame total | ~200 ms | **~44 ms** |

Frames are counted uncapped (vsync off), so the raw render cost shows through:

```console
$ for n in 500 1000 2000 4000 10000; do DURATION=5 BUNNY_COUNT=$n bundle exec ruby main.rb; done
bunnies:   500 | fps: 168 | draw calls:    501
bunnies:  1000 | fps:  93 | draw calls:   1001
bunnies:  2000 | fps:  46 | draw calls:   2001
bunnies:  4000 | fps:  23 | draw calls:   4001
bunnies: 10000 | fps:   9 | draw calls:  10001
```

The shape is the interesting result: throughput is still fixed per draw call,
but the fast path cuts the per-sprite cost roughly 4×. Your numbers will
differ with drivers and CPU; start small (`BUNNY_COUNT=500`) for a smooth
interactive feel.

## Project layout

- `main.rb` — window/renderer setup, render loop, input, stats.
- `lib/game_logic.rb` — bunny simulation (spawn, bounce, destroy, adaptive count).
- `lib/fast_sprites.rb` — batched sprite renderer (disabled with `FAST=0`).
- `resources/` — bunny textures (from the raylib bunnymark).
- `mittsu/` — the Mittsu checkout (git submodule) used via Bundler `path:`.