// TODO: rename to exec_query or something

const std = @import("std");
const ts = @import("tree-sitter");
const FileBuffer = @import("./FileBuffer.zig");

pub const ExecQueryResult = struct {
    parse_tree: ts.Tree,
    query_match_iter: ts.QueryMatchesIterator,
    matches: [*:null]?*const ts._c.TSQueryMatch,
    buff: []const u8,
    // FIXME: use StringArrayHashMap?
    /// map of captures to their index within capture list,
    /// which is also their depth first traversal order
    capture_name_to_index: std.StringHashMap(u32),
};

test "check deinit capture_name_to_index" {
    var str_map = std.StringHashMap(u32).init(std.testing.allocator);
    defer str_map.deinit();
    try str_map.put("test", 50);
    try std.testing.expectEqual(str_map.get("test").?, 50);
}

/// free a malloc'ed ExecQueryResult
export fn free_ExecQueryResult(r: *ExecQueryResult) void {
    r.capture_name_to_index.deinit();
    r.parse_tree.delete();
    r.query_match_iter.free();
    const match_count = std.mem.len(r.matches);
    for (r.matches[0..match_count]) |maybe_match| {
        if (maybe_match) |match| std.heap.c_allocator.destroy(match);
    }
    // NOTE: maybe should use actual std.c.free (and malloc)?
    std.heap.c_allocator.destroy(r);

    const munmap_result = std.c.getErrno(std.c.munmap(@alignCast(std.mem.page_size, r.buff.ptr), r.buff.len));
    if (munmap_result != .SUCCESS)
        std.log.err("munmap errno: {any}", .{ munmap_result });
}

export fn matches_ExecQueryResult(r: *ExecQueryResult) [*:null]?*const ts._c.TSQueryMatch {
    return r.matches;
}

/// Caller is responsible for std.c.free'ing the result
export fn node_source(_node: ts._c.TSNode, ctx: *const ExecQueryResult) [*c]const u8 {
    const node = ts.Node { ._c = _node };
    const source = node.in_source(ctx.buff);
    const result = std.heap.c_allocator.allocSentinel(u8, source.len, 0) catch |err| {
        std.debug.print("node_source allocSentinel err {any}", .{err});
        return null;
    };
    std.mem.copy(u8, result[0..source.len], source);
    // confusing...
    return @as([*:0]const u8, result);
}

const chibi = @cImport({ @cInclude("./chibi_macros.h"); });

fn query_to_str(ctx: chibi.sexp, query: chibi.sexp) []u8 {
    var str_port = chibi.sexp_open_output_string(ctx);
    chibi.sexp_write(ctx, query, str_port);
    return chibi.sexp_get_output_string(ctx, str_port);
    //var str = std.heap.c_allocator.alloc(u8, n) catch unreachable;
}

/// populates the query_ctx with analysis from the query, like capture indices
fn analyzeQuery(
    ctx: chibi.sexp,
    query: chibi.sexp,
    query_ctx: *ExecQueryResult
) void  {
    //var result = std.heap.c_allocator.create(ExecQueryResult) catch unreachable;
    query_ctx.capture_name_to_index = std.StringHashMap(u32).init(std.heap.c_allocator);

    const Impl = struct {
        ctx: chibi.sexp,
        query_ctx: *ExecQueryResult,
        i: u32,

        fn impl(self: *@This(), expr: chibi.sexp) void {
            if (chibi._sexp_symbolp(expr) != 0) {
                const symbol_str = chibi._sexp_string_data(chibi._sexp_symbol_to_string(self.ctx, expr));
                const symbol_slice = symbol_str[0..std.mem.len(symbol_str)];
                if (std.mem.startsWith(u8, symbol_slice, "@")) {
                    self.query_ctx.capture_name_to_index.put(symbol_slice, self.i) catch unreachable;
                    self.i += 1;
                }
            }
            if (chibi._sexp_pairp(expr) == 0) return;
            self.impl(chibi._sexp_car(expr));
            self.impl(chibi._sexp_cdr(expr));
        }
    };
    //const str = query_to_str(ctx, query);
    (Impl{.ctx = ctx, .query_ctx = query_ctx, .i = 0}).impl(query);
}

