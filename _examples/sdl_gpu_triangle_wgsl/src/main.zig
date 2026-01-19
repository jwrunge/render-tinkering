const std = @import("std");
const sdlError = @import("logging.zig").sdlError;
const ShaderProgram = @import("ShaderProgram.zig").ShaderProgram;
const VertexLayout = @import("VertexLayout.zig").VertexLayout;
const c = @import("SDL.zig").c;

const Vertex = extern struct {
    pos: [2]f32,
};

fn pickShaderFormat(formats: c.SDL_GPUShaderFormat) c.SDL_GPUShaderFormat {
    // Prefer MSL on macOS (Metal driver). Fall back to SPIR-V when available.
    if ((formats & c.SDL_GPU_SHADERFORMAT_MSL) != 0) return c.SDL_GPU_SHADERFORMAT_MSL;
    if ((formats & c.SDL_GPU_SHADERFORMAT_SPIRV) != 0) return c.SDL_GPU_SHADERFORMAT_SPIRV;
    return c.SDL_GPU_SHADERFORMAT_INVALID;
}

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{sdlError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("SDL_gpu triangle (WGSL + naga)", 900, 600, 0) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{sdlError()});
        return error.SDLCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Declare the shader formats we can provide. SDL will pick a backend that can consume one.
    const requested_formats: c.SDL_GPUShaderFormat =
        c.SDL_GPU_SHADERFORMAT_MSL |
        c.SDL_GPU_SHADERFORMAT_SPIRV;

    const device = c.SDL_CreateGPUDevice(requested_formats, false, null) orelse {
        std.debug.print("SDL_CreateGPUDevice failed: {s}\n", .{sdlError()});
        return error.SDLCreateGPUDeviceFailed;
    };
    defer c.SDL_DestroyGPUDevice(device);

    if (!c.SDL_ClaimWindowForGPUDevice(device, window)) {
        std.debug.print("SDL_ClaimWindowForGPUDevice failed: {s}\n", .{sdlError()});
        return error.SDLClaimWindowForGPUDeviceFailed;
    }
    defer c.SDL_ReleaseWindowFromGPUDevice(device, window);

    if (c.SDL_GetGPUDeviceDriver(device)) |name_ptr| {
        std.debug.print("GPU driver: {s}\n", .{std.mem.span(name_ptr)});
    }

    const actual_formats = c.SDL_GetGPUShaderFormats(device);
    const shader_format = pickShaderFormat(actual_formats);
    if (shader_format == c.SDL_GPU_SHADERFORMAT_INVALID) {
        std.debug.print("No supported shader format. Device supports mask=0x{x}\n", .{actual_formats});
        return error.NoSupportedShaderFormat;
    }

    var vb_desc = [_]c.SDL_GPUVertexBufferDescription{
        .{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX, .instance_step_rate = 0 },
        // later you can add slot=1 here for instancing, etc
    };

    var vb_attr = [_]c.SDL_GPUVertexAttribute{
        .{ .location = 0, .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = 0 },
        // later: .{ .location = 1, .buffer_slot = 1, ... } etc
    };

    const layout = VertexLayout{
        .vb_desc = vb_desc[0..],
        .vb_attr = vb_attr[0..],
    };

    const triangle_shader = try ShaderProgram.init(allocator, device, shader_format, "triangle");
    defer triangle_shader.deinit();

    const swap_format = c.SDL_GetGPUSwapchainTextureFormat(device, window);

    var blend_state: c.SDL_GPUColorTargetBlendState = std.mem.zeroes(c.SDL_GPUColorTargetBlendState);
    blend_state.enable_blend = false;
    blend_state.enable_color_write_mask = false; // when false, SDL writes all RGBA channels

    const color_targets = [_]c.SDL_GPUColorTargetDescription{.{
        .format = swap_format,
        .blend_state = blend_state,
    }};

    const target_info: c.SDL_GPUGraphicsPipelineTargetInfo = .{
        .color_target_descriptions = &color_targets,
        .num_color_targets = 1,
        .depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_INVALID,
        .has_depth_stencil_target = false,
        .padding1 = 0,
        .padding2 = 0,
        .padding3 = 0,
    };

    var raster: c.SDL_GPURasterizerState = std.mem.zeroes(c.SDL_GPURasterizerState);
    raster.fill_mode = c.SDL_GPU_FILLMODE_FILL;
    raster.cull_mode = c.SDL_GPU_CULLMODE_NONE;
    raster.front_face = c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE;
    raster.enable_depth_bias = false;
    raster.enable_depth_clip = true;

    var msaa: c.SDL_GPUMultisampleState = std.mem.zeroes(c.SDL_GPUMultisampleState);
    msaa.sample_count = c.SDL_GPU_SAMPLECOUNT_1;
    msaa.sample_mask = 0;
    msaa.enable_mask = false;
    msaa.enable_alpha_to_coverage = false;

    var ds: c.SDL_GPUDepthStencilState = std.mem.zeroes(c.SDL_GPUDepthStencilState);
    ds.enable_depth_test = false;
    ds.enable_depth_write = false;
    ds.enable_stencil_test = false;

    const pipeline_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = triangle_shader.vs,
        .fragment_shader = triangle_shader.fs,
        .vertex_input_state = layout.vertexInputState(),
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = raster,
        .multisample_state = msaa,
        .depth_stencil_state = ds,
        .target_info = target_info,
        .props = 0,
    };

    const pipeline = c.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse {
        std.debug.print("SDL_CreateGPUGraphicsPipeline failed: {s}\n", .{sdlError()});
        return error.SDLCreateGPUGraphicsPipelineFailed;
    };
    defer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);

    // Create a GPU vertex buffer + upload 3 clip-space vertices.
    const vertices = [_]Vertex{
        .{ .pos = .{ -0.75, -0.60 } },
        .{ .pos = .{ 0.75, -0.60 } },
        .{ .pos = .{ 0.0, 0.80 } },
    };

    const vb_info: c.SDL_GPUBufferCreateInfo = .{
        .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = @sizeOf(@TypeOf(vertices)),
        .props = 0,
    };

    const vertex_buffer = c.SDL_CreateGPUBuffer(device, &vb_info) orelse {
        std.debug.print("SDL_CreateGPUBuffer failed: {s}\n", .{sdlError()});
        return error.SDLCreateGPUBufferFailed;
    };
    defer c.SDL_ReleaseGPUBuffer(device, vertex_buffer);

    const tb_info: c.SDL_GPUTransferBufferCreateInfo = .{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = vb_info.size,
        .props = 0,
    };

    const transfer_buffer = c.SDL_CreateGPUTransferBuffer(device, &tb_info) orelse {
        std.debug.print("SDL_CreateGPUTransferBuffer failed: {s}\n", .{sdlError()});
        return error.SDLCreateGPUTransferBufferFailed;
    };
    defer c.SDL_ReleaseGPUTransferBuffer(device, transfer_buffer);

    const mapped = c.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse {
        std.debug.print("SDL_MapGPUTransferBuffer failed: {s}\n", .{sdlError()});
        return error.SDLMapGPUTransferBufferFailed;
    };
    @memcpy(@as([*]u8, @ptrCast(mapped))[0..vb_info.size], std.mem.asBytes(&vertices));
    c.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);

    // Upload once using a transient command buffer.
    {
        const cmd = c.SDL_AcquireGPUCommandBuffer(device) orelse {
            std.debug.print("SDL_AcquireGPUCommandBuffer failed: {s}\n", .{sdlError()});
            return error.SDLAcquireGPUCommandBufferFailed;
        };

        const copy_pass = c.SDL_BeginGPUCopyPass(cmd);

        const src: c.SDL_GPUTransferBufferLocation = .{
            .transfer_buffer = transfer_buffer,
            .offset = 0,
        };

        const dst: c.SDL_GPUBufferRegion = .{
            .buffer = vertex_buffer,
            .offset = 0,
            .size = vb_info.size,
        };

        c.SDL_UploadToGPUBuffer(copy_pass, &src, &dst, false);
        c.SDL_EndGPUCopyPass(copy_pass);

        if (!c.SDL_SubmitGPUCommandBuffer(cmd)) {
            std.debug.print("SDL_SubmitGPUCommandBuffer (upload) failed: {s}\n", .{sdlError()});
            return error.SDLSubmitGPUCommandBufferFailed;
        }
    }

    // Main loop
    var running = true;
    while (running) {
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e)) {
            switch (e.type) {
                c.SDL_EVENT_QUIT => running = false,
                else => {},
            }
        }

        const cmd = c.SDL_AcquireGPUCommandBuffer(device) orelse {
            std.debug.print("SDL_AcquireGPUCommandBuffer failed: {s}\n", .{sdlError()});
            return error.SDLAcquireGPUCommandBufferFailed;
        };

        var swapchain_texture: ?*c.SDL_GPUTexture = null;
        var swap_w: u32 = 0;
        var swap_h: u32 = 0;

        if (!c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd, window, &swapchain_texture, &swap_w, &swap_h)) {
            std.debug.print("SDL_WaitAndAcquireGPUSwapchainTexture failed: {s}\n", .{sdlError()});
            return error.SDLAcquireSwapchainTextureFailed;
        }

        if (swapchain_texture == null) {
            _ = c.SDL_SubmitGPUCommandBuffer(cmd);
            continue;
        }

        var color_target: c.SDL_GPUColorTargetInfo = std.mem.zeroes(c.SDL_GPUColorTargetInfo);
        color_target.texture = swapchain_texture.?;
        color_target.clear_color = c.SDL_FColor{ .r = 0.02, .g = 0.02, .b = 0.02, .a = 1.0 };
        color_target.load_op = c.SDL_GPU_LOADOP_CLEAR;
        color_target.store_op = c.SDL_GPU_STOREOP_STORE;

        const pass = c.SDL_BeginGPURenderPass(cmd, &color_target, 1, null);

        // Be explicit about viewport. SDL sets a default, but resizing correctness is easier this way.
        const vp: c.SDL_GPUViewport = .{
            .x = 0,
            .y = 0,
            .w = @floatFromInt(swap_w),
            .h = @floatFromInt(swap_h),
            .min_depth = 0.0,
            .max_depth = 1.0,
        };
        c.SDL_SetGPUViewport(pass, &vp);

        c.SDL_BindGPUGraphicsPipeline(pass, pipeline);

        const binding: c.SDL_GPUBufferBinding = .{
            .buffer = vertex_buffer,
            .offset = 0,
        };
        c.SDL_BindGPUVertexBuffers(pass, 0, &binding, 1);

        c.SDL_DrawGPUPrimitives(pass, 3, 1, 0, 0);
        c.SDL_EndGPURenderPass(pass);

        if (!c.SDL_SubmitGPUCommandBuffer(cmd)) {
            std.debug.print("SDL_SubmitGPUCommandBuffer failed: {s}\n", .{sdlError()});
            return error.SDLSubmitGPUCommandBufferFailed;
        }
    }
}
