//! TODO: doing this by hand for now but some kind of clang plugin could probably generate bindings better
//! alternatively, tree-sitter queries themselves or even sizr-format could potentially generate this

const std = @import("std");

pub const c_api = @cImport({
    @cInclude("tree_sitter/api.h");
});

// TODO: prefer c_api, make this non-pub
/// deprecated
pub const _c = c_api;

pub const InputEncoding = enum(c_api.TSInputEncoding) {
    utf8 = c_api.TSInputEncodingUTF8,
    utf16 = c_api.TSInputEncodingUTF16,
};

// TODO: remove Ts prefix from all types since user can namespace it themselves
pub const Parser = struct {
    _c: *c_api.TSParser,

    const Self = @This();

    pub fn new() Self {
        return Self{ ._c = c_api.ts_parser_new().? };
    }

    // TODO: check zig idioms
    pub fn free(self: Self) void {
        c_api.ts_parser_delete(self._c);
    }

    pub fn set_language(self: Self, language: Language) bool {
        return c_api.ts_parser_set_language(self._c, language._c);
    }

    // TODO: steal the documentation from the C header
    // would be nice if this could be done with reflection
    pub fn parse_string(self: Self, old_tree: ?Tree, src_string: []const u8) Tree {
        // FIXME: I actually have no idea what the input encoding is when unspecified
        return self.parse_string_encoding(old_tree, src_string, InputEncoding.utf8);
    }

    pub fn parse_string_encoding(self: Self, old_tree: ?Tree, src_string: []const u8, encoding: InputEncoding) Tree {
        return Tree{
            ._c = c_api.ts_parser_parse_string_encoding(
                self._c,
                if (old_tree) |old_tree_val| old_tree_val._c else null,
                src_string.ptr,
                @truncate(u32, src_string.len),
                @enumToInt(encoding)
            ).?
        };
    }
};

test "Parser" {
    var parser = Parser.new();
    defer {
        parser.free();
    }
}

