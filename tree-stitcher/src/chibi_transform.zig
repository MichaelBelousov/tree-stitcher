const std = @import("std");
const builtin = @import("builtin");
const bindings = @import("./bindings.zig");
const ts = @import("tree-sitter");
const chibi = @cImport({ @cInclude("./chibi_macros.h"); });

fn _sexp_prepend(ctx: chibi.sexp, list: *chibi.sexp, exp: chibi.sexp) void {
    // ZIGBUG: possible zig translate-c bug when using just sexp_push
    _ = chibi.sexp_push_op(ctx, list, chibi.SEXP_VOID);
    chibi._set_sexp_car(list.*, exp);
}

const NodeToAstImpl = struct {
    fn node_to_ast_impl(
        ctx: chibi.sexp,
        cursor: *ts.TreeCursor,
        parse_ctx: *const bindings.ExecQueryResult,
        field_replacements: std.StringArrayHashMap(chibi.sexp),
    ) chibi.sexp {
        //const env = chibi._sexp_context_env(ctx);

        var sexp_stack = std.SegmentedList(chibi.sexp, 64){};
        defer sexp_stack.deinit(std.heap.c_allocator);
        var top = sexp_stack.addOne(std.heap.c_allocator) catch unreachable;
        top.* = chibi.SEXP_NULL;

        // TODO: move to internal state of NodeToAstImpl?
        const state = struct {
            cursor: *ts.TreeCursor,
            top: **chibi.sexp,
            sexp_stack: *std.SegmentedList(chibi.sexp, 64),
            ctx: chibi.sexp,

            pub fn print_moved(self: @This(), moved_to_label: []const u8) void {
                const maybe_node_type = self._cursor.current_node().@"type"();
                std.debug.print("moved to {s} '{s}'\n", .{
                    moved_to_label,
                    if (maybe_node_type) |node_type| node_type else "UNKNOWN"
                });
            }

            pub fn popMergeUp(self: @This()) void {
                // FIXME: why do we need const if nreverse?
                var old_top = self.sexp_stack.pop();
                // FIXME: expensive check of end! (maybe double pop and repush instead?)
                // (or use a different stack data structure)
                // FIXME ugly double pointers... just initialize it in the state
                self.top.* = self.sexp_stack.uncheckedAt(self.sexp_stack.count() - 1);
                old_top = chibi._sexp_nreverse(self.ctx, old_top.?);
                _sexp_prepend(self.ctx, self.top.*, old_top.?);
            }

            pub fn pushEmpty(self: @This()) void {
                var next = self.sexp_stack.addOne(std.heap.c_allocator) catch unreachable;
                next.* = chibi.SEXP_NULL;
                self.top.* = next;
            }

            const CursorGotoResult = struct {
                did_move: bool,
                was_named: bool,
                is_named: bool,
            };

            pub fn goto_parent(self: @This()) ?CursorGotoResult {
                const was_named = self.cursor.current_node().is_named();
                const did_move = self.cursor.goto_parent();
                const is_named = if (did_move) self.cursor.current_node().is_named() else was_named;
                return if (!did_move) null
                    else .{ .was_named = was_named, .did_move = did_move, .is_named = is_named };
            }

            pub fn goto_next_sibling(self: @This()) ?CursorGotoResult {
                const was_named = self.cursor.current_node().is_named();
                const did_move = self.cursor.goto_next_sibling();
                const is_named = if (did_move) self.cursor.current_node().is_named() else was_named;
                return if (!did_move) null
                    else .{ .was_named = was_named, .did_move = did_move, .is_named = is_named };
            }

            pub fn goto_first_child(self: @This()) ?CursorGotoResult {
                const was_named = self.cursor.current_node().is_named();
                const did_move = self.cursor.goto_first_child();
                const is_named = if (did_move) self.cursor.current_node().is_named() else was_named;
                return if (!did_move) null
                    else .{ .was_named = was_named, .did_move = did_move, .is_named = is_named };
            }
        }{
            .cursor = cursor,
            .top = &top,
            .sexp_stack = &sexp_stack,
            .ctx = ctx,
        };

        // FIXME?: handle anonymous root node

        outer: while (true) {
            if (cursor.current_node().is_null())
                @panic("current node was null, not possible with tree cursor");

            // TODO:
            // if (cursor.current_node().is_missing())

            // FIXME: instead of a string map, use the language to store in the field map the TSSymbol
            // for faster lookups
            const curr_field_name = cursor.current_field_name();
            const in_child_of_root = sexp_stack.count() == 2;
            const maybe_replacement =
                if (in_child_of_root and curr_field_name != null)
                    field_replacements.get(curr_field_name.?)
                else null;
            if (maybe_replacement) |replacement| {
                if (std.os.getenv("DEBUG") != null) {
                    std.debug.print("replacing field '{s}' with:\n", .{curr_field_name.?});
                    chibi._sexp_debug(ctx, "", replacement);
                    const node_str = cursor.current_node().string();
                    defer node_str.free();
                    std.debug.print("otherwise would be '{s}'\n", .{node_str.ptr});
                    std.debug.print("source is '{s}'\n", .{cursor.current_node().in_source(parse_ctx.buff)});
                }
                top.* = chibi._sexp_append2(ctx, chibi._sexp_reverse(ctx, replacement), top.*);

            } else {
                if (cursor.current_node().is_named()) {
                    // ZIGBUG?: why isn't this an implicit conversion?
                    const node_type = cursor.current_node().@"type"().?;
                    const sym = chibi.sexp_intern(ctx, node_type.ptr, @intCast(c_long, node_type.len));
                    _sexp_prepend(ctx, top, sym);
                }

                if (state.goto_first_child()) |goto_result| {
                    if (goto_result.is_named) state.pushEmpty();
                    continue;
                } else {
                    const slice = cursor.current_node().in_source(parse_ctx.buff);
                    const str = chibi.sexp_c_string(ctx, slice.ptr, @intCast(c_long, slice.len));
                    _sexp_prepend(ctx, top, str);
                }
            }

            while (true) {
                if (state.goto_next_sibling()) |goto_result| {
                    if (goto_result.was_named) state.popMergeUp();
                    if (goto_result.is_named) state.pushEmpty();
                    break;
                }
                if (state.goto_parent()) |goto_result| {
                    if (goto_result.was_named) state.popMergeUp();
                } else break :outer;
            }
        }

        // FIXME: why do we need var if nreverse
        var ast = sexp_stack.pop().?;
        ast = chibi._sexp_nreverse(ctx, ast);
        return ast;
    }

    // NOTE: not sure I need this thunk anymore since there is no longer recursion in the impl
    // ZIGBUG even with pub on the struct, this doesn't make it into the bundled library when marked `export`
    fn node_to_ast(
        ctx: chibi.sexp,
        in_node: ts._c.TSNode,
        parse_ctx: *const bindings.ExecQueryResult,
        field_replacements: std.StringArrayHashMap(chibi.sexp),
    ) chibi.sexp {
        const node = ts.Node{._c = in_node};
        var cursor = ts.TreeCursor.new(node);
        defer cursor.free();
        const ast = node_to_ast_impl(ctx, &cursor, parse_ctx, field_replacements);
        return ast;
    }
};

