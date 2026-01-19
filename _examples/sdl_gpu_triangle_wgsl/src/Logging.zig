const std = @import("std");
const c = @import("SDL.zig").c;

pub fn sdlError() []const u8 {
    return std.mem.span(c.SDL_GetError());
}
