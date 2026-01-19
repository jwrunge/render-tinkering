const std = @import("std");
const sdlError = @import("Logging.zig").sdlError;
const c = @import("SDL.zig").c;

fn shaderPathAlloc(allocator: std.mem.Allocator, leaf: []const u8) ![]u8 {
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    return try std.fs.path.join(allocator, &.{ exe_dir, "_examples", "sdl_gpu_triangle_wgsl", leaf });
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024);
}

pub const ShaderProgram = struct {
    device: *c.SDL_GPUDevice,
    vs: *c.SDL_GPUShader,
    fs: *c.SDL_GPUShader,

    pub fn init(allocator: std.mem.Allocator, device: *c.SDL_GPUDevice, format: c.SDL_GPUShaderFormat, base_name: []const u8) !ShaderProgram {
        const ext: []const u8 = switch (format) {
            c.SDL_GPU_SHADERFORMAT_MSL => ".metal",
            c.SDL_GPU_SHADERFORMAT_SPIRV => ".spv",
            else => unreachable,
        };

        const leaf = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_name, ext });
        defer allocator.free(leaf);

        const shader_path = try shaderPathAlloc(allocator, leaf);
        defer allocator.free(shader_path);

        const shader_code = try readFileAlloc(allocator, shader_path);
        defer allocator.free(shader_code);

        const vs_info: c.SDL_GPUShaderCreateInfo = .{
            .code_size = shader_code.len,
            .code = @ptrCast(shader_code.ptr),
            .entrypoint = "vs_main",
            .format = format,
            .stage = c.SDL_GPU_SHADERSTAGE_VERTEX,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 0,
            .props = 0,
        };

        const fs_info: c.SDL_GPUShaderCreateInfo = .{
            .code_size = shader_code.len,
            .code = @ptrCast(shader_code.ptr),
            .entrypoint = "fs_main",
            .format = format,
            .stage = c.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 0,
            .props = 0,
        };

        const vs = c.SDL_CreateGPUShader(device, &vs_info) orelse {
            std.debug.print("SDL_CreateGPUShader(vs) failed: {s}\n", .{sdlError()});
            return error.SDLCreateGPUShaderFailed;
        };

        const fs = c.SDL_CreateGPUShader(device, &fs_info) orelse {
            std.debug.print("SDL_CreateGPUShader(fs) failed: {s}\n", .{sdlError()});
            return error.SDLCreateGPUShaderFailed;
        };

        return ShaderProgram{
            .device = device,
            .vs = vs,
            .fs = fs,
        };
    }

    pub fn deinit(self: ShaderProgram) void {
        c.SDL_ReleaseGPUShader(self.device, self.vs);
        c.SDL_ReleaseGPUShader(self.device, self.fs);
    }
};
