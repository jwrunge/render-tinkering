const std = @import("std");
const Object = @import("object.zig").Object;

pub const Chunk = struct {
    lod: u4,
    x: u4,
    y: u4,
    z: u4,
    objects: *[]Object,

    pub fn init(allocator: std.mem.Allocator, x: u4, y: u4, z: u4) *Chunk {
        var c = Chunk{
            .lod = 0,
            .x = x,
            .y = y,
            .z = z,
            .objects = std.ArrayList(Object).init(allocator),
        };

        c.setLod(x, y, z);
        return c;
    }

    fn setLod(self: *Chunk, x: u4, y: u4, z: u4) void {
        const new_lod = if (x > y)
            if (x > z) x else z
        else if (y > z) y else z;

        self.lod = new_lod;
    }

    pub fn deinit(self: *Chunk) void {
        self.objects.deinit();
    }

    fn summarize(self: *Chunk) void {
        std.debug.print("Chunk LOD: {d}, Position: ({d}, {d}, {d}), Object count: {d}\n", .{ self.lod, self.x, self.y, self.z, self.objects.len });
    }
};
