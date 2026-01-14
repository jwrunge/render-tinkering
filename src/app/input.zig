const std = @import("std");
const sdl = @import("sdl.zig").c;
const io = @import("file-io.zig");

pub const app_name: []const u8 = "render";
pub const input_map_filename: []const u8 = "keymap.cfg";

pub const Action = enum {
    quit,
};

fn defaultKeyFor(action: Action) sdl.SDL_Keycode {
    return switch (action) {
        .quit => sdl.SDLK_ESCAPE,
    };
}

pub const InputMap = struct {
    bindings: std.EnumArray(Action, sdl.SDL_Keycode),

    fn handleReadConfigLine(ctx: *InputMap, name: []const u8, value_str: []const u8) !bool {
        const action = std.meta.stringToEnum(Action, name) orelse return false;
        const parsed_keycode = std.fmt.parseInt(u32, value_str, 10) catch return false;
        ctx.tempRemap(action, @as(sdl.SDL_Keycode, parsed_keycode));
        return false;
    }

    fn handleWriteConfig(ctx: *const InputMap, writer: *std.Io.Writer) !void {
        try writer.writeAll("# Keymap configuration file\n");
        try writer.writeAll("# Lines starting with '#' are comments\n");
        try writer.writeAll("# Format: action=SDL_Keycode (decimal)\n");
        inline for (std.meta.fields(Action)) |f| {
            const action: Action = @enumFromInt(f.value);
            const keycode: u32 = @intCast(ctx.getInput(action));
            try writer.print("{s}={d}\n", .{ @tagName(action), keycode });
        }
    }

    fn resetToDefaults(self: *InputMap) void {
        inline for (std.meta.fields(Action)) |f| {
            const action: Action = @enumFromInt(f.value);
            self.bindings.set(action, defaultKeyFor(action));
        }
    }

    pub fn init() !InputMap {
        var map = InputMap{
            .bindings = std.EnumArray(Action, sdl.SDL_Keycode).initUndefined(),
        };

        // Set default bindings
        map.resetToDefaults();

        // Map bindings from file if it exists
        try io.readLines(InputMap, input_map_filename, &map, handleReadConfigLine);

        return map;
    }

    /// Saves current bindings to `path`, overwriting the file.
    pub fn saveToFile(self: *const InputMap) !void {
        try io.writeWith(input_map_filename, .{ .truncate = true }, self, handleWriteConfig);
    }

    /// Get key for action
    pub fn getInput(self: *const InputMap, action: Action) sdl.SDL_Keycode {
        return self.bindings.get(action);
    }

    /// Get action for key
    pub fn getAction(self: *const InputMap, key: sdl.SDL_Keycode) ?Action {
        inline for (std.meta.fields(Action)) |f| {
            const a: Action = @enumFromInt(f.value);
            if (self.getInput(a) == key) {
                return a;
            }
        }
        return null;
    }

    /// Set key for action (do not persist)
    pub fn tempRemap(self: *InputMap, action: Action, new_key: sdl.SDL_Keycode) void {
        self.bindings.set(action, new_key);
    }

    /// Remap action to new_key (persists settings)
    pub fn remap(self: *InputMap, action: Action, new_key: sdl.SDL_Keycode) !void {
        self.tempRemap(action, new_key);
        try self.saveToFile();
    }

    /// Handle SDL event, updating `running` if quit action is triggered
    pub fn handleEvent(self: *InputMap, e: *sdl.SDL_Event, running: *bool) void {
        if (e.type == sdl.SDL_EVENT_QUIT) {
            running.* = false;
            return;
        }
        if (e.type != sdl.SDL_EVENT_KEY_DOWN) return;

        var matched_action: ?Action = null;
        inline for (std.meta.fields(Action)) |f| {
            const a: Action = @enumFromInt(f.value);
            if (self.getInput(a) == e.key.key) {
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
