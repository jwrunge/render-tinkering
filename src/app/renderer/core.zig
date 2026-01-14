const std = @import("std");
const sdl = @import("../sdl.zig").c;
const App = @import("../App.zig").App;
const RenderLogger = @import("logger.zig").RenderLogger;
const build_options = @import("build_options");

pub const Timings = struct {
    lock_fill_unlock_ns: u64,
    render_ns: u64,
    present_ns: u64,
};

pub const Renderer = struct {
    app: *App,
    device: *sdl.SDL_GPUDevice,
    window: *sdl.SDL_Window,
    logger: RenderLogger,

    pub fn init(self: *Renderer, app: *App) !void {
        if (!build_options.enable_sdl_gpu) return error.SDLGPUDisabled;

        const shader_formats: sdl.SDL_GPUShaderFormat =
            sdl.SDL_GPU_SHADERFORMAT_SPIRV |
            sdl.SDL_GPU_SHADERFORMAT_MSL |
            sdl.SDL_GPU_SHADERFORMAT_METALLIB |
            sdl.SDL_GPU_SHADERFORMAT_DXBC |
            sdl.SDL_GPU_SHADERFORMAT_DXIL;

        const device = sdl.SDL_CreateGPUDevice(shader_formats, false, null) orelse {
            std.debug.print("SDL_CreateGPUDevice failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateGPUDeviceFailed;
        };
        errdefer sdl.SDL_DestroyGPUDevice(device);

        if (!sdl.SDL_ClaimWindowForGPUDevice(device, app.window)) {
            std.debug.print("SDL_ClaimWindowForGPUDevice failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLClaimWindowForGPUDeviceFailed;
        }
        errdefer sdl.SDL_ReleaseWindowFromGPUDevice(device, app.window);
        // Swapchain defaults to VSYNC; try to uncap if the platform allows it.
        // (If not supported, we keep the default.)
        const composition = sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR;
        if (sdl.SDL_WindowSupportsGPUPresentMode(device, app.window, sdl.SDL_GPU_PRESENTMODE_IMMEDIATE)) {
            _ = sdl.SDL_SetGPUSwapchainParameters(device, app.window, composition, sdl.SDL_GPU_PRESENTMODE_IMMEDIATE);
        } else if (sdl.SDL_WindowSupportsGPUPresentMode(device, app.window, sdl.SDL_GPU_PRESENTMODE_MAILBOX)) {
            _ = sdl.SDL_SetGPUSwapchainParameters(device, app.window, composition, sdl.SDL_GPU_PRESENTMODE_MAILBOX);
        }

        // Allow more frames in flight to reduce stalling in WaitAndAcquire.
        _ = sdl.SDL_SetGPUAllowedFramesInFlight(device, 3);

        self.* = .{ .app = app, .device = device, .window = app.window, .logger = RenderLogger.init() };

        if (sdl.SDL_GetGPUDeviceDriver(device)) |name_ptr| {
            std.debug.print("GPU device driver: {s}\n", .{std.mem.span(name_ptr)});
        }
    }

    pub fn deinit(self: *Renderer) void {
        sdl.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
        sdl.SDL_DestroyGPUDevice(self.device);
    }

    pub fn render(self: *Renderer, log: bool) !void {
        const t0: i128 = std.time.nanoTimestamp();
        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            std.debug.print("SDL_AcquireGPUCommandBuffer failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLAcquireGPUCommandBufferFailed;
        };

        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        var swap_w: u32 = 0;
        var swap_h: u32 = 0;

        if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, self.window, &swapchain_texture, &swap_w, &swap_h)) {
            std.debug.print("SDL_WaitAndAcquireGPUSwapchainTexture failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLAcquireSwapchainTextureFailed;
        }

        const t1: i128 = std.time.nanoTimestamp();

        // This can happen when the window is minimized; not an error.
        if (swapchain_texture == null) {
            _ = sdl.SDL_SubmitGPUCommandBuffer(command_buffer);
            return;
        }

        var color_target: sdl.SDL_GPUColorTargetInfo = std.mem.zeroes(sdl.SDL_GPUColorTargetInfo);
        color_target.texture = swapchain_texture.?;
        color_target.mip_level = 0;
        color_target.layer_or_depth_plane = 0;
        color_target.clear_color = sdl.SDL_FColor{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
        color_target.load_op = sdl.SDL_GPU_LOADOP_CLEAR;
        color_target.store_op = sdl.SDL_GPU_STOREOP_STORE;
        color_target.resolve_texture = null;
        color_target.resolve_mip_level = 0;
        color_target.resolve_layer = 0;
        color_target.cycle = false;
        color_target.cycle_resolve_texture = false;

        const render_pass = sdl.SDL_BeginGPURenderPass(command_buffer, &color_target, 1, null);
        sdl.SDL_EndGPURenderPass(render_pass);

        const t2: i128 = std.time.nanoTimestamp();

        if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) {
            std.debug.print("SDL_SubmitGPUCommandBuffer failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLSubmitGPUCommandBufferFailed;
        }

        const t3: i128 = std.time.nanoTimestamp();

        if (log) {
            self.logger.update_frame_timings(.{
                .lock_fill_unlock_ns = @intCast(t1 - t0),
                .render_ns = @intCast(t2 - t1),
                .present_ns = @intCast(t3 - t2),
            });
        }
    }
};