// NOTE: this of course doesn't work if someone does something like `(define my@thing 2)`, and we should use
// real traversal as implemented above, just need to figure out how to best decouple the string based query API
// and the chibi-scheme specific stuff
fn captureIndicesFromQueryStr(query: []const u8, map: *std.StringHashMap(u32)) void {
    var capture_index: u32 = 0;
    var i: usize = 0;
    var capture_start_index: usize = undefined;
    var state: enum { InCapture, Out } = .Out;
    for (query) |c| {
        switch (state) {
            .InCapture => {
                if (std.ascii.isWhitespace(c) or c == '(' or c == ')') {
                    const capture_text = query[capture_start_index..i];
                    map.put(capture_text, capture_index) catch unreachable;
                    capture_index += 1;
                    state = .Out;
                }
            },
            .Out => if (c == '@') {
                capture_start_index = i;
                state = .InCapture;
            }
        }
        i += 1;
    }
}

pub const Workspace = extern struct {
    // context
    files: [][]const u8,
};

var _active_language: ?*const fn() *ts.c_api.TSLanguage = null;

pub fn set_language(in_language: ?*const fn() *ts.c_api.TSLanguage) void {
    if (in_language) |lang| {
        _active_language = lang;
    } else {
        std.debug.print("tried to set null language", .{});
    }
}

/// Caller must use libc free to free each object pointed to by the returned list,
/// as well as the returned list itself
export fn exec_query(
    in_query: [*:0]const u8,
    srcs: [*c][*:0]const u8
) ?*ExecQueryResult {
    const query_len = std.mem.len(in_query);
    const query = in_query[0..query_len];

    // FIXME: replace these catches
    var result = std.heap.c_allocator.create(ExecQueryResult) catch unreachable;

    result.capture_name_to_index = std.StringHashMap(u32).init(std.heap.c_allocator);
    captureIndicesFromQueryStr(query, &result.capture_name_to_index);

    const path_len = std.mem.len(srcs[0]);
    // FIXME: don't use realpath, just some path join operation
    const abs_path = std.fs.cwd().realpathAlloc(std.heap.c_allocator, srcs[0][0..path_len]) catch |err| {
      std.debug.print("error '{}' realpath-ing file: '{s}'\n", .{err, srcs[0]});
      const cwd = std.fs.cwd().realpathAlloc(std.heap.c_allocator, ".") catch return null;
      defer std.heap.c_allocator.free(cwd);
      std.debug.print("was in cwd: '{s}'\n", .{cwd});
      return null;
    };
    defer std.heap.c_allocator.free(abs_path);

    var file = FileBuffer.from_path(std.heap.c_allocator, abs_path) catch |err| {
      std.debug.print("error '{any}' opening file: '{s}'\n", .{err, srcs[0]});
      return null;
    };

    result.buff = file.buffer;

    const parser = ts.Parser.new();
    defer parser.free();


    const language =
        if (_active_language) |lang| ts.Language{._c = lang()}
        else {
            // FIXME: error handling
            std.debug.print("_active_language was null", .{});
            @panic("_active_language was null");
        };

    if (!parser.set_language(language))
        @panic("couldn't set lang");

    result.parse_tree = parser.parse_string(null, result.buff);
    const root = result.parse_tree.root_node();
    const syntax_tree_str = root.string();
    defer syntax_tree_str.free();

    result.query_match_iter = root.exec_query(query) catch unreachable;

    var list = std.SegmentedList(*ts._c.TSQueryMatch, 16){};
    defer list.deinit(std.heap.c_allocator);

    while (result.query_match_iter.next()) |match| {
        const match_slot = std.heap.c_allocator.create(ts._c.TSQueryMatch) catch unreachable;
        match_slot.* = match._c;

        // LEAK? working around that tree-sitter seems to reuse the capture pointer of returned matches when you
        // call next again... but will tree-sitter free it correctly later?
        const newCaptures = std.heap.c_allocator.alloc(ts._c.TSQueryCapture, match._c.capture_count) catch unreachable;
        std.mem.copy(
            ts._c.TSQueryCapture,
            newCaptures[0..match._c.capture_count],
            match._c.captures[0..match._c.capture_count]
        );
        match_slot.captures = @as([*c]ts._c.TSQueryCapture, &newCaptures[0]);

        list.append(std.heap.c_allocator, match_slot) catch unreachable;
    }

    result.matches = std.heap.c_allocator.allocSentinel(?*ts._c.TSQueryMatch, list.len, null) catch |err| {
        std.debug.print("allocSentinel err {any}", .{err});
        return null;
    };
    var list_iter = list.iterator(0);

    var i: usize = 0;
    while (list_iter.next()) |val| {
        result.matches[i] = val.*;
        i += 1;
    }

    return result;
}

