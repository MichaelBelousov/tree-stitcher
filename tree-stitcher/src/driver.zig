//! web driver of sizr-lisp, a (completey chibi-scheme-based) scheme interpreter
//! with the sizr primitives built in

// TODO: rename owning directory to webdriver, doesn't support non-web use case yet,
// and probably want a different directory for that

const std = @import("std");
const builtin = @import("builtin");
const chibi_transform_funcs = @import("./chibi_transform.zig");
const bindings = @import("./bindings.zig");
const ts = @import("tree-sitter");

// FIXME: create a package of chibi bindings
const chibi = @cImport({
    if (builtin.os.tag == .wasi) {
        @cDefine("SEXP_USE_DL", "0");
    }
    @cInclude("chibi_macros.h");
    @cInclude("dlfcn.h");
});

/// alias for the c import to use when using non-chibi C apis
/// this chibi import should really be replaced with a properly wrapping package
const c = chibi;

var chibi_ctx: chibi.sexp = null;

// TODO: consider using a different allocator
var allocator = std.heap.c_allocator;

var preopens: std.fs.wasi.PreopenList = undefined;

var target_buf: []u8 = undefined;

// no dynamic language loading yet :/
// export fn loadAndSetLanguage(in_path: ?[*:0]const u8, in_sym: ?[*:0]const u8) bool {
//     const path = in_path orelse {
//         std.debug.print("loadAndSetLanguage path arg was null\n", .{});
//         return false;
//     };
//     const sym = in_sym orelse {
//         std.debug.print("loadAndSetLanguage sym arg was null\n", .{});
//         return false;
//     };
//     const dll = std.c.dlopen(path, c.RTLD_NOW) orelse {
//         std.debug.print("failed to dlopen '{s}'", .{ path[0..std.mem.len(path)] });
//         return false;
//     };
//     const func = std.c.dlsym(dll, sym) orelse {
//         std.debug.print("failed to dlsym '{s}'", .{ sym[0..std.mem.len(sym)] });
//         return false;
//     };
//     return bindings.set_language(@ptrCast(?*const fn() *ts.c_api.TSLanguage, func));
// }

extern fn tree_sitter_cpp() *ts.c_api.TSLanguage;
extern fn tree_sitter_python() *ts.c_api.TSLanguage;
extern fn tree_sitter_javascript() *ts.c_api.TSLanguage;

export fn load_cpp() void { return bindings.set_language(tree_sitter_cpp()); }
export fn load_python() void { return bindings.set_language(tree_sitter_python()); }
export fn load_javascript() void { return bindings.set_language(tree_sitter_javascript()); }

export fn init() u16 {
    // const args = std.process.argsAlloc(allocator) catch |e| {
    //     std.debug.print("proc arg alloc err: {}\n", .{e});
    //     return @errorToInt(e);
    // };
    // defer std.process.argsFree(allocator, args);
    // for (args) |arg| {
    //     std.debug.print("arg: {s}\n", .{arg});
    // }

    preopens = std.fs.wasi.PreopenList.init(allocator);
    // // populate causes integer overflow somehow,
    // no backtraces so haven't looked into it yet
    // preopens.populate("/") catch return 1;
    // preopens.populate("/") catch |e| {
    //     std.debug.print("preopen populate err: {}\n", .{e});
    //     return @errorToInt(e);
    // };
    // for (preopens.asSlice()) |preopen, i| {
    //     std.debug.print("preopen {}: {}\n", .{i, preopen});
    // }
    // std.os.initPreopensWasi(allocator, "/") catch |e| {
    //     std.debug.print("initPreopen err: {}\n", .{e});
    //     return @errorToInt(e);
    // };

    const target_file = std.fs.cwd().openFile("/target.txt", .{}) catch |e| {
        std.debug.print("open /target.txt err: {}\n", .{e});
        return @errorToInt(e);
    };
    defer target_file.close();
    const file_len = @intCast(usize, (target_file.stat() catch |e| {
        std.debug.print("target.txt stat err: {}\n", .{e});
        return @errorToInt(e);
    }).size);

    target_buf = allocator.alloc(u8, file_len) catch |e| {
        std.debug.print("target_buf alloc err: {}\n", .{e});
        return @errorToInt(e);
    };

    _ = target_file.readAll(target_buf) catch |e| {
        std.debug.print("err: {}\n", .{e});
        return @errorToInt(e);
    };

    chibi.sexp_scheme_init();

    chibi_ctx = chibi.sexp_make_eval_context(null, null, null, 0, 0);

    if (chibi._sexp_exceptionp(
            chibi.sexp_load_standard_env(chibi_ctx, null, chibi.SEXP_SEVEN)
    ) != 0) {
        std.debug.print("exp_load_standard_env err", .{});
        return @errorToInt(error.ChibiLoadErr);
    }

    if (chibi._sexp_exceptionp(
            chibi.sexp_load_standard_ports(chibi_ctx, null, chibi.stdin, chibi.stdout, chibi.stdout, 1)
    ) != 0) {
        std.debug.print("exp_load_standard_env err", .{});
        return @errorToInt(error.ChibiLoadErr);
    }

    return 0;
}

export fn deinit() void {
    _ = chibi.sexp_destroy_context(chibi_ctx);
    preopens.deinit();
    allocator.free(target_buf);
}

// this blog demonstrates how I should implement usage of this function in the browser with wasmer
// https://mnt.io/2018/08/22/from-rust-to-beyond-the-webassembly-galaxy/
export fn eval_str(buf_ptr: [*]const u8, _buf_len: i32) void {
    const result = chibi.sexp_eval_string(chibi_ctx, buf_ptr, @intCast(c_int, _buf_len), null);
    chibi._sexp_debug(chibi_ctx, "", result);
}

// TODO: should probably handle stdin chunks the way that `main` does currently
export fn eval_stdin() u16 {
    var line_buff: [1024]u8 = undefined;
    const bytes_read = std.io.getStdIn().read(&line_buff) catch |e| return @errorToInt(e);
    const result = chibi.sexp_eval_string(chibi_ctx, &line_buff, @intCast(c_int, bytes_read), null);
    chibi._sexp_debug(chibi_ctx, "", result);
    return 0;
}


pub fn main() !void {
    const init_result = init();
    if (init_result != 0) {
        const init_err = @intToError(init_result);
        std.debug.print("caught init error: {}\n", .{init_err});
        return init_err;
    }

    defer deinit();

    // FIXME: temp loop
    while (true)
    {
        var line_buff: [1024]u8 = undefined;
        // TODO: use readline lib and also wait for parens to match
        // FIXME: temp emit non-wasi prompt
        _ = try std.io.getStdOut().write("> ");
        // need to read it all, not just by line!

        var total_bytes_read: usize = 0;
        {
            // HACK: temporary solution for multi-line input, doesn't handle quotes containing parentheses
            var lpar_count: usize = 0;
            var rpar_count: usize = 0;
            while (true) {
                const bytes_read = try std.io.getStdIn().read(line_buff[total_bytes_read..]);
                // NOTE: would be cool to scan these simultaneously, I wonder if the compiler will do that already
                lpar_count += std.mem.count(u8, line_buff[total_bytes_read..total_bytes_read + bytes_read], "(");
                rpar_count += std.mem.count(u8, line_buff[total_bytes_read..total_bytes_read + bytes_read], ")");
                total_bytes_read += bytes_read;
                if (lpar_count == rpar_count) break;
            }
        }

        // if (std.mem.eql(u8, "exit", line_buff[0..bytes_read]))
        //     break;
        eval_str(&line_buff, @intCast(i32, total_bytes_read));
    }
}
