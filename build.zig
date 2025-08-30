const std = @import("std");

fn addPlatformDependencies(step: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, b: *std.Build) void {
    // Add wlr-data-control protocol implementation
    step.addCSourceFile(.{ .file = b.path("src/wlr_protocol.c") });
    step.addIncludePath(b.path("include"));
    
    // Platform-specific linking
    switch (target.result.os.tag) {
        .linux => {
            step.linkLibC();
            step.linkSystemLibrary("wayland-client");
            step.linkSystemLibrary("X11");
        },
        .macos => {
            step.linkLibC();
            step.linkFramework("AppKit");
            step.linkFramework("Foundation");
        },
        else => {
            step.linkLibC();
        },
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the clipboard library module
    const clipboard_mod = b.addModule("clipboard", .{
        .root_source_file = b.path("src/clipboard.zig"),
    });
    
    // Add include path for wlr protocol headers
    clipboard_mod.addIncludePath(b.path("include"));

    // Library for static linking
    const lib = b.addStaticLibrary(.{
        .name = "nclip2-clipboard",
        .root_source_file = b.path("src/clipboard.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    addPlatformDependencies(lib, target, b);

    b.installArtifact(lib);

    // Wayland read example
    const wayland_read_exe = b.addExecutable(.{
        .name = "wayland-read",
        .root_source_file = b.path("examples/wayland_read.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    wayland_read_exe.root_module.addImport("clipboard", clipboard_mod);
    addPlatformDependencies(wayland_read_exe, target, b);
    b.installArtifact(wayland_read_exe);

    // Wayland event monitoring example
    const wayland_monitor_exe = b.addExecutable(.{
        .name = "wayland-monitor",
        .root_source_file = b.path("examples/wayland_monitor.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    wayland_monitor_exe.root_module.addImport("clipboard", clipboard_mod);
    addPlatformDependencies(wayland_monitor_exe, target, b);
    b.installArtifact(wayland_monitor_exe);

    // Wayland write example
    const wayland_write_exe = b.addExecutable(.{
        .name = "wayland-write",
        .root_source_file = b.path("examples/wayland_write.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    wayland_write_exe.root_module.addImport("clipboard", clipboard_mod);
    addPlatformDependencies(wayland_write_exe, target, b);
    b.installArtifact(wayland_write_exe);

    // X11 read example
    const x11_read_exe = b.addExecutable(.{
        .name = "x11-read",
        .root_source_file = b.path("examples/x11_read.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    x11_read_exe.root_module.addImport("clipboard", clipboard_mod);
    addPlatformDependencies(x11_read_exe, target, b);
    b.installArtifact(x11_read_exe);

    // X11 write example
    const x11_write_exe = b.addExecutable(.{
        .name = "x11-write",
        .root_source_file = b.path("examples/x11_write.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    x11_write_exe.root_module.addImport("clipboard", clipboard_mod);
    addPlatformDependencies(x11_write_exe, target, b);
    b.installArtifact(x11_write_exe);




    // Run commands
    const run_wayland_read_cmd = b.addRunArtifact(wayland_read_exe);
    if (b.args) |args| run_wayland_read_cmd.addArgs(args);
    const run_wayland_read_step = b.step("run-wayland-read", "Run the Wayland clipboard reader");
    run_wayland_read_step.dependOn(&run_wayland_read_cmd.step);

    const run_wayland_monitor_cmd = b.addRunArtifact(wayland_monitor_exe);
    if (b.args) |args| run_wayland_monitor_cmd.addArgs(args);
    const run_wayland_monitor_step = b.step("run-wayland-monitor", "Run the Wayland event-based clipboard monitor");
    run_wayland_monitor_step.dependOn(&run_wayland_monitor_cmd.step);

    const run_wayland_write_cmd = b.addRunArtifact(wayland_write_exe);
    if (b.args) |args| run_wayland_write_cmd.addArgs(args);
    const run_wayland_write_step = b.step("run-wayland-write", "Write text to clipboard via Wayland");
    run_wayland_write_step.dependOn(&run_wayland_write_cmd.step);

    const run_x11_read_cmd = b.addRunArtifact(x11_read_exe);
    if (b.args) |args| run_x11_read_cmd.addArgs(args);
    const run_x11_read_step = b.step("run-x11-read", "Run the X11 clipboard reader");
    run_x11_read_step.dependOn(&run_x11_read_cmd.step);

    const run_x11_write_cmd = b.addRunArtifact(x11_write_exe);
    if (b.args) |args| run_x11_write_cmd.addArgs(args);
    const run_x11_write_step = b.step("run-x11-write", "Write text to clipboard via X11");
    run_x11_write_step.dependOn(&run_x11_write_cmd.step);


    // Tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/clipboard.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    addPlatformDependencies(lib_tests, target, b);

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);
}