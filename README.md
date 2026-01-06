# render (Zig + SDL3.4)

## Prereqs (macOS)

- Zig: you already have `0.15.0-dev.*`
- Default build downloads SDL3 source into `vendor/SDL` and builds it locally.
- Tools needed for that default path: `git`, `cmake`, `ninja` (and Xcode CLT).

## Build / Run

```bash
zig build
zig build run
```

First build will (by default) clone SDL3 and run CMake to build it.

## Use system SDL3 instead

If you prefer installing SDL3 via Homebrew and skipping the vendored download/build:

```bash
brew install sdl3
zig build -Dvendored_sdl=false run
```

## If SDL3 isn’t found

If your SDL3 lives somewhere non-standard, pass an explicit prefix:

```bash
zig build -Dsdl3_prefix=$(brew --prefix) run
```