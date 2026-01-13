const std = @import("std");
const sdl = @import("sdl.zig").c;

pub const Window = struct {
    ref: *sdl.SDL_Window = undefined,
    w: c_int = 0,
    h: c_int = 0,
    pixel_w: c_int = 0,
    pixel_h: c_int = 0,

    pub fn init() !Window {
        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            std.debug.print("SDL_Init failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLInitFailed;
        }
        errdefer sdl.SDL_Quit();

        const window = sdl.SDL_CreateWindow("SDL3.4 + Zig", 800, 500, 0) orelse {
            std.debug.print("SDL_CreateWindow failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateWindowFailed;
        };
        errdefer sdl.SDL_DestroyWindow(window);

        var win_w: c_int = 0;
        var win_h: c_int = 0;
        if (!sdl.SDL_GetWindowSize(window, &win_w, &win_h)) {
            std.debug.print("SDL_GetWindowSize failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLWindowSizeQueryFailed;
        }

        var pixel_w: c_int = 0;
        var pixel_h: c_int = 0;
        if (!sdl.SDL_GetWindowSizeInPixels(window, &pixel_w, &pixel_h)) {
            std.debug.print("SDL_GetWindowSizeInPixels failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLWindowSizeQueryFailed;
        }

        std.debug.print("Window size: {d}x{d} | Pixel size: {d}x{d}\n", .{ win_w, win_h, pixel_w, pixel_h });

        return Window{
            .ref = window,
            .w = win_w,
            .h = win_h,
            .pixel_w = pixel_w,
            .pixel_h = pixel_h,
        };
    }

    pub fn deinit(self: Window) void {
        sdl.SDL_DestroyWindow(self.ref);
        sdl.SDL_Quit();
    }
};
