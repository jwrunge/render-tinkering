const std = @import("std");
const sdl = @import("sdl.zig").c;
const InputMap = @import("input.zig").InputMap;
const Renderer = @import("renderer/core.zig").Renderer;

pub const App = struct {
    window: *sdl.SDL_Window = undefined,
    w: c_int = 0,
    h: c_int = 0,
    pixel_w: c_int = 0,
    pixel_h: c_int = 0,
    scale_x: f32 = 1.0,
    scale_y: f32 = 1.0,
    inputs: InputMap = undefined,
    renderer: Renderer = undefined,

    fn refreshWindowMetrics(self: *App) !void {
        var win_w: c_int = 0;
        var win_h: c_int = 0;
        if (!sdl.SDL_GetWindowSize(self.window, &win_w, &win_h)) {
            std.debug.print("SDL_GetWindowSize failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLWindowSizeQueryFailed;
        }

        var pixel_w: c_int = 0;
        var pixel_h: c_int = 0;
        if (!sdl.SDL_GetWindowSizeInPixels(self.window, &pixel_w, &pixel_h)) {
            std.debug.print("SDL_GetWindowSizeInPixels failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLWindowSizeQueryFailed;
        }

        self.w = win_w;
        self.h = win_h;
        self.pixel_w = pixel_w;
        self.pixel_h = pixel_h;

        if (win_w > 0 and win_h > 0) {
            self.scale_x = @as(f32, @floatFromInt(pixel_w)) / @as(f32, @floatFromInt(win_w));
            self.scale_y = @as(f32, @floatFromInt(pixel_h)) / @as(f32, @floatFromInt(win_h));
        } else {
            self.scale_x = 1.0;
            self.scale_y = 1.0;
        }
    }

    /// Call from your main event loop; keeps window/pixel sizes and scale in sync.
    pub fn handleEvent(self: *App, e: *sdl.SDL_Event, running: *bool) void {
        switch (e.type) {
            sdl.SDL_EVENT_WINDOW_RESIZED,
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
            => {
                // Best-effort: if it fails, keep the old values.
                _ = self.refreshWindowMetrics() catch {};
            },
            else => {},
        }

        self.inputs.handleEvent(e, running);
    }

    pub fn init() !App {
        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            std.debug.print("SDL_Init failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLInitFailed;
        }
        errdefer sdl.SDL_Quit();

        const window = sdl.SDL_CreateWindow("SDL3.4 + Zig", 800, 500, sdl.SDL_WINDOW_RESIZABLE) orelse {
            std.debug.print("SDL_CreateWindow failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateWindowFailed;
        };
        errdefer sdl.SDL_DestroyWindow(window);

        const inputs = try InputMap.init();
        var app = App{
            .window = window,
            .inputs = inputs,
        };

        try app.refreshWindowMetrics();
        std.debug.print(
            "Window size: {d}x{d} | Pixel size: {d}x{d} | Scale: {d:.2}x{d:.2}\n",
            .{ app.w, app.h, app.pixel_w, app.pixel_h, app.scale_x, app.scale_y },
        );

        try app.renderer.init(&app);
        return app;
    }

    pub fn deinit(self: *App) void {
        self.inputs.deinit();
        self.renderer.deinit();
        sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
    }
};
