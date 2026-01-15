const std = @import("std");

const Timings = struct {
    lock_fill_unlock_ns: u128,
    render_ns: u128,
    present_ns: u128,
};

pub const RenderLogger = struct {
    frame_count: u64 = 0,
    last_fps_time: i128 = 0,
    sum_lock_fill_unlock_ns: u128 = 0,
    sum_render_ns: u128 = 0,
    sum_present_ns: u128 = 0,

    pub fn init() RenderLogger {
        return .{ .last_fps_time = std.time.nanoTimestamp() };
    }

    pub fn update_frame_timings(self: *RenderLogger, timings: Timings) void {
        self.sum_lock_fill_unlock_ns += timings.lock_fill_unlock_ns;
        self.sum_render_ns += timings.render_ns;
        self.sum_present_ns += timings.present_ns;
        self.frame_count += 1;

        // Update FPS counters
        const now: i128 = std.time.nanoTimestamp();
        const elapsed_ns: i128 = now - self.last_fps_time;
        if (elapsed_ns >= 1_000_000_000) {
            const fps: f64 = (@as(f64, @floatFromInt(self.frame_count)) * 1_000_000_000.0) /
                @as(f64, @floatFromInt(elapsed_ns));

            const denom: f64 = @as(f64, @floatFromInt(self.frame_count));
            const avg_lock_ms: f64 = (@as(f64, @floatFromInt(self.sum_lock_fill_unlock_ns)) / denom) / 1_000_000.0;
            const avg_render_ms: f64 = (@as(f64, @floatFromInt(self.sum_render_ns)) / denom) / 1_000_000.0;
            const avg_present_ms: f64 = (@as(f64, @floatFromInt(self.sum_present_ns)) / denom) / 1_000_000.0;

            std.debug.print(
                "FPS: {d:.1} | wait+acquire: {d:.3}ms | encode: {d:.3}ms | submit: {d:.3}ms\n",
                .{ fps, avg_lock_ms, avg_render_ms, avg_present_ms },
            );

            self.frame_count = 0;
            self.last_fps_time = now;
            self.sum_lock_fill_unlock_ns = 0;
            self.sum_render_ns = 0;
            self.sum_present_ns = 0;
        }
    }
};
