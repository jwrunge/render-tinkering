const std = @import("std");
const util = @import("./util.zig");

pub fn vendor_sdl(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    exe: *std.Build.Step.Compile,
) void {
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
}