pub const Node = struct {
    _c: c_api.TSNode,

    // TODO: maybe wrap all ts.Node usage in optionals and hide the concept of the invalid raw c struct?
    // or just use another zig tree-sitter binding
    pub fn from_c(c: c_api.TSNode) @This() {
        return @This(){ ._c = c };
    }

    // TODO: maybe wrap all ts.Node usage in optionals and hide the concept of the invalid raw c struct?
    // or just use another zig tree-sitter binding
    pub fn is_null(self: @This()) bool {
        return c_api.ts_node_is_null(self._c);
    }

    pub fn @"type"(self: @This()) ?[]const u8 {
        if (self.is_null()) return null;
        const raw = c_api.ts_node_type(self._c);
        return if (raw == null) null else std.mem.span(raw);
    }

    pub fn is_named(self: @This()) bool {
        return c_api.ts_node_is_named(self._c);
    }

    pub fn is_missing(self: @This()) bool {
        return c_api.ts_node_is_missing(self._c);
    }

    pub fn is_extra(self: @This()) bool {
        return c_api.ts_node_is_extra(self._c);
    }

    pub fn has_changes(self: @This()) bool {
        return c_api.ts_node_has_changes(self._c);
    }

    pub fn has_error(self: @This()) bool {
        return c_api.ts_node_has_error(self._c);
    }

    pub fn child_by_field_name(self: @This(), field_name: []const u8) ?Node {
        if (self.is_null()) return null;
        return Node {._c = c_api.ts_node_child_by_field_name(self._c, field_name.ptr, @truncate(u32, field_name.len)) };
    }

    pub fn child(self: @This(), index: u32) Node {
        return Node{ ._c = c_api.ts_node_child(self._c, index) };
    }

    pub fn field_name_for_child(self: @This(), index: u32) ?[]const u8 {
        const raw = c_api.ts_node_field_name_for_child(self._c, index);
        return if (raw == null) null else std.mem.span(raw);
    }

    pub const FreeableCStr = struct {
        ptr: [*c]u8,
        pub fn free(self: @This()) void {
            defer std.c.free(self.ptr);
        }
    };

    pub fn string(self: @This()) FreeableCStr {
        return FreeableCStr{ .ptr = c_api.ts_node_string(self._c) };
    }

    pub fn in_source(self: @This(), src: []const u8) []const u8 {
        const start = @as(usize, c_api.ts_node_start_byte(self._c));
        const end = @as(usize, c_api.ts_node_end_byte(self._c));
        return src[start..end];
    }

    pub fn parent(self: @This()) Node {
        if (self.is_null()) return self;
        return Node { ._c = c_api.ts_node_parent(self._c) };
    }

    pub fn child_count(self: @This()) u32 {
        if (self.is_null()) return 0;
        return c_api.ts_node_child_count(self._c);
    }


    pub fn symbol(self: @This()) Symbol {
        if (self.is_null()) return 0;
        return c_api.ts_node_symbol(self._c);
    }

    pub fn dbgprint_fields(self: @This()) void {
        const lang = cpp(); // temp
        if (self.is_null()) {
            std.debug.print("{{NULL}}\n", .{});
            return;
        }
        const count = self.child_count();
        var i: u32 = 0;
        std.debug.print("{s} = [{}]: {{\n", .{self.@"type"(), count});
        while (i < count) {
            std.debug.print("  - field #: {}\n", .{i});
            const maybeFieldName = self.field_name_for_child(i);
            if (maybeFieldName) |fieldName| {
                std.debug.print("\tfield name: {s}\n", .{fieldName});
                std.debug.print("\tfield id: {}\n", .{lang.field_id_for_name(fieldName)});
            } else {
                std.debug.print("\tfield name: NONE\n", .{});
                std.debug.print("\tfield id: NONE\n", .{});
            }
            i += 1;
        }
        std.debug.print("}}\n", .{});
    }

    pub fn dbgprint_field_in_parent(self: @This()) void {
        const lang = cpp(); // temp
        if (self.is_null()) {
            std.debug.print("<node NULL />\n", .{});
            return;
        }
        const count = self.parent().child_count();
        std.debug.print("node type/symbol: {}, child count: {}\n", .{self.symbol(), count});
        var i: u32 = 0;
        while (i < count) {
            std.debug.print("{}:  {} <=> {}\n", .{i, self._c, self.child(i)._c});
            if (std.meta.eql(self._c, self.child(i)._c)) {
                const maybeFieldName = self.field_name_for_child(i);
                if (maybeFieldName) |fieldName| {
                    std.debug.print("field name: {s}\n", .{fieldName});
                    std.debug.print("field id: {}\n", .{lang.field_id_for_name(fieldName)});
                } else {
                    std.debug.print("field name: NONE\n", .{});
                    std.debug.print("field id: NONE\n", .{});
                }
                std.debug.print("\n", .{});
                return;
            }
            i += 1;
        }
        //unreachable;
    }

    /// not from tree-sitter API, convenience wrapper
    pub fn exec_query(self: @This(), query_src: []const u8) !QueryMatchesIterator {
        var err_offset = @as(u32, 0);
        var err_type: c_api.TSQueryError = c_api.TSQueryErrorNone;
        const language = c_api.ts_tree_language(self._c.tree);
        const query = c_api.ts_query_new(language, query_src.ptr, @intCast(u32, query_src.len), &err_offset, &err_type);
        switch (err_type) {
            c_api.TSQueryErrorSyntax => return error.TSQueryErrorSyntax,
            c_api.TSQueryErrorNodeType => return error.TSQueryErrorNodeType,
            c_api.TSQueryErrorField => return error.TSQueryErrorField,
            c_api.TSQueryErrorCapture => return error.TSQueryErrorCapture,
            c_api.TSQueryErrorStructure => return error.TSQueryErrorStructure,
            c_api.TSQueryErrorLanguage => return error.TSQueryErrorLanguage,
            //c_api.TSQueryErrorNone => {},
            else => {}, // ignore others, there are no other enum values
        }
        const cursor = c_api.ts_query_cursor_new().?;
        c_api.ts_query_cursor_exec(cursor, query, self._c);

        return QueryMatchesIterator {
            ._query = query orelse @panic("null query"),
            ._cursor = cursor
        };
    }
};

