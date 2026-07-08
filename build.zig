const std = @import("std");

const module_name = "clix";
const source_path = "src/clix.zig";
const tests_path = "tests/clix_tests.zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clix_module = addClixModule(b, target, optimize);
    const tests = addTests(b, target, optimize, clix_module);

    const check_step = b.step("check", "Compile the library and tests");
    check_step.dependOn(&tests.step);
    b.default_step.dependOn(&tests.step);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}

fn addClixModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.addModule(module_name, .{
        .root_source_file = b.path(source_path),
        .target = target,
        .optimize = optimize,
    });
}

fn addTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    clix_module: *std.Build.Module,
) *std.Build.Step.Compile {
    return b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(tests_path),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = module_name, .module = clix_module },
            },
        }),
    });
}
