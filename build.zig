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
            step.linkSystemLibrary("Xmu");
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

    // Simple executable for basic clipboard reading
    const simple_exe = b.addExecutable(.{
        .name = "clipboard-simple",
        .root_source_file = b.path("examples/simple.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    simple_exe.root_module.addImport("clipboard", clipboard_mod);
    
    addPlatformDependencies(simple_exe, target, b);
    
    b.installArtifact(simple_exe);

    // Monitor executable for event-based clipboard monitoring
    const monitor_exe = b.addExecutable(.{
        .name = "clipboard-monitor",
        .root_source_file = b.path("examples/monitor.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    monitor_exe.root_module.addImport("clipboard", clipboard_mod);
    
    addPlatformDependencies(monitor_exe, target, b);
    
    b.installArtifact(monitor_exe);

    // Write test executable
    const write_test_exe = b.addExecutable(.{
        .name = "clipboard-write-test",
        .root_source_file = b.path("examples/write_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    write_test_exe.root_module.addImport("clipboard", clipboard_mod);
    addPlatformDependencies(write_test_exe, target, b);
    b.installArtifact(write_test_exe);

    // Image test executable
    const image_test_exe = b.addExecutable(.{
        .name = "clipboard-image-test",
        .root_source_file = b.path("examples/image_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    image_test_exe.root_module.addImport("clipboard", clipboard_mod);
    addPlatformDependencies(image_test_exe, target, b);
    b.installArtifact(image_test_exe);

    // Run commands
    const run_simple_cmd = b.addRunArtifact(simple_exe);
    
    if (b.args) |args| {
        run_simple_cmd.addArgs(args);
    }
    
    const run_simple_step = b.step("run-simple", "Run the simple clipboard reader");
    run_simple_step.dependOn(&run_simple_cmd.step);

    const run_monitor_cmd = b.addRunArtifact(monitor_exe);
    
    if (b.args) |args| {
        run_monitor_cmd.addArgs(args);
    }
    
    const run_monitor_step = b.step("run-monitor", "Run the event-based clipboard monitor");
    run_monitor_step.dependOn(&run_monitor_cmd.step);

    const run_write_test_cmd = b.addRunArtifact(write_test_exe);
    
    if (b.args) |args| {
        run_write_test_cmd.addArgs(args);
    }
    
    const run_write_test_step = b.step("run-write-test", "Run the clipboard write test");
    run_write_test_step.dependOn(&run_write_test_cmd.step);

    const run_image_test_cmd = b.addRunArtifact(image_test_exe);
    
    if (b.args) |args| {
        run_image_test_cmd.addArgs(args);
    }
    
    const run_image_test_step = b.step("run-image-test", "Run the clipboard image test");
    run_image_test_step.dependOn(&run_image_test_cmd.step);

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