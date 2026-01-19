const std = @import("std");

pub fn dirExists(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        if (std.fs.openDirAbsolute(path, .{})) |dir_const| {
            var dir = dir_const;
            dir.close();
            return true;
        } else |_| return false;
    } else {
        if (std.fs.cwd().openDir(path, .{})) |dir_const| {
            var dir = dir_const;
            dir.close();
            return true;
        } else |_| return false;
    }
}

pub fn fileExists(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        if (std.fs.openFileAbsolute(path, .{})) |file_const| {
            var file = file_const;
            file.close();
            return true;
        } else |_| return false;
    } else {
        if (std.fs.cwd().openFile(path, .{})) |file_const| {
            var file = file_const;
            file.close();
            return true;
        } else |_| return false;
    }
}

pub fn sanitizePathForBuildDir(b: *std.Build, path: []const u8) []const u8 {
    // Turn a relative path like "assets/shaders" into something safe for a single folder name.
    // This is only used for build output folders.
    var buf = std.ArrayList(u8).init(b.allocator);
    for (path) |ch| {
        switch (ch) {
            '/', '\\', ':', ' ' => buf.append('_') catch unreachable,
            else => buf.append(ch) catch unreachable,
        }
    }
    return buf.toOwnedSlice() catch unreachable;
}

pub fn addWgslShaderDir(
    b: *std.Build,
    compile_step: *std.Build.Step,
    naga_bin: []const u8,
    shader_dir_path: []const u8,
) void {
    // Compile all `.wgsl` files directly in `shader_dir_path` (non-recursive) into
    // SPIR-V and MSL, and install them under the same relative directory next to the executable.

    const safe_dir = sanitizePathForBuildDir(b, shader_dir_path);
    const out_dir = b.fmt("build/shaders/{s}", .{safe_dir});
    std.fs.cwd().makePath(out_dir) catch {};

    var shader_dir = std.fs.cwd().openDir(shader_dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Failed to open shader dir {s}: {any}\n", .{ shader_dir_path, err });
        return;
    };
    defer shader_dir.close();

    var it = shader_dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".wgsl")) continue;

        const stem = std.fs.path.stem(entry.name);
        const input_path = b.fmt("{s}/{s}", .{ shader_dir_path, entry.name });
        const out_spv = b.fmt("{s}/{s}.spv", .{ out_dir, stem });
        const out_metal = b.fmt("{s}/{s}.metal", .{ out_dir, stem });

        // naga-cli v28+ uses: `naga <input> <output...>` and infers output kinds from extensions.
        const naga_cmd = b.addSystemCommand(&.{
            naga_bin,
            "--input-kind",
            "wgsl",
            input_path,
            out_spv,
            out_metal,
        });
        compile_step.dependOn(&naga_cmd.step);

        // Install compiled shaders next to the executable.
        // Preserve the given relative directory (e.g. `shaders/foo.spv`).
        const install_spv = b.addInstallBinFile(b.path(out_spv), b.fmt("{s}/{s}.spv", .{ shader_dir_path, stem }));
        const install_metal = b.addInstallBinFile(b.path(out_metal), b.fmt("{s}/{s}.metal", .{ shader_dir_path, stem }));
        install_spv.step.dependOn(&naga_cmd.step);
        install_metal.step.dependOn(&naga_cmd.step);
        b.getInstallStep().dependOn(&install_spv.step);
        b.getInstallStep().dependOn(&install_metal.step);
    }
}
