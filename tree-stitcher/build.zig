// thank you https://zig.news/xq/zig-build-explained-part-1-59lf
const std = @import("std");

const tree_sitter_pkg = std.build.Pkg{
    .name = "tree-sitter",
    .source = std.build.FileSource.relative("../tree-sitter/tree_sitter.zig"),
    .dependencies = null,
};

const zig_clap_package = std.build.Pkg{
    .name = "zig-clap",
    // do I need gyro or zigmod to let the package build itself?
    .source = std.build.FileSource.relative("../thirdparty/zig-clap/clap.zig"),
    .dependencies = null,
};

pub fn build(b: *std.build.Builder) void {
    // TODO: replace with .addSystemCommand
    var tree_sitter_step = buildTreeSitter(b);

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    var tests = b.addTest("src/bindings.zig");
    // use `-Dtest-filter=x` to filter on tests
    const maybe_test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match the filter");
    if (maybe_test_filter) |test_filter| { tests.setFilter(test_filter); }

    const exe = b.addExecutable("tsquery", "src/tsquery.zig");
    exe.step.dependOn(tree_sitter_step);
    exe.setTarget(target);

    const ast_helper_gen_exe = b.addExecutable("ast-helper-gen", "src/ast_helper_gen/main.zig");
    ast_helper_gen_exe.setTarget(target);
    ast_helper_gen_exe.addPackage(zig_clap_package);
    ast_helper_gen_exe.linkLibC();
    ast_helper_gen_exe.install();
    const build_ast_helper_gen = b.step("ast-helper-gen", "Build the ast-helper-gen tool");
    build_ast_helper_gen.dependOn(&ast_helper_gen_exe.step);

    const build_chibi_bindings_src = b.addSystemCommand(&.{ "chibi-ffi", "./tree-sitter-chibi-ffi.scm" });
    // TODO: ask tree-sitter to tag their struct typedefs
    const patch_chibi_bindings_src = b.addSystemCommand(&[_][]const u8{
        "sed", "-i", "-r",
        "-e", "s/struct (TS\\w+)/\\1/g", // remove struct keyword usage for tree-sitter APIs
        "-e", "/sexp_car\\(res\\) =/s/\\)\\);$/);/", // remove extraneous ')'
        "./tree-sitter-chibi-ffi.c"
    });
    patch_chibi_bindings_src.step.dependOn(&build_chibi_bindings_src.step);

    const query_binding = b.addSharedLibrary("bindings", "src/chibi_transform.zig", .unversioned);
    query_binding.addCSourceFile("./tree-sitter-chibi-ffi.c", &.{"-std=c99", "-fPIC"});
    // compiler bug: previously I accidentally did src/chibi_macros.h here, which caused a malformed object file
    // which ld.lld would think was a linker script and scream at
    query_binding.addCSourceFile("src/chibi_macros.c", &.{"-std=c99", "-fPIC"});
    query_binding.linkSystemLibrary("chibi-scheme");
    query_binding.addIncludePath("src");
    query_binding.step.dependOn(&patch_chibi_bindings_src.step);

    const driver_exe = b.addExecutable("driver", "src/driver/main.zig");
    driver_exe.setTarget(target);
    driver_exe.linkLibC();
    driver_exe.install();
    driver_exe.addIncludePath("./src/driver");
    driver_exe.linkSystemLibrary("chibi-scheme");
    driver_exe.addCSourceFile("src/chibi_macros.c", &.{"-std=c11", "-fPIC"});
    const driver = b.step("driver", "Build the driver");
    driver.dependOn(&driver_exe.step);

    // TODO: deduplicate from regular driver
    const webdriver_exe = b.addStaticLibrary("webdriver", "src/driver/main.zig");
    var webTarget = target;
    webTarget.cpu_arch = .wasm32;
    // can't use emscripten target doesn't support a lot of stuff
    // maybe should use freestanding? (also doesn't support stdin/err)
    webTarget.os_tag = .wasi;
    webdriver_exe.setTarget(webTarget);
    webdriver_exe.linkLibC();
    webdriver_exe.install();
    webdriver_exe.addIncludePath("./src/driver");
    webdriver_exe.addIncludePath("./thirdparty");
    webdriver_exe.linkSystemLibrary("chibi-scheme");
    webdriver_exe.addCSourceFile("src/chibi_macros.c", &.{"-std=c11", "-fPIC"});

    // emcc -O0 chibi-scheme-static.bc
    //-o $@ -s ALLOW_MEMORY_GROWTH=1 -s MODULARIZE=1
    //-s EXPORT_NAME=\"Chibi\" -s EXPORTED_FUNCTIONS=@js/exported_functions.json
    //`find  lib -type f \( -name "*.scm" -or -name "*.sld" \) -printf " --preload-file %p"`
    //-s 'EXTRA_EXPORTED_RUNTIME_METHODS=["ccall", "cwrap"]' --pre-js js/pre.js --post-js js/post.js
    const link_webdriver = b.addSystemCommand(&[_][]const u8{
        "emcc",
        "/home/mike/personal/chibi-scheme/js/chibi.wasm",
        "-o", "out/repl.wasm",
        "-s", "STANDALONE_WASM",
        "-s", "EXPORTED_FUNCTIONS=_initDriver",
        "-s", "LLD_REPORT_UNDEFINED",
        "--no-entry",
        "-O0",
    });
    link_webdriver.addFileSourceArg(webdriver_exe.getOutputSource());
    link_webdriver.step.dependOn(&webdriver_exe.step);

    // FIXME: why doesn't this step work? I keep needing to do full zig build...
    const webdriver = b.step("webdriver", "Build the web driver");
    webdriver.dependOn(&link_webdriver.step);

    // zig build-exe -lc -lc++ -Lthirdparty/tree-sitter -Ithirdparty/tree-sitter/lib/include
    // -ltree-sitter thirdparty/tree-sitter-cpp/src/parser.c thirdparty/tree-sitter-cpp/src/scanner.cc src/code.zig
    for ([_]*std.build.LibExeObjStep{exe, tests, query_binding}) |artifact| {
        artifact.setBuildMode(mode);
        artifact.setTarget(target);
        artifact.linkLibC();
        artifact.linkSystemLibrary("c++");
        // TODO: move thirdparty up to share it more appropriately
        artifact.addIncludePath("../thirdparty/tree-sitter/lib/include");
        artifact.addLibraryPath("../thirdparty/tree-sitter");
        artifact.linkSystemLibrary("tree-sitter");
        artifact.addCSourceFile("../thirdparty/tree-sitter-cpp/src/parser.c", &.{"-std=c99"});
        artifact.addCSourceFile("../thirdparty/tree-sitter-cpp/src/scanner.cc", &.{"-std=c++14"});
        artifact.addPackage(tree_sitter_pkg);
    }

    // exe.install();
    query_binding.install();

    var test_step = b.step("unit-test", "run unit tests");
    test_step.dependOn(&tests.step);

    const e2e_test_step_impl = b.addSystemCommand(&[_][]const u8{
        "/bin/bash", "./test.sh"
    });
    const e2e_test_step = b.step("test", "run tests");
    e2e_test_step.dependOn(&e2e_test_step_impl.step);
    e2e_test_step.dependOn(test_step); // TODO: fix spacing in report of merged tests

    const run_tsquery_cmd = exe.run();
    run_tsquery_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_tsquery_cmd.addArgs(args);
    }

    const run_tsquery_step = b.step("query", "Run tsquery");
    run_tsquery_step.dependOn(&run_tsquery_cmd.step);
}

// TODO: abstract the concept of adding a gnumake invocation step (also check if zig has something for this)
pub fn buildTreeSitter(b: *std.build.Builder) *std.build.Step {
    const make_tree_sitter = b.addSystemCommand(&[_][]const u8{ "/bin/make", "--directory", "../thirdparty/tree-sitter" });
    //const make_tree_sitter = std.build.RunStep.create(b, "run 'make' in thirdparty tree_sitter dep");
    //make_tree_sitter.addArgs(&[_][]const u8{ "/bin/make", "--directory", "../thirdparty/tree-sitter" });
    return &make_tree_sitter.step;
}

