const std = @import("std");
const util = @import("./util.zig");
const ExternDependency = @import("Dependency.zig").ExternDependency;

pub fn compile_shaders(b: *std.Build, naga: ExternDependency) *std.Build.Step {
    // Compile and install all WGSL shaders in the hard-coded `shader_dirs`.
    const shaders_step = b.step("shaders", "Compile WGSL shaders from shader_dirs (MSL + SPIR-V) and install them");
    if (naga.step) |s| {
        shaders_step.dependOn(s);
    }

    const shader_dirs = [_][]const u8{
        "shaders",
    };

    inline for (shader_dirs) |dir| {
        util.addWgslShaderDir(b, shaders_step, naga.bin, dir);
    }

    return shaders_step;
}
