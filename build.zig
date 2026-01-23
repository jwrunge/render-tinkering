const std = @import("std");
const util = @import("build_util/util.zig");
const add_naga = @import("build_util/install_naga.zig").add_naga;
const vendor_sdl = @import("build_util/vendor_sdl.zig").vendor_sdl;
const compile_shaders = @import("build_util/compile_shaders.zig").compile_shaders;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // External deps
    const naga = add_naga(b, target);

    const exe = b.addExecutable(.{
        .name = "render",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const options = b.addOptions();
    exe.root_module.addOptions("build_options", options);

    exe.linkLibC();

    // Internal deps
    vendor_sdl(b, target, optimize, exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Ensure `zig build run` gets shaders installed first.
    const shaders_step = compile_shaders(b, naga);
    run_cmd.step.dependOn(shaders_step);
}
