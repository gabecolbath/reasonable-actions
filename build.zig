const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "scatty",
        .root_module = exe_mod,
    });

    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    const uuid = b.dependency("uuid", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("httpz", httpz.module("httpz")); 
    exe.root_module.addImport("uuid", uuid.module("uuid"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests."); 

    const app_test = b.addTest(.{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
    });

    const server_test = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    app_test.root_module.addImport("httpz", httpz.module("httpz"));
    app_test.root_module.addImport("uuid", uuid.module("uuid"));

    server_test.root_module.addImport("httpz", httpz.module("httpz"));
    server_test.root_module.addImport("uuid", uuid.module("uuid"));

    const run_app_tests = b.addRunArtifact(app_test);
    const run_server_tests = b.addRunArtifact(server_test);
    test_step.dependOn(&run_app_tests.step);
    test_step.dependOn(&run_server_tests.step);
}
