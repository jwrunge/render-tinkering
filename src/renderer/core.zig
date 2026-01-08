const std = @import("std");
const sdl = @import("../util/sdl.zig").c;
const build_options = @import("build_options");

pub const Renderer = struct {
    sdl_renderer: *sdl.SDL_Renderer,
    texture: *sdl.SDL_Texture,
    w: i32,
    h: i32,
    rng_state4: @Vector(4, u32),
    rng_tail: u32,

    pub const Timings = struct {
        lock_fill_unlock_ns: u64,
        render_ns: u64,
        present_ns: u64,
    };

    fn xorshift32(state: *u32) u32 {
        var x = state.*;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        state.* = x;
        return x;
    }

    fn xorshift32x4(state: *@Vector(4, u32)) @Vector(4, u32) {
        var x = state.*;
        x ^= x << @splat(13);
        x ^= x >> @splat(17);
        x ^= x << @splat(5);
        state.* = x;
        return x;
    }

    pub fn init(window: *sdl.SDL_Window, w: i32, h: i32) !Renderer {
        const driver = if (build_options.use_software_renderer) sdl.SDL_SOFTWARE_RENDERER else null;
        const sdl_renderer = sdl.SDL_CreateRenderer(window, driver) orelse {
            std.debug.print("SDL_CreateRenderer failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateRendererFailed;
        };
        errdefer sdl.SDL_DestroyRenderer(sdl_renderer);

        if (sdl.SDL_GetRendererName(sdl_renderer)) |name_ptr| {
            std.debug.print("Renderer: {s}\n", .{std.mem.span(name_ptr)});
        }

        var vsync: c_int = 0;
        if (sdl.SDL_GetRenderVSync(sdl_renderer, &vsync)) {
            std.debug.print("VSync (initial): {d}\n", .{vsync});
        }

        // Try to disable vsync so present doesn't block on refresh.
        if (!sdl.SDL_SetRenderVSync(sdl_renderer, sdl.SDL_RENDERER_VSYNC_DISABLED)) {
            std.debug.print("SDL_SetRenderVSync(DISABLED) failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
        } else if (sdl.SDL_GetRenderVSync(sdl_renderer, &vsync)) {
            std.debug.print("VSync (after set): {d}\n", .{vsync});
        }

        const texture = sdl.SDL_CreateTexture(
            sdl_renderer,
            sdl.SDL_PIXELFORMAT_ARGB8888,
            sdl.SDL_TEXTUREACCESS_STREAMING,
            w,
            h,
        ) orelse {
            std.debug.print("SDL_CreateTexture failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateTextureFailed;
        };
        errdefer sdl.SDL_DestroyTexture(texture);

        // If the window/output is a different size than the texture (common with HiDPI),
        // SDL will scale the texture. Nearest keeps the pixel look (no blur).
        if (!sdl.SDL_SetTextureScaleMode(texture, sdl.SDL_SCALEMODE_NEAREST)) {
            std.debug.print("SDL_SetTextureScaleMode(NEAREST) failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
        }

        const t: i128 = std.time.nanoTimestamp();
        var seed: u32 = @truncate(@as(u128, @bitCast(t)));
        // xorshift has a bad all-zero state.
        if (seed == 0) seed = 0x1234_5678;

        // Seed SIMD lanes by advancing the scalar generator.
        var s = seed;
        var a = xorshift32(&s);
        var b = xorshift32(&s);
        var c = xorshift32(&s);
        var d = xorshift32(&s);
        if (a == 0) a = 0xA341_316C;
        if (b == 0) b = 0xC801_3EA4;
        if (c == 0) c = 0xAD90_777D;
        if (d == 0) d = 0x7E95_761E;

        return .{
            .sdl_renderer = sdl_renderer,
            .texture = texture,
            .w = w,
            .h = h,
            .rng_state4 = .{ a, b, c, d },
            // Keep scalar RNG seed identical to the pre-SIMD version.
            .rng_tail = seed,
        };
    }

    pub fn deinit(self: *Renderer) void {
        sdl.SDL_DestroyTexture(self.texture);
        sdl.SDL_DestroyRenderer(self.sdl_renderer);
    }

    pub fn render(self: *Renderer) !Timings {
        const t0: i128 = std.time.nanoTimestamp();
        var locked_pixels: ?*anyopaque = null;
        var pitch: c_int = 0;
        if (!sdl.SDL_LockTexture(self.texture, null, &locked_pixels, &pitch)) {
            std.debug.print("SDL_LockTexture failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLLockTextureFailed;
        }

        const base: [*]u8 = @ptrCast(locked_pixels.?);
        const pitch_usize: usize = @intCast(pitch);
        const w_usize: usize = @intCast(self.w);
        const h_usize: usize = @intCast(self.h);

        var rng4 = self.rng_state4;
        var rng_tail = self.rng_tail;
        const alpha4: @Vector(4, u32) = @splat(0xFF00_0000);
        const rgb_mask4: @Vector(4, u32) = @splat(0x00FF_FFFF);

        // Fill full texture. Format is ARGB8888, alpha always 0xFF.
        var y: usize = 0;
        while (y < h_usize) : (y += 1) {
            const row_ptr: [*]u8 = base + y * pitch_usize;
            const row_u32: [*]u32 = @ptrCast(@alignCast(row_ptr));

            var x: usize = 0;

            if (build_options.use_simd_fill) {
                while (x + 4 <= w_usize) : (x += 4) {
                    const r4 = xorshift32x4(&rng4);
                    const p4: @Vector(4, u32) = alpha4 | (r4 & rgb_mask4);
                    const dst: *align(1) @Vector(4, u32) = @ptrCast(row_u32 + x);
                    dst.* = p4;
                }
            }

            while (x < w_usize) : (x += 1) {
                const r = xorshift32(&rng_tail);
                row_u32[x] = 0xFF000000 | (r & 0x00FFFFFF);
            }
        }

        self.rng_state4 = rng4;
        self.rng_tail = rng_tail;

        // Include unlock cost in lock+fill timing (some backends upload on unlock).
        sdl.SDL_UnlockTexture(self.texture);

        const t1: i128 = std.time.nanoTimestamp();

        // if (!sdl.SDL_RenderClear(self.sdl_renderer)) {
        //     std.debug.print("SDL_RenderClear failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
        //     return error.SDLRenderFailed;
        // }

        if (!sdl.SDL_RenderTexture(self.sdl_renderer, self.texture, null, null)) {
            std.debug.print("SDL_RenderTexture failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLRenderFailed;
        }

        const t2: i128 = std.time.nanoTimestamp();

        if (!sdl.SDL_RenderPresent(self.sdl_renderer)) {
            std.debug.print("SDL_RenderPresent failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLRenderFailed;
        }

        const t3: i128 = std.time.nanoTimestamp();

        return .{
            .lock_fill_unlock_ns = @intCast(t1 - t0),
            .render_ns = @intCast(t2 - t1),
            .present_ns = @intCast(t3 - t2),
        };
    }
};