// ZIGBUG: crash if exported?
fn node_to_ast(
    ctx: chibi.sexp,
    in_node: ts._c.TSNode,
    parse_ctx: *const bindings.ExecQueryResult,
    field_replacements: std.StringArrayHashMap(chibi.sexp),
) chibi.sexp {
    return NodeToAstImpl.node_to_ast(ctx, in_node, parse_ctx, field_replacements);
}

const none: chibi.sexp = null;

fn Result(comptime Ok: type, comptime Err: type) type {
    return union (enum) { err: Err, ok: Ok };
}

const MatchTransformer = struct {
    query_ctx: *bindings.ExecQueryResult,
    ctx: chibi.sexp,
    transform: chibi.sexp,

    env: chibi.sexp,
    sexp_self: chibi.sexp, // for exceptions

    const Error = union (enum) {
        badCapture: []const u8,
        badField: []const u8,
        fieldAfterNonField: void,
        fieldWithoutReplacement: []const u8,

        fn format(self: @This(), alloc: std.mem.Allocator) []const u8 {
            return switch (self) {
                .badCapture => |name| std.fmt.allocPrint(alloc, "capture '{s}' not in query", .{name}) catch unreachable,
                .badField => |name| std.fmt.allocPrint(alloc, "field '{s}' not on that node", .{name}) catch unreachable,
                .fieldAfterNonField => "fields may not follow non-fields",
                .fieldWithoutReplacement => |name| std.fmt.allocPrint(alloc, "field '{s}' in transform was not followed by its replacement", .{name}) catch unreachable,
            };
        }
    };

    const TransformResult = Result(chibi.sexp, Error);


    fn new(query_ctx: *bindings.ExecQueryResult, ctx: chibi.sexp, transform: chibi.sexp) @This() {
        const env = chibi._sexp_context_env(ctx);
        const sexp_self = chibi.sexp_env_ref(
            ctx, env,
            chibi.sexp_intern(ctx, "transform_ExecQueryResult", -1), none
        );
        if (sexp_self == none) @panic("could not find owning function bindings in environment");

        return @This(){
            .query_ctx = query_ctx,
            .ctx = ctx,
            .transform = transform,
            .env = env,
            .sexp_self = sexp_self,
        };
    }

    pub fn transform_match(
        query_ctx: *bindings.ExecQueryResult,
        chibi_ctx: chibi.sexp,
        match: ts._c.TSQueryMatch,
        transform: chibi.sexp,
    ) TransformResult {
        // TODO: document better that we always add a root capture to the end of the query
        const root_node = ts.Node{._c = match.captures[match.capture_count - 1].node};
        const result = MatchTransformer
            .new(query_ctx, chibi_ctx, transform)
            .transform_match_impl(match, transform, root_node, false);
        return result;
    }

    /// Given "match", a query matching context, a "transform" s-exp, and a root node, "node"
    /// - traverse the transform and each time we find an s-exp list starting with a `@capture`,
    ///   skip its subtree replace it with:
    ///   - the extended tree-sitter s-exp representation (defined by node_to_ast above)
    ///     of that capture's node in the match, except
    ///   - read through the "arguments" of the caller (list elements following that first one)
    ///     - if they are a `field:` identifier, replace that field's representation in the caller's expansion
    ///       with transform_match_impl(match, sibling_after_field:_in_transform, field_node)
    ///       // FIXME: field order could matter, should be illegal to have a non-field before a field
    ///     - otherwise append to the caller's expansion:
    ///       transform_match_impl(match_ctx, the_non_field_transform_subexpr, node)
    fn transform_match_impl(
        self: @This(),
        match: ts._c.TSQueryMatch,
        transform_expr: chibi.sexp,
        node: ts.Node,
        in_ast_expansion: bool,
    ) TransformResult {
        if (chibi._sexp_pairp(transform_expr) == 0)
            return TransformResult{.ok = transform_expr};

        const car = chibi._sexp_car(transform_expr);
        const list_starts_with_symbol = chibi._sexp_symbolp(car) != 0; 

        if (list_starts_with_symbol) {
            // TODO: add util func for this
            const symbol_str = chibi._sexp_string_data(chibi._sexp_symbol_to_string(self.ctx, car));
            const symbol_slice = symbol_str[0..std.mem.len(symbol_str)];
            // TODO: check if in map instead of assume and fail
            const list_starts_with_capture_ref = std.mem.startsWith(u8, symbol_slice, "@");

            if (list_starts_with_capture_ref) {
                // FIXME: the capture order is in captured node source order, so this naive analysis is probably wrong
                const capture_index = match.capture_count - 1 - (
                    self.query_ctx.capture_name_to_index.get(symbol_slice)
                    // NOTE: error references memory owned by the scheme context
                    orelse return TransformResult{.err = Error{.badCapture = symbol_slice}}
                  );

                const capture = match.captures[capture_index];

                // FIXME: shouldn't the query context also use a StringArrayHashMap?
                var fields = std.StringArrayHashMap(chibi.sexp).init(std.heap.c_allocator);
                defer fields.deinit();
                // go through children, determining fields
                var child_list = chibi._sexp_cdr(transform_expr);
                var done_with_fields = false;
                var to_append_list = std.SegmentedList(chibi.sexp, 16){};
                defer to_append_list.deinit(std.heap.c_allocator);
                while (chibi._sexp_nullp(child_list) == 0) : (child_list = chibi._sexp_cdr(child_list)) {
                    const child = chibi._sexp_car(child_list);
                    const is_symbol = chibi._sexp_symbolp(child) != 0;

                    if (is_symbol) {
                        const child_symbol_str = chibi._sexp_string_data(chibi._sexp_symbol_to_string(self.ctx, child));
                        const child_symbol_slice = child_symbol_str[0..std.mem.len(child_symbol_str)];
                        const is_field_ref = std.mem.endsWith(u8, child_symbol_slice, ":");
                        if (is_field_ref) {
                            if (done_with_fields) return TransformResult{.err=.fieldAfterNonField};
                    
                            child_list = chibi._sexp_cdr(child_list);
                            const field_name = child_symbol_slice[0..child_symbol_slice.len - 1];
                            if (chibi._sexp_nullp(child_list) != 0)
                                return TransformResult{.err=Error{.fieldWithoutReplacement=field_name}};
                            const field_replacement = chibi._sexp_car(child_list);
                            // FIXME: error handling
                            const field_node = node.child_by_field_name(field_name)
                                orelse return TransformResult{.err=Error{.badField=field_name}};
                            const transformed_field_replacement = switch (
                                self.transform_match_impl(match, field_replacement, field_node, true)
                            ) {
                                .err => |err| return TransformResult{.err = err},
                                .ok => |val| val,
                            };
                            fields.put(field_name, transformed_field_replacement)
                                catch @panic("put field failed");
                            continue;
                        }
                    } else {
                        done_with_fields = true;
                        const to_append = to_append_list.addOne(std.heap.c_allocator) catch unreachable;
                        // FIXME: returning a symbol won't work here...
                        to_append.* = switch(self.transform_match_impl(match, child, node, true)) {
                            .err => |err| return TransformResult{.err = err},
                            .ok => |val| val,
                        };
                    }
                }

                var ast = node_to_ast(self.ctx, capture.node, self.query_ctx, fields);

                var to_append_iter = to_append_list.constIterator(0);
                while (to_append_iter.next()) |to_append| {
                    ast = chibi._sexp_append2(
                        self.ctx, ast,
                        chibi._sexp_cons(self.ctx, to_append.*, chibi.SEXP_NULL)
                    );
                }

                // TODO: remove
                // FIXME: maybe I can just replace all quoting with implementing the tree-sitter
                // nodes as forms in the lang namespace
                //_ = in_ast_expansion;

                return TransformResult{.ok=ast};
            }
        }

        // not a list starting with a capture
        const new_car = switch (self.transform_match_impl(match, car, node, in_ast_expansion)) {
            .err => |e| return TransformResult{.err = e},
            .ok => |val| val,
        };
        const cdr = chibi._sexp_cdr(transform_expr);
        const cdr_not_null = chibi._sexp_nullp(cdr) == 0;
        const new_cdr =
            // FIXME: is there a better way to do this?
            if (cdr_not_null) switch (self.transform_match_impl(match, cdr, node, in_ast_expansion)) {
                .err => |e| return TransformResult{.err=e},
                .ok => |val| val,
            }
            else chibi.SEXP_NULL;

        return TransformResult{.ok = chibi._sexp_cons(self.ctx, new_car, new_cdr)};
    }
};

