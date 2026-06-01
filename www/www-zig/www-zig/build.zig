const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the 'www' executable
    const exe = b.addExecutable(.{
        .name = "www",
        // FIX: Changed .root_source_file to .root_source for newer Zig versions
        .root_source = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This is important for enabling the http client and its dependencies
    exe.linkSystemLibrary("c");

    b.installArtifact(exe);

    // Create a 'run' step to easily run the binary
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

