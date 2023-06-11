// thank you https://zig.news/xq/zig-build-explained-part-1-59lf

const std = @import("std");
const path = std.fs.path;

const c_flags = .{
    "-std=c99",
    "-DNDEBUG=",
    "-Dfprintf(...)=",
    "-fno-exceptions",
};

pub fn libPkgStep(b: *std.build.Builder, rel_path: []const u8) !*std.build.LibExeObjStep {
    const lib = b.addStaticLibrary("tree-sitter", try path.join(b.allocator, &.{rel_path, "tree_sitter.zig"}));
    try populateTreeSitterStep(lib, rel_path);
    return lib;
}

pub fn pkg(b: *std.build.Builder, rel_path: []const u8) !std.build.Pkg {
    return .{
        .name = "tree-sitter",
        .source = std.build.FileSource{
            .path = try path.join(b.allocator, &.{ rel_path, "tree_sitter.zig" })
        },
        .dependencies = null,
    };
}

pub fn populateTreeSitterStep(step: *std.build.LibExeObjStep, rel_path: []const u8) !void {
    step.linkLibC();
    step.addIncludePath(try path.join(step.builder.allocator,
                            &.{rel_path, "../thirdparty/tree-sitter/lib/include"}));
    step.addCSourceFile(try path.join(step.builder.allocator,
                            &.{rel_path, "../thirdparty/tree-sitter/lib/src/lib.c"}),
                        &c_flags);
    step.addIncludePath(try path.join(step.builder.allocator,
                            &.{rel_path, "../thirdparty/tree-sitter/lib/src"}));
}

pub fn build(b: *std.build.Builder) !void {
    // allow picking target
    const target = b.standardTargetOptions(.{});
    // allow picking Release/Debug/Safe/Small
    const mode = b.standardReleaseOptions();

    const lib = try libPkgStep(b, ".");
    lib.install();

    var tests = b.addTest("./tree_sitter.zig");
    try populateTreeSitterStep(tests, ".");

    // use `-Dtest-filter=x` to filter on tests
    const maybe_test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match the filter");
    if (maybe_test_filter) |test_filter|
        tests.setFilter(test_filter);

    // zig build-exe -lc -lc++ -Lthirdparty/tree-sitter -Ithirdparty/tree-sitter/lib/include
    // -ltree-sitter thirdparty/tree-sitter-cpp/src/parser.c thirdparty/tree-sitter-cpp/src/scanner.cc src/code.zig
    for ([_]*std.build.LibExeObjStep{lib, tests}) |step| {
        step.setBuildMode(mode);
        step.setTarget(target);
    }

    const run_tests = b.step("test", "run tests");
    run_tests.dependOn(&tests.step);
}
