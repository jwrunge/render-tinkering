const std = @import("std");
const util = @import("./util.zig");
const ExternDependency = @import("Dependency.zig").ExternDependency;

pub fn add_naga(b: *std.Build, target: std.Build.ResolvedTarget) ExternDependency {
    const naga_version_opt = b.option([]const u8, "naga_version", "Optional naga-cli crate version to install (e.g. 0.28.0). Defaults to latest.");

    const naga_root = "build/naga-cli";
    std.fs.cwd().makePath(naga_root) catch {};

    const naga_exe_name = switch (target.result.os.tag) {
        .windows => "naga.exe",
        else => "naga",
    };
    const naga_bin = b.pathResolve(&.{ naga_root, "bin", naga_exe_name });

    if (!util.fileExists(naga_bin)) {
        var cargo_args = std.ArrayList([]const u8).init(b.allocator);
        cargo_args.appendSlice(&.{
            "cargo",
            "install",
            "naga-cli",
            "--root",
            naga_root,
            "--locked",
        }) catch unreachable;
        if (naga_version_opt) |ver| {
            cargo_args.appendSlice(&.{ "--version", ver }) catch unreachable;
        }

        const install_naga = b.addSystemCommand(cargo_args.toOwnedSlice() catch unreachable);
        return .{ .bin = naga_bin, .step = &install_naga.step };
    }

    return .{ .bin = naga_bin, .step = null };
}
