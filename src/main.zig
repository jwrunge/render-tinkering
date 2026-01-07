const std = @import("std");
const keys = @import("keys.zig");
const sdl = @import("sdl.zig").c;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        const err = std.mem.span(sdl.SDL_GetError());
        std.debug.print("SDL_Init failed: {s}\n", .{err});
        return error.SDLInitFailed;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("SDL3.4 + Zig", 800, 500, 0);
    if (window == null) {
        const err = std.mem.span(sdl.SDL_GetError());
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{err});
        return error.SDLCreateWindowFailed;
    }
    defer sdl.SDL_DestroyWindow(window);

    const keymap_path = try keys.defaultKeymapPath(allocator);
    defer allocator.free(keymap_path);

    var keymap = try keys.Keymap.initLoadOrDefault(keymap_path);
    try keymap.remapAndSave(.quit, sdl.SDLK_ESCAPE, keymap_path);

    var running = true;
    while (running) {
        var e: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&e)) {
            keymap.handleEvent(&e, &running);
        }

        sdl.SDL_Delay(16);
    }
}
