//! web driver of sizr-lisp, a (completely chibi-scheme-based) scheme interpreter
//! with the sizr primitives built in

const std = @import("std");
const builtin = @import("builtin");
const bindings = @import("./bindings.zig");
const ts = @import("tree-sitter");

// TODO: create a package of chibi bindings
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

extern fn sexp_exec_query_stub(chibi.sexp, chibi.sexp, isize) chibi.sexp;
extern fn sexp_transform_ExecQueryResult_stub(chibi.sexp, chibi.sexp, isize) chibi.sexp;
extern fn sexp_matches_ExecQueryResult_stub(chibi.sexp, chibi.sexp, isize) chibi.sexp;
extern fn sexp_node_source_stub(chibi.sexp, chibi.sexp, isize) chibi.sexp;
extern fn sexp_ts_node_string_stub(chibi.sexp, chibi.sexp, isize) chibi.sexp;

fn loadSizrBindings(in_chibi_ctx: chibi.sexp) !void {
    const env = chibi._sexp_context_env(in_chibi_ctx);
    _ = chibi._sexp_define_foreign(in_chibi_ctx, env, "exec_query", 2, sexp_exec_query_stub);
    _ = chibi._sexp_define_foreign(in_chibi_ctx, env, "transform_ExecQueryResult", 2, sexp_transform_ExecQueryResult_stub);
    _ = chibi._sexp_define_foreign(in_chibi_ctx, env, "matches_ExecQueryResult", 1, sexp_matches_ExecQueryResult_stub);
    _ = chibi._sexp_define_foreign(in_chibi_ctx, env, "node_source", 2, sexp_node_source_stub);
    _ = chibi._sexp_define_foreign(in_chibi_ctx, env, "ts_node_string", 1, sexp_ts_node_string_stub);
}

export fn init() u16 {
    const chibi_transform_funcs = @import("./chibi_transform.zig");
    _ = chibi_transform_funcs;

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

    chibi.sexp_scheme_init();

    chibi_ctx = chibi.sexp_make_eval_context(null, null, null, 0, 0);

    if (chibi._sexp_exceptionp(
            chibi.sexp_load_standard_env(chibi_ctx, null, chibi.SEXP_SEVEN)
    ) != 0) {
        std.debug.print("sexp_load_standard_env err\n", .{});
        return @errorToInt(error.ChibiLoadErr);
    }

    if (chibi._sexp_exceptionp(
            chibi.sexp_load_standard_ports(chibi_ctx, null, chibi.stdin, chibi.stdout, chibi.stdout, 1)
    ) != 0) {
        std.debug.print("sexp_load_standard_ports err\n", .{});
        return @errorToInt(error.ChibiLoadErr);
    }

    load_cpp();

    loadSizrBindings(chibi_ctx) catch |e| {
        return @errorToInt(e);
    };

    return 0;
}

export fn deinit() void {
    _ = chibi.sexp_destroy_context(chibi_ctx);
    preopens.deinit();
}

fn print_chibi_value(val: chibi.sexp) void {
    if (chibi.SEXP_VOID == val) {
        // do nothing
    } else if (chibi._sexp_exceptionp(val) != 0) {
        chibi._sexp_print_exception(chibi_ctx, val, chibi._sexp_current_error_port(chibi_ctx));
        chibi._sexp_write_char(chibi_ctx, '\n', chibi._sexp_current_error_port(chibi_ctx));
        chibi._sexp_flush(chibi_ctx, chibi._sexp_current_error_port(chibi_ctx));
    } else {
        chibi._sexp_write(chibi_ctx, val, chibi._sexp_current_output_port(chibi_ctx));
        chibi._sexp_write_char(chibi_ctx, '\n', chibi._sexp_current_output_port(chibi_ctx));
        chibi._sexp_flush(chibi_ctx, chibi._sexp_current_output_port(chibi_ctx));
    }
}


// TODO: remove...
// this blog demonstrates how I should implement usage of this function in the browser with wasmer
// https://mnt.io/2018/08/22/from-rust-to-beyond-the-webassembly-galaxy/
export fn eval_str(buf_ptr: [*]const u8, _buf_len: i32) void {
    const result = chibi.sexp_eval_string(chibi_ctx, buf_ptr, @intCast(c_int, _buf_len), null);
    print_chibi_value(result);
}

// TODO: should probably handle stdin chunks the way that `main` does currently
export fn eval_stdin() u16 {
    var line_buff: [1024]u8 = undefined;
    const bytes_read = std.io.getStdIn().read(&line_buff) catch |e| return @errorToInt(e);
    const result = chibi.sexp_eval_string(chibi_ctx, &line_buff, @intCast(c_int, bytes_read), null);
    // see chibi-scheme's main.c#repl
    print_chibi_value(result);
    return 0;
}

pub fn interpretProgramSources(srcs: []const []const u8) !void {
    // TODO: implement streaming read (mmap on posix)
    for (srcs) |src| {
        const file = @import("./FileBuffer.zig").fromDirAndPath(allocator, std.fs.cwd(), src);
        // FIXME: use new context for each file
        const result = chibi.sexp_eval_string(chibi_ctx, file.buffer.ptr, @intCast(c_int, file.buffer.len), null);
        const is_excep = chibi._sexp_exceptionp(result) != 0;
        if (is_excep) {
            print_chibi_value(result);
            return error.SchemeProgramException;
        }
    }
}

// TODO: add full execution of files in command line arguments, also support reading from
// piped stdin
pub fn main() !void {
    const init_result = init();
    if (init_result != 0) {
        const init_err = @intToError(init_result);
        std.debug.print("caught init error: {}\n", .{init_err});
        return init_err;
    }

    defer deinit();

    const args = std.process.argsAlloc(allocator) catch |e| {
        std.debug.print("proc arg alloc err: {}\n", .{e});
        return @errorToInt(e);
    };
    defer std.process.argsFree(allocator, args);

    if (args.len > 1)
        return interpretProgramSources(args[1..]);

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

        const line = line_buff[0..total_bytes_read];

        if (std.mem.eql(u8, "exit", line)) {
            break;
        } else {
            eval_str(&line_buff, @intCast(i32, total_bytes_read));
        }
    }
}
