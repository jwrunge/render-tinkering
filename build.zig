const std = @import("std");
const util = @import("build_util/util.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_software_renderer = b.option(bool, "use_software_renderer", "Force SDL software renderer backend (CPU) instead of GPU") orelse false;
    const use_simd_fill = b.option(bool, "use_simd_fill", "Use SIMD/vectorized pixel fill (default: true)") orelse true;
    const naga_bin = b.option([]const u8, "naga_bin", "Path to the naga CLI (defaults to `naga` in PATH)") orelse "naga";
    const shader_dirs = [_][]const u8{
        // Add project shader folders here. Each folder is scanned for `*.wgsl` (non-recursive).
        // Compiled outputs are installed under the same relative folder next to the executable.
        "shaders",
    };

    const exe = b.addExecutable(.{
        .name = "render",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const options = b.addOptions();
    options.addOption(bool, "use_software_renderer", use_software_renderer);
    options.addOption(bool, "use_simd_fill", use_simd_fill);
    exe.root_module.addOptions("build_options", options);

    exe.linkLibC();

    // Make it easy for the runtime loader to find SDL when we install it next to the executable.
    // (On Windows, DLL search rules are different; on macOS/Linux, this is the common approach.)
    switch (target.result.os.tag) {
        .macos => exe.root_module.addRPathSpecial("@executable_path"),
        .linux => exe.root_module.addRPathSpecial("$ORIGIN"),
        else => {},
    }

    // Vendored SDL (always): download SDL3 source into vendor/SDL (if missing)
    // and build it via CMake into build/sdl3-build.
    const sdl_git_tag = b.option([]const u8, "sdl_git_tag", "SDL git tag to fetch when vendoring") orelse "release-3.4.0";
    const sdl_repo = b.option([]const u8, "sdl_repo", "SDL git repository URL") orelse "https://github.com/libsdl-org/SDL.git";

    const sdl_src_dir = "vendor/SDL";
    const sdl_include_dir = "vendor/SDL/include";
    const sdl_build_dir = "build/sdl3-build";

    var sdl_ready_step: ?*std.Build.Step = null;

    // Create vendor/ eagerly so `git clone` has a place to put the repo.
    std.fs.cwd().makePath("vendor") catch {};
    // Ensure the build directory exists so adding -L won't fail.
    std.fs.cwd().makePath(sdl_build_dir) catch {};

    var clone_step: ?*std.Build.Step.Run = null;
    if (!util.dirExists(sdl_src_dir)) {
        const clone = b.addSystemCommand(&.{
            "git",
            "clone",
            "--depth",
            "1",
            "--branch",
            sdl_git_tag,
            sdl_repo,
            sdl_src_dir,
        });
        clone_step = clone;
    }

    // Build only if we don't already have a built dylib.
    // (This keeps `zig build` fast after the first run.)
    const sdl_dylib_path = b.pathResolve(&.{ sdl_build_dir, "libSDL3.0.dylib" });
    if (!util.fileExists(sdl_dylib_path)) {
        const cmake_build_type = switch (optimize) {
            .Debug => "Debug",
            else => "Release",
        };

        const configure = b.addSystemCommand(&.{
            "cmake",
            "-S",
            sdl_src_dir,
            "-B",
            sdl_build_dir,
            "-G",
            "Ninja",
            b.fmt("-DCMAKE_BUILD_TYPE={s}", .{cmake_build_type}),
            "-DSDL_TESTS=OFF",
            "-DSDL_EXAMPLES=OFF",
            "-DSDL_INSTALL=OFF",
        });
        if (clone_step) |c| configure.step.dependOn(&c.step);

        const build_sdl = b.addSystemCommand(&.{ "cmake", "--build", sdl_build_dir });
        build_sdl.step.dependOn(&configure.step);

        sdl_ready_step = &build_sdl.step;
    }

    // Add paths unconditionally; the steps above ensure they will exist by build time.
    exe.addIncludePath(.{ .cwd_relative = sdl_include_dir });
    exe.addLibraryPath(.{ .cwd_relative = sdl_build_dir });

    // Install the SDL3 dylib next to the executable so `zig build run` works without
    // needing DYLD_LIBRARY_PATH.
    if (target.result.os.tag == .macos) {
        const install_sdl0 = b.addInstallBinFile(b.path("build/sdl3-build/libSDL3.0.dylib"), "libSDL3.0.dylib");
        const install_sdl = b.addInstallBinFile(b.path("build/sdl3-build/libSDL3.dylib"), "libSDL3.dylib");

        if (sdl_ready_step) |s| {
            install_sdl0.step.dependOn(s);
            install_sdl.step.dependOn(s);
        }

        b.getInstallStep().dependOn(&install_sdl0.step);
        b.getInstallStep().dependOn(&install_sdl.step);
    }

    exe.linkSystemLibrary("SDL3");

    if (sdl_ready_step) |s| {
        exe.step.dependOn(s);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // --- shaders (generic) ---
    // Compile and install all WGSL shaders in the hard-coded `shader_dirs`.
    const shaders_step = b.step("shaders", "Compile WGSL shaders from shader_dirs (MSL + SPIR-V) and install them");
    inline for (shader_dirs) |dir| {
        util.addWgslShaderDir(b, shaders_step, naga_bin, dir);
    }

    // Ensure `zig build run` gets shaders installed first.
    run_cmd.step.dependOn(shaders_step);
}
