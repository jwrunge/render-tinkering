const std = @import("std");

pub fn getDir(path: []const u8) !std.fs.Dir {
    const parent = std.fs.path.dirname(path) orelse ".";
    if (std.fs.path.isAbsolute(parent)) {
        return try std.fs.openDirAbsolute(parent, .{});
    }
    return try std.fs.cwd().openDir(parent, .{});
}

pub fn readFile(path: []const u8) !std.fs.File {
    const dir = try getDir(path);
    defer dir.close();

    const basename = std.fs.path.basename(path);
    return try dir.openFile(basename, .{});
}

fn createFile(path: []const u8, flags: std.fs.File.CreateFlags) !std.fs.File {
    const dir = try getDir(path);
    defer dir.close();

    const basename = std.fs.path.basename(path);
    return try dir.createFile(basename, flags);
}

pub fn writeFileBytes(path: []const u8, bytes: []const u8, flags: ?std.fs.File.CreateFlags) !void {
    const f = flags orelse std.fs.File.CreateFlags{};
    const file = try createFile(path, f);
    defer file.close();

    var writer_buf: [4096]u8 = undefined;
    var writer = file.writer(&writer_buf);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

pub fn writeFileWith(path: []const u8, flags: ?std.fs.File.CreateFlags, ctx: anytype, comptime writeFn: anytype) !void {
    const file = try createFile(path, flags orelse std.fs.File.CreateFlags{});
    defer file.close();

    var writer_buf: [4096]u8 = undefined;
    var writer = file.writer(&writer_buf);
    try writeFn(ctx, writer);
    try writer.interface.flush();
}
