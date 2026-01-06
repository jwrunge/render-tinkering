const std = @import("std");

fn addIncludePathIfExists(exe: *std.Build.Step.Compile, path: []const u8) void {
    if (std.fs.path.isAbsolute(path)) {
        if (std.fs.openDirAbsolute(path, .{})) |dir_const| {
            var dir = dir_const;
            dir.close();
            exe.addIncludePath(.{ .cwd_relative = path });
        } else |_| {}
    } else {
        if (std.fs.cwd().openDir(path, .{})) |dir_const| {
            var dir = dir_const;
            dir.close();
            exe.addIncludePath(.{ .cwd_relative = path });
        } else |_| {}
    }
}

fn addLibraryPathIfExists(exe: *std.Build.Step.Compile, path: []const u8) void {
    if (std.fs.path.isAbsolute(path)) {
        if (std.fs.openDirAbsolute(path, .{})) |dir_const| {
            var dir = dir_const;
            dir.close();
            exe.addLibraryPath(.{ .cwd_relative = path });
        } else |_| {}
    } else {
        if (std.fs.cwd().openDir(path, .{})) |dir_const| {
            var dir = dir_const;
            dir.close();
            exe.addLibraryPath(.{ .cwd_relative = path });
        } else |_| {}
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "render",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();

    // SDL3 discovery order:
    // 1) Explicit include/lib dirs (most precise)
    // 2) `-Dsdl3_prefix=...` (prefix containing include/ and lib/)
    // 3) Auto-detect SDL3 from the existing CMake FetchContent build (build/_deps)
    // 4) Common Homebrew prefixes

    const sdl3_include_dir_opt = b.option([]const u8, "sdl3_include_dir", "SDL3 include dir (contains SDL3/SDL.h)") orelse "";
    const sdl3_lib_dir_opt = b.option([]const u8, "sdl3_lib_dir", "SDL3 library dir (contains libSDL3.*)") orelse "";
    const sdl3_prefix_opt = b.option([]const u8, "sdl3_prefix", "Prefix containing include/ and lib/ for SDL3") orelse "";

    if (sdl3_include_dir_opt.len != 0) {
        addIncludePathIfExists(exe, sdl3_include_dir_opt);
    }
    if (sdl3_lib_dir_opt.len != 0) {
        addLibraryPathIfExists(exe, sdl3_lib_dir_opt);
    }

    if (sdl3_include_dir_opt.len == 0 and sdl3_lib_dir_opt.len == 0) {
        if (sdl3_prefix_opt.len != 0) {
            addIncludePathIfExists(exe, b.fmt("{s}/include", .{sdl3_prefix_opt}));
            addLibraryPathIfExists(exe, b.fmt("{s}/lib", .{sdl3_prefix_opt}));
        } else {
            // If you previously built SDL3 via the CMake setup in this repo,
            // re-use those artifacts to avoid requiring a system install.
            addIncludePathIfExists(exe, b.pathResolve(&.{ "build", "_deps", "sdl3-src", "include" }));
            addLibraryPathIfExists(exe, b.pathResolve(&.{ "build", "_deps", "sdl3-build" }));

            // Common Homebrew prefixes (Apple Silicon + Intel Macs).
            const prefixes = [_][]const u8{ "/opt/homebrew", "/usr/local" };
            inline for (prefixes) |p| {
                addIncludePathIfExists(exe, p ++ "/include");
                addLibraryPathIfExists(exe, p ++ "/lib");
            }
        }
    }

    exe.linkSystemLibrary("SDL3");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
