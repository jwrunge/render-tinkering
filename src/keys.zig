const std = @import("std");
const sdl = @import("sdl.zig").c;

pub const app_name: []const u8 = "render";
pub const keymap_filename: []const u8 = "keymap.cfg";

pub const Action = enum {
    quit,
};

pub const Keymap = struct {
    bindings: std.EnumArray(Action, sdl.SDL_Keycode),

    fn initDefault() Keymap {
        var map = Keymap{
            .bindings = std.EnumArray(Action, sdl.SDL_Keycode).initUndefined(),
        };
        map.bindings.set(.quit, sdl.SDLK_Q);
        return map;
    }

    /// Loads key bindings from `path`. If the file does not exist, returns defaults.
    /// Format:
    ///   quit=113
    /// Blank lines and lines starting with '#' are ignored.
    pub fn initLoadOrDefault(path: []const u8) !Keymap {
        var map = Keymap.initDefault();

        const file = openFilePath(path) catch |err| switch (err) {
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
        try ensureParentDirExists(path);
        const file = try createFilePath(path, .{ .truncate = true });
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

    pub fn get(self: *const Keymap, action: Action) sdl.SDL_Keycode {
        return self.bindings.get(action);
    }

    pub fn remap(self: *Keymap, action: Action, new_key: sdl.SDL_Keycode) void {
        self.bindings.set(action, new_key);
    }

    pub fn remapAndSave(self: *Keymap, action: Action, new_key: sdl.SDL_Keycode, path: []const u8) !void {
        self.remap(action, new_key);
        try self.saveToFile(path);
    }

    pub fn handleEvent(self: *Keymap, e: *sdl.SDL_Event, running: *bool) void {
        if (e.type == sdl.SDL_EVENT_QUIT) {
            running.* = false;
            return;
        }
        if (e.type != sdl.SDL_EVENT_KEY_DOWN) return;

        var matched_action: ?Action = null;
        inline for (std.meta.fields(Action)) |f| {
            const a: Action = @enumFromInt(f.value);
            if (self.get(a) == e.key.key) {
                matched_action = a;
                break;
            }
        }
        const action = matched_action orelse return;

        switch (action) {
            .quit => running.* = false,
        }
    }
};

/// Returns the full path to the keymap file in the OS-standard per-user app data directory.
/// Caller owns the returned memory.
pub fn defaultKeymapPath(allocator: std.mem.Allocator) ![]u8 {
    const dir = try std.fs.getAppDataDir(allocator, app_name);
    defer allocator.free(dir);

    try ensureDirExistsRecursiveAbsolute(dir);
    return try std.fs.path.join(allocator, &[_][]const u8{ dir, keymap_filename });
}

fn openFilePath(path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) return std.fs.openFileAbsolute(path, .{});
    return std.fs.cwd().openFile(path, .{});
}

fn createFilePath(path: []const u8, flags: std.fs.File.CreateFlags) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) return std.fs.createFileAbsolute(path, flags);
    return std.fs.cwd().createFile(path, flags);
}

fn ensureParentDirExists(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (std.fs.path.isAbsolute(parent)) {
        try ensureDirExistsRecursiveAbsolute(parent);
    } else {
        try std.fs.cwd().makePath(parent);
    }
}

fn ensureDirExistsRecursiveAbsolute(dir_path: []const u8) !void {
    std.debug.assert(std.fs.path.isAbsolute(dir_path));
    std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        error.AccessDenied => return err,
        error.FileNotFound => {
            const parent = std.fs.path.dirname(dir_path) orelse return err;
            // Avoid infinite recursion on roots.
            if (std.mem.eql(u8, parent, dir_path)) return err;
            try ensureDirExistsRecursiveAbsolute(parent);
            try std.fs.makeDirAbsolute(dir_path);
        },
        else => return err,
    };
}
