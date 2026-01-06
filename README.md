# render (C + SDL3.4)

## Build

From the repo root:

```bash
cmake -S . -B build
cmake --build build
```

Run:

```bash
./build/render
```

## Build using a system SDL3 instead

If you installed SDL3 via a package manager and it provides a CMake config package, try:

```bash
cmake -S . -B build -DUSE_SYSTEM_SDL3=ON
cmake --build build
```

If CMake can’t find it, you may need to provide `CMAKE_PREFIX_PATH`.