pub const QueryMatch = struct {
    _c: c_api.TSQueryMatch,
};

pub const QueryMatchesIterator = struct {
    _cursor: *c_api.TSQueryCursor,
    _query: *c_api.TSQuery,

    // FIXME: see ts_query_cursor_next_capture, might fix bugs I encounter elsewhere

    const Self = @This();

    pub fn next(self: Self) ?QueryMatch {
        var match: c_api.TSQueryMatch = undefined;
        var hadMoreMatches = c_api.ts_query_cursor_next_match(self._cursor, &match);
        return if (hadMoreMatches) QueryMatch{._c = match} else null;
    }

    pub fn free(self: Self) void {
        c_api.ts_query_cursor_delete(self._cursor);
        c_api.ts_query_delete(self._query);
    }
};

pub const Tree = struct {
    _c: *c_api.TSTree,

    pub fn language(self: @This()) bool {
        return c_api.ts_tree_language(self._c);
    }

    pub fn delete(self: @This()) void {
        return c_api.ts_tree_delete(self._c);
    }

    pub fn root_node(self: @This()) Node {
        return Node { ._c = c_api.ts_tree_root_node(self._c) };
    }
};

// these are just typedefs to native types
pub const FieldId = c_api.TSFieldId;
pub const Symbol = c_api.TSSymbol;

pub const SymbolType = enum(c_api.TSSymbolType) {
    regular = c_api.TSSymbolType.TSSymbolTypeRegular,
    anonymous = c_api.TSSymbolType.TSSymbolTypeAnonymous,
    auxiliary = c_api.TSSymbolType.TSSymbolTypeAuxiliary,
};

pub const Language = struct {
    _c: *c_api.TSLanguage,

    const Self = @This();

    pub fn symbol_count(self: Self) u32 {
        return c_api.ts_language_symbol_count(self._c);
    }

    pub fn symbol_name(self: Self, symbol: Symbol) ?[]const u8 {
        const result = c_api.ts_language_symbol_name(self._c, symbol);
        return if (result == null) null else std.mem.span(result);
    }
    pub fn symbol_for_name(self: Self, string: []const u8, is_named: bool) Symbol {
        return c_api.ts_language_symbol_for_name(self._c, string.ptr, @truncate(u32, string.len), is_named);
    }
    pub fn field_count(self: Self) u32 {
        return c_api.ts_language_field_count(self._c);
    }
    pub fn field_name_for_id(self: Self, field_id: FieldId) ?[]const u8 {
        const result = c_api.ts_language_field_name_for_id(self._c, field_id);
        return if (result == null) null else std.mem.span(result);
    }
    pub fn field_id_for_name(self: Self, name: []const u8) FieldId {
        return c_api.ts_language_field_id_for_name(self._c, name.ptr, @truncate(u32, name.len));
    }
    pub fn symbol_type(self: Self, symbol: Symbol) SymbolType {
        return c_api.ts_language_symbol_type(self._c, symbol);
    }
    pub fn version(self: Self) u32 {
        return c_api.ts_language_version(self._c);
    }
};