// FIXME: completely ignoring the garbage collector all over the place... going to be bad
export fn transform_ExecQueryResult(query_ctx: *bindings.ExecQueryResult, transform: chibi.sexp, ctx: chibi.sexp) chibi.sexp {
    const env = chibi._sexp_context_env(ctx);
    var chunks = std.SegmentedList([]const u8, 64){};
    defer chunks.deinit(std.heap.c_allocator);

    const sexp_self = chibi.sexp_env_ref(
        ctx, env,
        chibi.sexp_intern(ctx, "transform_ExecQueryResult", -1), none
    );
    if (sexp_self == none)
        @panic("could not find owning function bindings in environment");

    const match_count = std.mem.len(query_ctx.matches);
    var i: usize = 0;
    for (query_ctx.matches[0..match_count]) |maybe_match| {
        if (maybe_match) |match| {
            const outer_capture = match.captures[0];
            const start = ts._c.ts_node_start_byte(outer_capture.node);
            const end = ts._c.ts_node_end_byte(outer_capture.node);
            chunks.append(std.heap.c_allocator, query_ctx.buff[i..start]) catch |err| {
                std.log.err("Error allocating output chunk: {any}\n", .{err});
                return null;
            };
            i = end;

            const transformed_ast = switch(MatchTransformer.transform_match(query_ctx, ctx, match.*, transform)) {
                .ok => |v| v,
                // FIXME: need a finalizer for this allocated memory
                .err => |e| return chibi.sexp_user_exception(
                    ctx, sexp_self, e.format(std.heap.c_allocator).ptr, transform),
            };

            // if I do it this way, then @capture must be a function that merges its arguments into
            // its value, which is basically what I already have in lisp with make-complex-node, no?
            // but it also must use node_to_ast to produce the stringified ast...
            // {
            //     const transform_ctx = chibi.sexp_make_eval_context(ctx, null, null, 0, 0);
            //     // FIXME: destroying this derived context destroys the parent? maybe because
            //     // the stack and env are null?
            //     //defer _ = chibi.sexp_destroy_context(transform_ctx);
            //     var capture_iter = query_ctx.capture_name_to_index.iterator();
            //     while (capture_iter.next()) |capture| {
            //         const name = std.heap.c_allocator.alloc(u8, capture.key_ptr.*.len + 1)
            //             catch @panic("couldn't allocate capture name");
            //         const capture_index = capture.value_ptr.*;
            //         defer std.heap.c_allocator.free(name);
            //         const node = ts.Node.from_c(match.captures[capture_index].node);
            //         const node_str = node.string();
            //         defer node_str.free();
            //         const result = chibi.sexp_eval_string(ctx, node_str.ptr, -1, null);
            //         const symbol = chibi.sexp_intern(ctx, name.ptr, @intCast(c_long, name.len));
            //         _ = chibi.sexp_env_define(transform_ctx, env, symbol, result);
            //     }

            //     const test_result = chibi._sexp_eval(transform_ctx, transformed_ast, null);
            //     chibi._sexp_debug(ctx, "test eval:", test_result);
            // }

            if (std.os.getenv("DEBUG") != null)
                chibi._sexp_debug(ctx, "before eval:", transformed_ast);

            // FIXME: eval doesn't portably operate on procedures, but on symbols, so may need to
            // quote the ast or something
            var transform_result = chibi._sexp_eval(ctx, transformed_ast, null);

            if (std.os.getenv("DEBUG") != null)
                chibi._sexp_debug(ctx, "after eval:", transformed_ast);

            if (chibi._sexp_exceptionp(transform_result) != 0)
                return transform_result;

            // TODO: type check it's not a list
            if (chibi._sexp_stringp(transform_result) == 0) {
                const ast_to_string = chibi.sexp_intern(ctx, "ast->string", -1);
                transform_result = chibi._sexp_list2(ctx, ast_to_string, transform_result);
                transform_result = chibi._sexp_eval(ctx, transform_result, null);
                if (std.os.getenv("DEBUG") != null)
                    chibi._sexp_debug(ctx, "after stringify:", transform_result);
            }

            if (chibi._sexp_exceptionp(transform_result) != 0)
                return transform_result;

            // FIXME: when is transform_result garbage collected? need to valgrind...
            const transform_as_str = chibi._sexp_string_data(transform_result);
            const transform_as_str_len = chibi._sexp_string_size(transform_result);
            chunks.append(std.heap.c_allocator, transform_as_str[0..transform_as_str_len]) catch {
                return chibi.sexp_user_exception(ctx, sexp_self, "error allocating output chunk", transform);
            };
        }
    }

    // NOTE: can avoid appending this one...
    chunks.append(std.heap.c_allocator, query_ctx.buff[i..]) catch {
        return chibi.sexp_user_exception(ctx, sexp_self, "error allocating last chunk", transform);
    };

    // TODO: wrap chunks.append so this is recorded everytime we push instead of at the end in another pass here
    const chunks_aggregate_len = _: {
        var chunk_iter = chunks.constIterator(0);
        var result: usize = 0;
        while (chunk_iter.next()) |chunk| {
            result += chunk.len;
        }
        break :_ result;
    };

    var result_buffer = std.heap.c_allocator.allocSentinel(u8, chunks_aggregate_len, 0) catch {
        return chibi.sexp_user_exception(ctx, sexp_self, "error allocating aggregate buffer", transform);
    };

    {
        var chunk_iter = chunks.constIterator(0);
        var byte_pos: usize = 0;
        while (chunk_iter.next()) |chunk| {
            std.mem.copy(u8, result_buffer[byte_pos..byte_pos+chunk.len], chunk.*);
            byte_pos += chunk.len;
        }
    }
    
    // TODO: use @fieldParentPtr to finalize the result
    const string_result = chibi.sexp_c_string(ctx, result_buffer.ptr, @intCast(c_long, result_buffer.len));
    return string_result;
}

