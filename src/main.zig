const std = @import("std");
const sdl = @import("app/sdl.zig").sdl;
const App = @import("app/App.zig").App;

pub fn main() !void {
    // Init video & window, Settings, Inputs
    var app = try App.init();
    defer app.deinit();

    // MAIN LOOP
    var running = true;
    while (running) {
        // Handle input events
        var e: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&e)) {
            app.handleEvent(&e, &running);
        }

        // Render frame and update timings
        try app.renderer.render(true);

        // sdl.SDL_Delay(16);
    }
}
