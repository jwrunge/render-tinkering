const std = @import("std");

pub const ExternDependency = struct {
    bin: []const u8,
    step: ?*std.Build.Step,
};
