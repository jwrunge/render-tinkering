const std = @import("std");
const sdl = @import("../util/sdl.zig").c;

const cpu_mod = @import("core.zig");
const gpu_mod = @import("gpu.zig");

pub const Backend = enum {
    cpu,
    gpu,
};

pub const Renderer = struct {
    backend: Backend = .cpu,
    cpu: cpu_mod.CpuRenderer = undefined,
    gpu: gpu_mod.GpuRenderer = undefined,

    pub const Timings = cpu_mod.CpuRenderer.Timings;

    pub fn init(self: *Renderer, window: *sdl.SDL_Window, w: i32, h: i32, requested: Backend) !void {
        // Default to CPU unless GPU is explicitly requested.
        if (requested == .gpu) {
            if (gpu_mod.GpuRenderer.init(&self.gpu, window)) |_| {
                self.backend = .gpu;
                return;
            } else |err| {
                std.debug.print("GPU init failed ({any}); falling back to CPU\n", .{err});
            }
        }

        try self.cpu.init(window, w, h);
        self.backend = .cpu;
    }

    pub fn deinit(self: *Renderer) void {
        switch (self.backend) {
            .cpu => self.cpu.deinit(),
            .gpu => self.gpu.deinit(),
        }
    }

    pub fn render(self: *Renderer) !Timings {
        return switch (self.backend) {
            .cpu => try self.cpu.render(),
            .gpu => try self.gpu.render(),
        };
    }

    pub fn getBackend(self: *Renderer) Backend {
        return self.backend;
    }
};
