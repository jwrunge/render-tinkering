const std = @import("std");
const sdl = @import("../util/sdl.zig").c;
const build_options = @import("build_options");
const cpu = @import("core.zig");

pub const GpuRenderer = struct {
    device: *sdl.SDL_GPUDevice,
    window: *sdl.SDL_Window,
    shader_code: ?[]u8,
    vertex_shader: ?*sdl.SDL_GPUShader,
    fragment_shader: ?*sdl.SDL_GPUShader,
    pipeline: ?*sdl.SDL_GPUGraphicsPipeline,
    pipeline_format: sdl.SDL_GPUTextureFormat,

    pub const Timings = cpu.CpuRenderer.Timings;

    pub fn init(self: *GpuRenderer, window: *sdl.SDL_Window) !void {
        if (!build_options.enable_sdl_gpu) return error.SDLGPUDisabled;

        // Tell SDL we can (eventually) provide shaders for any backend.
        // Even though this minimal backend just clears the swapchain, this
        // helps SDL pick the best driver on each platform.
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

        if (!sdl.SDL_ClaimWindowForGPUDevice(device, window)) {
            std.debug.print("SDL_ClaimWindowForGPUDevice failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLClaimWindowForGPUDeviceFailed;
        }
        errdefer sdl.SDL_ReleaseWindowFromGPUDevice(device, window);

        // Swapchain defaults to VSYNC; try to uncap if the platform allows it.
        // (If not supported, we keep the default.)
        const composition = sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR;
        if (sdl.SDL_WindowSupportsGPUPresentMode(device, window, sdl.SDL_GPU_PRESENTMODE_IMMEDIATE)) {
            _ = sdl.SDL_SetGPUSwapchainParameters(device, window, composition, sdl.SDL_GPU_PRESENTMODE_IMMEDIATE);
        } else if (sdl.SDL_WindowSupportsGPUPresentMode(device, window, sdl.SDL_GPU_PRESENTMODE_MAILBOX)) {
            _ = sdl.SDL_SetGPUSwapchainParameters(device, window, composition, sdl.SDL_GPU_PRESENTMODE_MAILBOX);
        }

        // Allow more frames in flight to reduce stalling in WaitAndAcquire.
        _ = sdl.SDL_SetGPUAllowedFramesInFlight(device, 3);

        self.* = .{ .device = device, .window = window };

        // Optional: load a shader library and set up a simple fullscreen pipeline.
        // If this fails (missing metallib, no toolchain, etc) we still keep a
        // working GPU backend (clear-only).
        self.shader_code = null;
        self.vertex_shader = null;
        self.fragment_shader = null;
        self.pipeline = null;
        self.pipeline_format = sdl.SDL_GPU_TEXTUREFORMAT_INVALID;

        if (sdl.SDL_GetGPUDeviceDriver(device)) |name_ptr| {
            const driver_name = std.mem.span(name_ptr);
            // On macOS this will typically be "metal".
            if (std.mem.eql(u8, driver_name, "metal")) {
                if (loadShaderLibrary(std.heap.page_allocator)) |bytes| {
                    self.shader_code = bytes;
                    self.pipeline_format = sdl.SDL_GetGPUSwapchainTextureFormat(device, window);
                    self.createFullscreenPipeline() catch |err| {
                        std.debug.print("GPU pipeline init failed ({any}); falling back to clear-only\n", .{err});
                        self.destroyPipeline();
                        std.heap.page_allocator.free(bytes);
                        self.shader_code = null;
                    };
                } else |err| {
                    std.debug.print("No GPU shader library found ({any}); using clear-only\n", .{err});
                }
            }
        }

        if (sdl.SDL_GetGPUDeviceDriver(device)) |name_ptr| {
            std.debug.print("GPU device driver: {s}\n", .{std.mem.span(name_ptr)});
        }
    }

    pub fn deinit(self: *GpuRenderer) void {
        self.destroyPipeline();
        if (self.shader_code) |bytes| {
            std.heap.page_allocator.free(bytes);
            self.shader_code = null;
        }
        sdl.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
        sdl.SDL_DestroyGPUDevice(self.device);
    }

    fn loadShaderLibrary(allocator: std.mem.Allocator) ![]u8 {
        const exe_path = try std.fs.selfExePathAlloc(allocator);
        defer allocator.free(exe_path);

        const exe_dir = std.fs.path.dirname(exe_path) orelse return error.NoExeDir;
        const lib_path = try std.fs.path.join(allocator, &.{ exe_dir, "shaders", "pixel.metallib" });
        defer allocator.free(lib_path);

        var f = try std.fs.openFileAbsolute(lib_path, .{});
        defer f.close();
        return try f.readToEndAlloc(allocator, 16 * 1024 * 1024);
    }

    fn destroyPipeline(self: *GpuRenderer) void {
        if (self.pipeline) |p| {
            sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, p);
            self.pipeline = null;
        }
        if (self.vertex_shader) |sh| {
            sdl.SDL_ReleaseGPUShader(self.device, sh);
            self.vertex_shader = null;
        }
        if (self.fragment_shader) |sh| {
            sdl.SDL_ReleaseGPUShader(self.device, sh);
            self.fragment_shader = null;
        }
    }

    fn createFullscreenPipeline(self: *GpuRenderer) !void {
        const code = self.shader_code orelse return error.NoShaderCode;
        if (self.pipeline_format == sdl.SDL_GPU_TEXTUREFORMAT_INVALID) return error.InvalidSwapchainFormat;

        // Create shaders from the metallib blob.
        const vs_info: sdl.SDL_GPUShaderCreateInfo = .{
            .code_size = code.len,
            .code = code.ptr,
            .entrypoint = "fullscreen_vs",
            .format = sdl.SDL_GPU_SHADERFORMAT_METALLIB,
            .stage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 0,
            .props = 0,
        };
        const fs_info: sdl.SDL_GPUShaderCreateInfo = .{
            .code_size = code.len,
            .code = code.ptr,
            .entrypoint = "fullscreen_fs",
            .format = sdl.SDL_GPU_SHADERFORMAT_METALLIB,
            .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 0,
            .props = 0,
        };

        const vs = sdl.SDL_CreateGPUShader(self.device, &vs_info) orelse {
            std.debug.print("SDL_CreateGPUShader(vs) failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateGPUShaderFailed;
        };
        errdefer sdl.SDL_ReleaseGPUShader(self.device, vs);

        const fs = sdl.SDL_CreateGPUShader(self.device, &fs_info) orelse {
            std.debug.print("SDL_CreateGPUShader(fs) failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateGPUShaderFailed;
        };
        errdefer sdl.SDL_ReleaseGPUShader(self.device, fs);

        var blend: sdl.SDL_GPUColorTargetBlendState = std.mem.zeroes(sdl.SDL_GPUColorTargetBlendState);
        blend.enable_blend = false;
        blend.enable_color_write_mask = false;
        blend.color_write_mask = 0;

        const color_desc = sdl.SDL_GPUColorTargetDescription{
            .format = self.pipeline_format,
            .blend_state = blend,
        };

        var pipeline_info: sdl.SDL_GPUGraphicsPipelineCreateInfo = std.mem.zeroes(sdl.SDL_GPUGraphicsPipelineCreateInfo);
        pipeline_info.vertex_shader = vs;
        pipeline_info.fragment_shader = fs;
        pipeline_info.vertex_input_state = .{
            .vertex_buffer_descriptions = null,
            .num_vertex_buffers = 0,
            .vertex_attributes = null,
            .num_vertex_attributes = 0,
        };
        pipeline_info.primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
        pipeline_info.rasterizer_state = .{
            .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            .cull_mode = sdl.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .enable_depth_bias = false,
            .enable_depth_clip = true,
            .padding1 = 0,
            .padding2 = 0,
        };
        pipeline_info.multisample_state = .{
            .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
            .sample_mask = 0,
            .enable_mask = false,
            .enable_alpha_to_coverage = false,
            .padding2 = 0,
            .padding3 = 0,
        };
        pipeline_info.depth_stencil_state = .{
            .compare_op = sdl.SDL_GPU_COMPAREOP_ALWAYS,
            .back_stencil_state = std.mem.zeroes(sdl.SDL_GPUStencilOpState),
            .front_stencil_state = std.mem.zeroes(sdl.SDL_GPUStencilOpState),
            .compare_mask = 0,
            .write_mask = 0,
            .enable_depth_test = false,
            .enable_depth_write = false,
            .enable_stencil_test = false,
            .padding1 = 0,
            .padding2 = 0,
            .padding3 = 0,
        };
        pipeline_info.target_info = .{
            .color_target_descriptions = &color_desc,
            .num_color_targets = 1,
            .depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_INVALID,
            .has_depth_stencil_target = false,
            .padding1 = 0,
            .padding2 = 0,
            .padding3 = 0,
        };
        pipeline_info.props = 0;

        const pipeline = sdl.SDL_CreateGPUGraphicsPipeline(self.device, &pipeline_info) orelse {
            std.debug.print("SDL_CreateGPUGraphicsPipeline failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateGPUGraphicsPipelineFailed;
        };

        self.vertex_shader = vs;
        self.fragment_shader = fs;
        self.pipeline = pipeline;
    }

    pub fn render(self: *GpuRenderer) !Timings {
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
            return .{ .lock_fill_unlock_ns = 0, .render_ns = 0, .present_ns = 0 };
        }

        var color_target: sdl.SDL_GPUColorTargetInfo = std.mem.zeroes(sdl.SDL_GPUColorTargetInfo);
        color_target.texture = swapchain_texture.?;
        color_target.mip_level = 0;
        color_target.layer_or_depth_plane = 0;
        // If we have a pipeline that touches every pixel, we can skip the clear.
        // Otherwise clear to white as a fallback.
        color_target.clear_color = sdl.SDL_FColor{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
        color_target.load_op = if (self.pipeline != null) sdl.SDL_GPU_LOADOP_DONT_CARE else sdl.SDL_GPU_LOADOP_CLEAR;
        color_target.store_op = sdl.SDL_GPU_STOREOP_STORE;
        color_target.resolve_texture = null;
        color_target.resolve_mip_level = 0;
        color_target.resolve_layer = 0;
        color_target.cycle = false;
        color_target.cycle_resolve_texture = false;

        const render_pass = sdl.SDL_BeginGPURenderPass(command_buffer, &color_target, 1, null);

        if (self.pipeline) |p| {
            sdl.SDL_BindGPUGraphicsPipeline(render_pass, p);
            // 3 vertices = fullscreen triangle. Keep first_vertex/instance at 0.
            sdl.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);
        }
        sdl.SDL_EndGPURenderPass(render_pass);

        const t2: i128 = std.time.nanoTimestamp();

        if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) {
            std.debug.print("SDL_SubmitGPUCommandBuffer failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLSubmitGPUCommandBufferFailed;
        }

        const t3: i128 = std.time.nanoTimestamp();

        return .{
            // For the GPU backend these timings mean:
            // - lock_fill_unlock_ns: swapchain wait+acquire time
            // - render_ns: command encoding time
            // - present_ns: submit time (presentation happens asynchronously)
            .lock_fill_unlock_ns = @intCast(t1 - t0),
            .render_ns = @intCast(t2 - t1),
            .present_ns = @intCast(t3 - t2),
        };
    }
};
