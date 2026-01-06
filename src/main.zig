const std = @import("std");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub fn main() !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        const err = std.mem.span(c.SDL_GetError());
        std.debug.print("SDL_Init failed: {s}\n", .{err});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("SDL3.4 + Zig", 800, 600, 0);
    if (window == null) {
        const err = std.mem.span(c.SDL_GetError());
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{err});
        return error.SDLCreateWindowFailed;
    }
    defer c.SDL_DestroyWindow(window);

    const autoclose_ms_env = c.SDL_getenv("RENDER_AUTOCLOSE_MS");
    const start_ms: u64 = @intCast(c.SDL_GetTicks());
    const autoclose_ms: u64 = if (autoclose_ms_env != null and autoclose_ms_env[0] != 0)
        @intCast(c.SDL_strtoull(autoclose_ms_env, null, 10))
    else
        0;

    var running = true;
    while (running) {
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e)) {
            if (e.type == c.SDL_EVENT_QUIT) {
                running = false;
            }
        }

        if (autoclose_ms > 0) {
            const now_ms: u64 = @intCast(c.SDL_GetTicks());
            if ((now_ms - start_ms) >= autoclose_ms) {
                running = false;
            }
        }

        c.SDL_Delay(16);
    }
}