/// generate a type from the tree-sitter header
fn wrapType(comptime name: []const u8, comptime Type: type) type {
    const decls_count = comptime decls: {
        var i = @as(i32, 0);
        for (std.meta.declarations(c_api)) |decl| {
            if (std.mem.startsWith(decl.name, name)) {
                i += 1;
            }
        }
        break :decls i;
    };

    const decls = comptime decls: {
        var i = @as(i32, 0);
        var result = [decls_count]std.builtin.TypeInfo.StructField;
        for (std.meta.declarations(c_api)) |decl| {
            if (std.mem.startsWith(decl.name, name)) {
                result[i] = std.builtin.TypeInfo.Declaration{
                    .name = decl.name[decl.len + 1..decl.name.len],
                    .data = if (decl.data == .Fn) decl.data else decl.data
                };
                i += 1;
            }
        }
        break :decls result;
    };

    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .fields = [_]std.builtin.TypeInfo.StructField{
                .{ .name = "_c", .field_type = *Type, .default_value = undefined, .is_comptime = false, .alignment = 8 }
            },
            .decls = decls,
            .is_tuple = false
        }
    });
}

test "wrapType" {
    _ = wrapType;
//     // unused because wrapType's iteration of all fields in c_api drags in unsupported stuff like glibc long double functions
//     const Language = wrapType("ts_language", c_api.TSLanguage);
//     std.meta.eql(
//         std.meta.declarations(@Type(Language)),
//         [_]std.builtin.TypeInfo.Declaration{
//             .{ .name = "symbol_name", .data = c_api.ts_language_symbol_name },
//             .{ .name = "symbol_for_name", .data = c_api.ts_language_symbol_for_name },
//             .{ .name = "field_count", .data = c_api.ts_language_field_count },
//             .{ .name = "field_name_for_id", .data = c_api.ts_language_field_name_for_id },
//             .{ .name = "field_id_for_name", .data = c_api.ts_language_field_id_for_name },
//             .{ .name = "symbol_type", .data = c_api.ts_language_symbol_type },
//             .{ .name = "version", .data = c_api.ts_language_version },
//         }
//     );
//     const lang = Language.new();
//     _ = lang;
//     defer {
//         lang.free();
//     }
}

const QueryError = enum {
  None,
  Syntax,
  NodeType,
  Field,
  Capture,
  Structure,
  Language,
};

// pub const QueryResult = union(enum) {
//     result: Query,
//     error: QueryError,
// };

pub const Query = struct {
    _c: *c_api.TSQuery,

    const Self = @This();

    pub fn new(lang: Language, source: []u8) Self {
        return Self{ ._c = c_api.ts_query_new(lang, source).? };
    }

    pub fn symbol_count(self: Self) u32 {
        return c_api.ts_language_symbol_count(self._c);
    }
};

pub const QueryCursor = struct {
    _c: *c_api.TSQueryCursor,

    const Self = @This();

    pub fn new() Self {
        return Self{ ._c = c_api.ts_query_cursor_new().? };
    }

    pub fn exec(self: Self, query: Query, node: Node) void {
        return c_api.ts_query_cursor_exec(self._c, query._c, node._c);
    }
};

// TODO: inline all direct wrappers
pub const TreeCursor = struct {
    _c: c_api.TSTreeCursor,

    const Self = @This();

    pub inline fn new(node: Node) Self {
        return Self{ ._c = c_api.ts_tree_cursor_new(node._c) };
    }

    pub inline fn free(self: *Self) void {
        c_api.ts_tree_cursor_delete(&self._c);
    }

    pub inline fn reset(self: *Self, node: Node) void {
        c_api.ts_tree_cursor_reset(&self._c, node._c);
    }

    pub inline fn goto_first_child(self: *Self) bool {
        return c_api.ts_tree_cursor_goto_first_child(&self._c);
    }

    pub inline fn goto_next_sibling(self: *Self) bool {
        return c_api.ts_tree_cursor_goto_next_sibling(&self._c);
    }

    pub inline fn goto_parent(self: *Self) bool {
        return c_api.ts_tree_cursor_goto_parent(&self._c);
    }

    pub inline fn current_node(self: Self) Node {
        return Node{._c = c_api.ts_tree_cursor_current_node(&self._c)};
    }

    pub inline fn current_field_name(self: *Self) ?[]const u8 {
        const maybe_cstr = c_api.ts_tree_cursor_current_field_name(&self._c);
        if (maybe_cstr) |cstr| {
            return maybe_cstr[0..std.mem.len(cstr)];
        } else {
            return null;
        }
    }

    pub inline fn current_field_id(self: *Self) c_api.TSFieldId {
        return c_api.ts_tree_cursor_current_field_id(&self._c);
    }
};

