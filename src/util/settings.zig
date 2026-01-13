const std = @import("std");
const renderer = @import("../renderer/renderer.zig");

pub const Settings = struct {
    backend: renderer.Backend,

    pub fn init() !Settings {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        // Set render mode
        var requested_backend: renderer.Backend = .cpu;
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--gpu")) requested_backend = .gpu;
            if (std.mem.eql(u8, arg, "--cpu")) requested_backend = .cpu;
        }

        return Settings{ .backend = requested_backend };
    }
};
