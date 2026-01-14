const std = @import("std");
const sdl = @import("app/sdl.zig").c;
const App = @import("app/App.zig").App;

pub fn main() !void {
    // Init video & window, Settings, Inputs
    var app = try App.init();
    defer app.deinit();

    // Frame logging
    var frame_count: u64 = 0;
    var last_fps_time: i128 = std.time.nanoTimestamp();
    var sum_lock_fill_unlock_ns: u128 = 0;
    var sum_render_ns: u128 = 0;
    var sum_present_ns: u128 = 0;

    // MAIN LOOP
    var running = true;
    while (running) {
        // Handle input events
        var e: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&e)) {
            app.inputs.handleEvent(&e, &running);
        }

        // Render frame and update timings
        const timings = try app.renderer.render();
        sum_lock_fill_unlock_ns += timings.lock_fill_unlock_ns;
        sum_render_ns += timings.render_ns;
        sum_present_ns += timings.present_ns;
        frame_count += 1;

        // Update FPS counters
        const now: i128 = std.time.nanoTimestamp();
        const elapsed_ns: i128 = now - last_fps_time;
        if (elapsed_ns >= 1_000_000_000) {
            const fps: f64 = (@as(f64, @floatFromInt(frame_count)) * 1_000_000_000.0) /
                @as(f64, @floatFromInt(elapsed_ns));

            const denom: f64 = @as(f64, @floatFromInt(frame_count));
            const avg_lock_ms: f64 = (@as(f64, @floatFromInt(sum_lock_fill_unlock_ns)) / denom) / 1_000_000.0;
            const avg_render_ms: f64 = (@as(f64, @floatFromInt(sum_render_ns)) / denom) / 1_000_000.0;
            const avg_present_ms: f64 = (@as(f64, @floatFromInt(sum_present_ns)) / denom) / 1_000_000.0;

            std.debug.print(
                "FPS: {d:.1} | wait+acquire: {d:.3}ms | encode: {d:.3}ms | submit: {d:.3}ms\n",
                .{ fps, avg_lock_ms, avg_render_ms, avg_present_ms },
            );

            frame_count = 0;
            last_fps_time = now;

            sum_lock_fill_unlock_ns = 0;
            sum_render_ns = 0;
            sum_present_ns = 0;
        }

        // sdl.SDL_Delay(16);
    }
}
