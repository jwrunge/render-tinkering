const std = @import("std");

pub fn getDir(path: []const u8) !std.fs.Dir {
    const parent = std.fs.path.dirname(path) orelse ".";
    if (std.fs.path.isAbsolute(parent)) {
        return try std.fs.openDirAbsolute(parent, .{});
    }
    return try std.fs.cwd().openDir(parent, .{});
}

/// Opens the file at `path` for reading.
pub fn open(path: []const u8) !std.fs.File {
    var dir = try getDir(path);
    defer dir.close();

    const basename = std.fs.path.basename(path);
    return try dir.openFile(basename, .{});
}

/// Reads the entire file into an owned buffer allocated from `allocator`.
pub fn readBytes(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try open(path);
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    errdefer allocator.free(buffer);

    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(&reader_buf);
    const read_n = try reader.interface.readAll(buffer);
    if (read_n != buffer.len) return error.UnexpectedEndOfStream;
    return buffer;
}

pub fn readLines(
    comptime Ctx: type,
    path: []const u8,
    ctx: *Ctx,
    comptime handleLineFn: fn (*Ctx, []const u8, []const u8) anyerror!bool,
) !void {
    var file = open(path) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(&reader_buf);

    while (true) {
        const raw_line = reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        const eq_index = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const name = std.mem.trim(u8, line[0..eq_index], " \t");
        const value_str = std.mem.trim(u8, line[eq_index + 1 ..], " \t");

        if (name.len == 0 or value_str.len == 0) continue;
        if (try handleLineFn(ctx, name, value_str)) break;
    }
}

fn create(path: []const u8, flags: std.fs.File.CreateFlags) !std.fs.File {
    var dir = try getDir(path);
    defer dir.close();

    const basename = std.fs.path.basename(path);
    return try dir.createFile(basename, flags);
}

pub fn writeBytes(path: []const u8, bytes: []const u8, flags: ?std.fs.File.CreateFlags) !void {
    const f = flags orelse std.fs.File.CreateFlags{};
    var file = try create(path, f);
    defer file.close();

    var writer_buf: [4096]u8 = undefined;
    var writer = file.writer(&writer_buf);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

pub fn writeWith(path: []const u8, flags: ?std.fs.File.CreateFlags, ctx: anytype, comptime writeFn: anytype) !void {
    var file = try create(path, flags orelse std.fs.File.CreateFlags{});
    defer file.close();

    var writer_buf: [4096]u8 = undefined;
    var writer = file.writer(&writer_buf);
    // Pass a mutable pointer: Writer methods update internal state.
    try writeFn(ctx, &writer.interface);
    try writer.interface.flush();
}
