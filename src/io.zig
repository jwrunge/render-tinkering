const std = @import("std");

pub fn u8readFile(path: []const u8, fromDir: ?[]const u8) ![]const u8 {
    if (fromDir) |dir_path| {
        var dir = if (std.fs.path.isAbsolute(dir_path))
            try std.fs.openDirAbsolute(dir_path, .{})
        else
            try std.fs.cwd().openDir(dir_path, .{});
        defer dir.close();
    } else {
        const file = try std.fs.cwd().openFile(path, .{});
        _ = file; // autofix
    }
    var dir =
        if (fromDir == null)
            try std.fs.cwd()
        else if (std.fs.path.isAbsolute(fromDir))
            try std.fs.openDirAbsolute(fromDir, .{})
        else
            try std.fs.cwd().openDir(fromDir, .{});

    defer dir.close();

    const file = dir.openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return map,
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

        const action = std.meta.stringToEnum(Action, name) orelse continue;
        const parsed_keycode = std.fmt.parseInt(u32, value_str, 10) catch continue;
        map.remap(action, @as(sdl.SDL_Keycode, parsed_keycode));
    }

    return map;
}

/// Saves current bindings to `path`, overwriting the file.
pub fn saveToFile(self: *const Keymap, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var writer_buf: [4096]u8 = undefined;
    var writer = file.writer(&writer_buf);

    try writer.interface.writeAll("# action=SDL_Keycode (decimal)\n");
    inline for (std.meta.fields(Action)) |f| {
        const action: Action = @enumFromInt(f.value);
        const keycode: u32 = @intCast(self.get(action));
        try writer.interface.print("{s}={d}\n", .{ @tagName(action), keycode });
    }

    try writer.interface.flush();
}
