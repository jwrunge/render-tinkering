const std = @import("std");
const input = @import("util/input.zig");
const sdl = @import("util/sdl.zig").c;
const renderer_mod = @import("renderer/renderer.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
        return error.SDLInitFailed;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("SDL3.4 + Zig", 800, 500, 0) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
        return error.SDLCreateWindowFailed;
    };
    defer sdl.SDL_DestroyWindow(window);

    var win_w: c_int = 0;
    var win_h: c_int = 0;
    if (!sdl.SDL_GetWindowSize(window, &win_w, &win_h)) {
        std.debug.print("SDL_GetWindowSize failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
        return error.SDLWindowSizeQueryFailed;
    }

    var input_map = try input.InputMap.init();

    var pixel_w: c_int = 0;
    var pixel_h: c_int = 0;
    if (!sdl.SDL_GetWindowSizeInPixels(window, &pixel_w, &pixel_h)) {
        std.debug.print("SDL_GetWindowSizeInPixels failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
        return error.SDLWindowSizeQueryFailed;
    }

    std.debug.print("Window size: {d}x{d} | Pixel size: {d}x{d}\n", .{ win_w, win_h, pixel_w, pixel_h });

    var requested_backend: renderer_mod.Backend = .cpu;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--gpu")) requested_backend = .gpu;
        if (std.mem.eql(u8, arg, "--cpu")) requested_backend = .cpu;
    }

    var renderer: renderer_mod.Renderer = undefined;
    try renderer.init(window, win_w, win_h, requested_backend);
    defer renderer.deinit();

    var frame_count: u64 = 0;
    var last_fps_time: i128 = std.time.nanoTimestamp();

    var sum_lock_fill_unlock_ns: u128 = 0;
    var sum_render_ns: u128 = 0;
    var sum_present_ns: u128 = 0;

    var running = true;
    while (running) {
        var e: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&e)) {
            input_map.handleEvent(&e, &running);
        }

        const timings = try renderer.render();
        sum_lock_fill_unlock_ns += timings.lock_fill_unlock_ns;
        sum_render_ns += timings.render_ns;
        sum_present_ns += timings.present_ns;

        frame_count += 1;
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
                "FPS: {d:.1} | lock+fill: {d:.3}ms | render: {d:.3}ms | present: {d:.3}ms\n",
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
