// thank you https://zig.news/xq/zig-build-explained-part-1-59lf

const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    var tree_sitter_step = buildTreeSitter(b);
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("tree-sitter", "./tree_sitter.zig");

    lib.step.dependOn(tree_sitter_step);

    lib.setTarget(target);

    var tests = b.addTest("tree_sitter.zig");

    // use `-Dtest-filter=x` to filter on tests
    const maybe_test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match the filter");
    if (maybe_test_filter) |test_filter| { tests.setFilter(test_filter); }

    // zig build-exe -lc -lc++ -Lthirdparty/tree-sitter -Ithirdparty/tree-sitter/lib/include
    // -ltree-sitter thirdparty/tree-sitter-cpp/src/parser.c thirdparty/tree-sitter-cpp/src/scanner.cc src/code.zig
    for ([_]*std.build.LibExeObjStep{lib, tests}) |artifact| {
        artifact.setBuildMode(mode);
        artifact.linkLibC();
        artifact.addIncludePath("../thirdparty/tree-sitter/lib/include");
        const c_flags = .{"-std=c99", "-DNDEBUG=", "-Dfprintf(...)=", "-fno-exceptions"};
        artifact.addCSourceFile("../thirdparty/tree-sitter/lib/src/lib.c", &c_flags);
        artifact.addIncludePath("../thirdparty/tree-sitter/lib/src");
    }

    lib.install();

    const test_step = b.step("test", "run tests");
    test_step.dependOn(&tests.step);
}

// TODO: abstract the concept of adding a gnumake invocation step (also check if zig has something for this)
pub fn buildTreeSitter(b: *std.build.Builder) *std.build.Step {
    const make_tree_sitter = std.build.RunStep.create(b, "run 'make' in thirdparty tree_sitter dep");
    make_tree_sitter.addArgs(&[_][]const u8{ "/bin/make", "--directory", "../thirdparty/tree-sitter" });
    return &make_tree_sitter.step;
}

