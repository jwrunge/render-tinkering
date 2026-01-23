const std = @import("std");
const sdl = @import("../sdl.zig").sdl;
const App = @import("../app/App.zig").App;
const RenderLogger = @import("logger.zig").RenderLogger;
const ShaderProgram = @import("ShaderProgram.zig").ShaderProgram;
const VertexLayout = @import("VertexLayout.zig").VertexLayout;

const Vertex = extern struct {
    pos: [2]f32,
};

fn pickShaderFormat(formats: sdl.SDL_GPUShaderFormat) sdl.SDL_GPUShaderFormat {
    // Prefer MSL on macOS (Metal driver). Fall back to SPIR-V when available.
    if ((formats & sdl.SDL_GPU_SHADERFORMAT_MSL) != 0) return sdl.SDL_GPU_SHADERFORMAT_MSL;
    if ((formats & sdl.SDL_GPU_SHADERFORMAT_SPIRV) != 0) return sdl.SDL_GPU_SHADERFORMAT_SPIRV;
    return sdl.SDL_GPU_SHADERFORMAT_INVALID;
}

pub const Renderer = struct {
    app: *App,
    device: *sdl.SDL_GPUDevice,
    window: *sdl.SDL_Window,
    logger: RenderLogger,

    shader_program: ShaderProgram,
    pipeline: *sdl.SDL_GPUGraphicsPipeline,
    vertex_buffer: *sdl.SDL_GPUBuffer,

    fn createGraphicsPipeline(
        device: *sdl.SDL_GPUDevice,
        window: *sdl.SDL_Window,
        shader_program: *const ShaderProgram,
        vertex_input_state: sdl.SDL_GPUVertexInputState,
    ) !*sdl.SDL_GPUGraphicsPipeline {
        const swap_format = sdl.SDL_GetGPUSwapchainTextureFormat(device, window);

        var blend_state: sdl.SDL_GPUColorTargetBlendState = std.mem.zeroes(sdl.SDL_GPUColorTargetBlendState);
        blend_state.enable_blend = false;
        blend_state.enable_color_write_mask = false; // when false, SDL writes all RGBA channels

        const color_targets = [_]sdl.SDL_GPUColorTargetDescription{.{
            .format = swap_format,
            .blend_state = blend_state,
        }};

        const target_info: sdl.SDL_GPUGraphicsPipelineTargetInfo = .{
            .color_target_descriptions = &color_targets,
            .num_color_targets = 1,
            .depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_INVALID,
            .has_depth_stencil_target = false,
            .padding1 = 0,
            .padding2 = 0,
            .padding3 = 0,
        };

        var raster: sdl.SDL_GPURasterizerState = std.mem.zeroes(sdl.SDL_GPURasterizerState);
        raster.fill_mode = sdl.SDL_GPU_FILLMODE_FILL;
        raster.cull_mode = sdl.SDL_GPU_CULLMODE_NONE;
        raster.front_face = sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE;
        raster.enable_depth_bias = false;
        raster.enable_depth_clip = true;

        var msaa: sdl.SDL_GPUMultisampleState = std.mem.zeroes(sdl.SDL_GPUMultisampleState);
        msaa.sample_count = sdl.SDL_GPU_SAMPLECOUNT_1;
        msaa.sample_mask = 0;
        msaa.enable_mask = false;
        msaa.enable_alpha_to_coverage = false;

        var ds: sdl.SDL_GPUDepthStencilState = std.mem.zeroes(sdl.SDL_GPUDepthStencilState);
        ds.enable_depth_test = false;
        ds.enable_depth_write = false;
        ds.enable_stencil_test = false;

        const pipeline_info: sdl.SDL_GPUGraphicsPipelineCreateInfo = .{
            .vertex_shader = shader_program.vs,
            .fragment_shader = shader_program.fs,
            .vertex_input_state = vertex_input_state,
            .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = raster,
            .multisample_state = msaa,
            .depth_stencil_state = ds,
            .target_info = target_info,
            .props = 0,
        };

        const pipeline = sdl.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse {
            std.debug.print("SDL_CreateGPUGraphicsPipeline failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateGPUGraphicsPipelineFailed;
        };

        return pipeline;
    }

    fn createTriangleVertexBuffer(device: *sdl.SDL_GPUDevice) !*sdl.SDL_GPUBuffer {
        // These positions are in clip space (NDC). Without an aspect correction in the shader,
        // the triangle will appear stretched when the window aspect ratio changes.
        const vertices = [_]Vertex{
            .{ .pos = .{ -0.75, -0.60 } },
            .{ .pos = .{ 0.75, -0.60 } },
            .{ .pos = .{ 0.0, 0.80 } },
        };

        const vb_info: sdl.SDL_GPUBufferCreateInfo = .{
            .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
            .size = @sizeOf(@TypeOf(vertices)),
            .props = 0,
        };

        const vertex_buffer = sdl.SDL_CreateGPUBuffer(device, &vb_info) orelse {
            std.debug.print("SDL_CreateGPUBuffer failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateGPUBufferFailed;
        };
        errdefer sdl.SDL_ReleaseGPUBuffer(device, vertex_buffer);

        const tb_info: sdl.SDL_GPUTransferBufferCreateInfo = .{
            .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = vb_info.size,
            .props = 0,
        };

        const transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(device, &tb_info) orelse {
            std.debug.print("SDL_CreateGPUTransferBuffer failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateGPUTransferBufferFailed;
        };
        defer sdl.SDL_ReleaseGPUTransferBuffer(device, transfer_buffer);

        const mapped = sdl.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse {
            std.debug.print("SDL_MapGPUTransferBuffer failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLMapGPUTransferBufferFailed;
        };
        @memcpy(@as([*]u8, @ptrCast(mapped))[0..vb_info.size], std.mem.asBytes(&vertices));
        sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);

        // Upload once using a transient command buffer.
        // (We record a copy pass that moves bytes from an upload buffer into a GPU-only buffer.)
        {
            const cmd = sdl.SDL_AcquireGPUCommandBuffer(device) orelse {
                std.debug.print("SDL_AcquireGPUCommandBuffer failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
                return error.SDLAcquireGPUCommandBufferFailed;
            };

            const copy_pass = sdl.SDL_BeginGPUCopyPass(cmd);

            const src: sdl.SDL_GPUTransferBufferLocation = .{ .transfer_buffer = transfer_buffer, .offset = 0 };
            const dst: sdl.SDL_GPUBufferRegion = .{ .buffer = vertex_buffer, .offset = 0, .size = vb_info.size };

            sdl.SDL_UploadToGPUBuffer(copy_pass, &src, &dst, false);
            sdl.SDL_EndGPUCopyPass(copy_pass);

            if (!sdl.SDL_SubmitGPUCommandBuffer(cmd)) {
                std.debug.print("SDL_SubmitGPUCommandBuffer (upload) failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
                return error.SDLSubmitGPUCommandBufferFailed;
            }
        }

        return vertex_buffer;
    }

    pub fn init(self: *Renderer, app: *App) !void {
        // === 1) Create a GPU device and attach it to the window ===
        // We ask SDL for a device that can consume either SPIR-V or Metal shader binaries.
        const requested_formats: sdl.SDL_GPUShaderFormat =
            sdl.SDL_GPU_SHADERFORMAT_SPIRV |
            sdl.SDL_GPU_SHADERFORMAT_MSL;

        const device = sdl.SDL_CreateGPUDevice(requested_formats, false, null) orelse {
            std.debug.print("SDL_CreateGPUDevice failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLCreateGPUDeviceFailed;
        };
        // `errdefer` means: if we return an error later in init(), run this cleanup.
        errdefer sdl.SDL_DestroyGPUDevice(device);

        if (!sdl.SDL_ClaimWindowForGPUDevice(device, app.window)) {
            std.debug.print("SDL_ClaimWindowForGPUDevice failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLClaimWindowForGPUDeviceFailed;
        }
        errdefer sdl.SDL_ReleaseWindowFromGPUDevice(device, app.window);

        // === 2) Configure swapchain / presentation behavior ===
        // Swapchain = the series of images we render into and present to the window.

        // Swapchain defaults to VSYNC; try to uncap if the platform allows it.
        const composition = sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR;
        if (sdl.SDL_WindowSupportsGPUPresentMode(device, app.window, sdl.SDL_GPU_PRESENTMODE_IMMEDIATE)) {
            _ = sdl.SDL_SetGPUSwapchainParameters(device, app.window, composition, sdl.SDL_GPU_PRESENTMODE_IMMEDIATE);
        } else if (sdl.SDL_WindowSupportsGPUPresentMode(device, app.window, sdl.SDL_GPU_PRESENTMODE_MAILBOX)) {
            _ = sdl.SDL_SetGPUSwapchainParameters(device, app.window, composition, sdl.SDL_GPU_PRESENTMODE_MAILBOX);
        }

        // === 3) Tune how far the CPU can get ahead of the GPU ===
        // More frames-in-flight can reduce stalls but increases latency and resource pressure.
        // 2–3 is a common default; this is not “20 frames ahead”, it’s a max queue depth.
        _ = sdl.SDL_SetGPUAllowedFramesInFlight(device, 3);

        // === 4) Pick a shader binary format compatible with the device ===

        const actual_formats = sdl.SDL_GetGPUShaderFormats(device);
        const shader_format = pickShaderFormat(actual_formats);
        if (shader_format == sdl.SDL_GPU_SHADERFORMAT_INVALID) {
            std.debug.print("No supported shader format. Device supports mask=0x{x}\n", .{actual_formats});
            return error.NoSupportedShaderFormat;
        }

        // === 5) Load shaders (vertex + fragment) ===
        // `ShaderProgram` reads the precompiled shader artifacts produced by the build.
        const allocator = std.heap.page_allocator;
        const shader_program = try ShaderProgram.init(allocator, device, shader_format, "triangle");
        errdefer shader_program.deinit();

        // === 6) Describe how vertex buffer bytes map to shader inputs ===
        // This must match what the vertex shader expects.
        // Here: one buffer slot (0), one attribute at @location(0) = vec2f position.
        const vb_desc = [_]sdl.SDL_GPUVertexBufferDescription{.{
            .slot = 0,
            .pitch = @sizeOf(Vertex),
            .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        }};

        const vb_attr = [_]sdl.SDL_GPUVertexAttribute{.{
            .location = 0,
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            .offset = 0,
        }};

        const layout = VertexLayout{ .vb_desc = vb_desc[0..], .vb_attr = vb_attr[0..] };
        const vertex_input_state: sdl.SDL_GPUVertexInputState = layout.vertexInputState();

        // === 7) Create a graphics pipeline ===
        // A pipeline is a “bundle” of shaders + fixed-function state (blend/raster/msaa/depth)
        // compiled together for a specific render target format.
        const pipeline = try createGraphicsPipeline(device, app.window, &shader_program, vertex_input_state);
        errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);

        // === 8) Create GPU buffers and upload geometry ===
        const vertex_buffer = try createTriangleVertexBuffer(device);
        errdefer sdl.SDL_ReleaseGPUBuffer(device, vertex_buffer);

        // === 9) Publish fully-initialized renderer state ===
        self.* = .{
            .app = app,
            .device = device,
            .window = app.window,
            .logger = RenderLogger.init(),
            .shader_program = shader_program,
            .pipeline = pipeline,
            .vertex_buffer = vertex_buffer,
        };

        if (sdl.SDL_GetGPUDeviceDriver(device)) |name_ptr| {
            std.debug.print("GPU device driver: {s}\n", .{std.mem.span(name_ptr)});
        }
    }

    pub fn deinit(self: *Renderer) void {
        sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.pipeline);
        sdl.SDL_ReleaseGPUBuffer(self.device, self.vertex_buffer);
        self.shader_program.deinit();
        sdl.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
        sdl.SDL_DestroyGPUDevice(self.device);
    }

    pub fn render(self: *Renderer, log: bool) !void {
        // Frame timings: mostly used to understand where time is going.
        const t0: i128 = std.time.nanoTimestamp();

        // === 1) Get a command buffer for this frame ===
        // Command buffers record GPU work; submitting them tells the GPU to execute it.
        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            std.debug.print("SDL_AcquireGPUCommandBuffer failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLAcquireGPUCommandBufferFailed;
        };

        // === 2) Acquire the current swapchain texture (the frame we will render into) ===
        // SDL also returns the pixel size; we use it to set the viewport correctly on resize.
        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        var swap_w: u32 = 0;
        var swap_h: u32 = 0;

        if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, self.window, &swapchain_texture, &swap_w, &swap_h)) {
            std.debug.print("SDL_WaitAndAcquireGPUSwapchainTexture failed: {s}\n", .{std.mem.span(sdl.SDL_GetError())});
            return error.SDLAcquireSwapchainTextureFailed;
        }

        const t1: i128 = std.time.nanoTimestamp();

        // This can happen when the window is minimized; not an error.
        // There's nothing to render to, but we should still submit the command buffer.
        if (swapchain_texture == null) {
            _ = sdl.SDL_SubmitGPUCommandBuffer(command_buffer);
            return;
        }

        // === 3) Begin a render pass targeting the swapchain texture ===
        // The render pass defines attachments + clear/load/store operations.
        var color_target: sdl.SDL_GPUColorTargetInfo = std.mem.zeroes(sdl.SDL_GPUColorTargetInfo);
        color_target.texture = swapchain_texture.?;
        color_target.mip_level = 0;
        color_target.layer_or_depth_plane = 0;
        color_target.clear_color = sdl.SDL_FColor{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
        color_target.load_op = sdl.SDL_GPU_LOADOP_CLEAR;
        color_target.store_op = sdl.SDL_GPU_STOREOP_STORE;

        color_target.resolve_texture = null;
        color_target.resolve_mip_level = 0;
        color_target.resolve_layer = 0;
        color_target.cycle = false;
        color_target.cycle_resolve_texture = false;

        const pass = sdl.SDL_BeginGPURenderPass(command_buffer, &color_target, 1, null);

        // === 4) Dynamic state + bindings + draw ===
        // Be explicit about viewport. SDL sets a default, but resizing correctness is easier this way.
        const vp: sdl.SDL_GPUViewport = .{
            .x = 0,
            .y = 0,
            .w = @floatFromInt(swap_w),
            .h = @floatFromInt(swap_h),
            .min_depth = 0.0,
            .max_depth = 1.0,
        };
        sdl.SDL_SetGPUViewport(pass, &vp);

        // Bind pipeline (shaders + fixed-function state).
        sdl.SDL_BindGPUGraphicsPipeline(pass, self.pipeline);

        // Bind vertex buffer(s). This provides the per-vertex data consumed by the vertex shader.
        const binding: sdl.SDL_GPUBufferBinding = .{
            .buffer = self.vertex_buffer,
            .offset = 0,
        };
        sdl.SDL_BindGPUVertexBuffers(pass, 0, &binding, 1);

        // Issue a draw: 3 vertices = one triangle.
        sdl.SDL_DrawGPUPrimitives(pass, 3, 1, 0, 0);

        // Close the pass to finalize the render commands.
        sdl.SDL_EndGPURenderPass(pass);

        const t2: i128 = std.time.nanoTimestamp();

        // === 5) Submit recorded work to the GPU ===
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