test "TreeCursor" {
    // NOTE: can I make this global or comptime data only referenced by tests and therefore not part
    // of standard builds?
    var parser = Parser.new();
    defer parser.free();

    if (!parser.set_language(cpp())) @panic("couldn't set cpp lang");

    const tree = parser.parse_string(null, "int main() {}");
    // NOTE: would be nice to just read `expect` a zig struct if more complicated tests are necessary...
    // .{ .name="translation_unit", .children=.{.{.name=fn_def}} }

    var cursor = TreeCursor.new(tree.root_node());
    defer cursor.free();

    try std.testing.expectEqualStrings("translation_unit", cursor.current_node().@"type"().?);
    try std.testing.expectEqual(false, cursor.goto_next_sibling());
    try std.testing.expectEqual(true, cursor.goto_first_child());

    try std.testing.expectEqualStrings("function_definition", cursor.current_node().@"type"().?);
    try std.testing.expectEqual(@as(?[]const u8, null), cursor.current_field_name());
    try std.testing.expectEqual(false, cursor.goto_next_sibling());
    try std.testing.expectEqual(true, cursor.goto_first_child());

    try std.testing.expectEqualStrings("primitive_type", cursor.current_node().@"type"().?);
    try std.testing.expectEqualStrings("type", cursor.current_field_name().?);
    try std.testing.expectEqual(false, cursor.goto_first_child());
    try std.testing.expectEqual(true, cursor.goto_next_sibling());

    try std.testing.expectEqualStrings("function_declarator", cursor.current_node().@"type"().?);
    try std.testing.expectEqualStrings("declarator", cursor.current_field_name().?);
    try std.testing.expectEqual(true, cursor.goto_first_child());

    try std.testing.expectEqualStrings("identifier", cursor.current_node().@"type"().?);
    try std.testing.expectEqualStrings("declarator", cursor.current_field_name().?);
    try std.testing.expectEqual(false, cursor.goto_first_child());
    try std.testing.expectEqual(true, cursor.goto_next_sibling());

    try std.testing.expectEqualStrings("parameter_list", cursor.current_node().@"type"().?);
    try std.testing.expectEqualStrings("parameters", cursor.current_field_name().?);
    try std.testing.expectEqual(true, cursor.goto_first_child());
    try std.testing.expectEqual(true, cursor.goto_parent()); // ignore testing anonymous nodes for now...
    try std.testing.expectEqual(false, cursor.goto_next_sibling());
    try std.testing.expectEqual(true, cursor.goto_parent());
    try std.testing.expectEqual(true, cursor.goto_next_sibling());

    try std.testing.expectEqualStrings("compound_statement", cursor.current_node().@"type"().?);
    try std.testing.expectEqualStrings("body", cursor.current_field_name().?);
    try std.testing.expectEqual(true, cursor.goto_first_child());
    try std.testing.expectEqual(true, cursor.goto_parent()); // ignore testing anonymous nodes for now...
    try std.testing.expectEqual(false, cursor.goto_next_sibling());
}

// c++ support
extern fn tree_sitter_cpp() callconv(.C) *c_api.TSLanguage;

// TODO: remove this and dependency on tree_sitter_cpp,
// languages it should be loaded at runtime
// maybe make this a field and statically initialize it?
pub fn cpp() Language {
    return Language{._c = tree_sitter_cpp()};
}

