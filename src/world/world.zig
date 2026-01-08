const Chunk = @import("chunk.zig").Chunk;
const std = @import("std");

pub const World = struct {
    chunks: [16 * 16 * 16]Chunk,

    pub fn init() !World {
        var world = World{
            .chunks = undefined,
        };

        // Initialize only the chunks we need
        for (0..world.active_count) |i| {
            world.chunks[i] = Chunk.init(0, 0, 0);
        }
        return world;
    }
};
