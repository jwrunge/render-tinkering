# render (Zig + SDL3.4)

## Prereqs (macOS)

- Zig: you already have `0.15.0-dev.*`
- SDL3: `brew install sdl3`

## Build / Run

```bash
zig build
zig build run
```

## If SDL3 isn’t found

If your SDL3 lives somewhere non-standard, pass an explicit prefix:

```bash
zig build -Dsdl3_prefix=$(brew --prefix) run
```