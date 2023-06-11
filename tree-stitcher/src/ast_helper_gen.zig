const builtin = @import("builtin");
const std = @import("std");
const json = std.json;
const clap = @import("zig-clap");
// not used and therefore ignored off posix
const mman = @cImport({ @cInclude("sys/mman.h"); });

const sexp = union (enum) {
    str: []const u8,
    symbol: []const u8,
    pair: struct {
        car: *sexp,
        cdr: *sexp,
    },

    pub fn write(self: @This(), writer: *std.io.Writer) !void {
        switch (self) {
            .str => |data| writer.write(data),
            .symbol => |data| {
                writer.write("'");
                writer.write(data);
            },
            .pair => |data| {
                writer.write("(");
                data.car.write(writer);
                writer.write(" ");
                data.cdr.write(writer);
                writer.write(")");
            },
        }
    }
};

/// A buffer that contains the entire contents of a file
const FileBuffer = @import("./FileBuffer.zig");

const Grammar = struct {
    name: []const u8,
    word: ?[]const u8,
    /// interface Alias {
    ///   type: "ALIAS",
    ///   content: Rule,
    ///   named: boolean,
    ///   value: string,
    /// }
    /// interface Rule {
    ///   type: "CHOICE" | "REPEAT" | "SEQ" | "ALIAS" | "PATTERN"
    ///       | "STRING" | "FIELD" | "IMMEDIATE_TOKEN" | "BLANK",
    ///   name?: string,
    ///   members?: Rule[],
    /// }
    rules: json.ValueTree,
    extras: []struct { type: []const u8, name: []const u8 },
    conflicts: [][][]const u8,
    precedences: [][]const u8,
    externals: []struct { type: []const u8, name: []const u8 },
    @"inline": [][]const u8,
    supertypes: [][]const u8,
};

const NodeTypesFile = []const struct {
    type: []const u8,
    named: bool,
    subtypes: ?[]const struct { type: []const u8, named: bool },
    fields: ?std.StringHashMap(struct {
        multiple: bool,
        required: bool,
        types: []const struct { type: []const u8, named: bool },
    }),
    children: ?std.StringHashMap(struct {
        multiple: bool,
        required: bool,
        types: []const struct { type: []const u8, named: bool },
    }),
};

// high-level overview:
// see if we can use the node-types.json's fields property to generate the necessary
// ast builders

pub fn convertNodeTypes(
    allocator: std.mem.Allocator,
    paths: []const []const u8,
    write_ctx: anytype,
) !void {
    var parser = json.Parser.init(allocator, false);
    defer parser.deinit();

    if (paths.len == 0) {
        std.debug.print("no paths provided\n", .{});
        return;
    }

    for (paths) |rel_path| {
        // TODO: don't use realpath, just some path join operation
        const file = try FileBuffer.fromDirAndPath(allocator, std.fs.cwd(), rel_path);
        // TODO: use typed streaming json parser in 0.11.0
        var parsed = try parser.parse(file.buffer);
        defer parsed.deinit();

        // doesn't seem to work with record types...
        // var parsed2 = try json.parse(
        //     NodeTypesFile,
        //     &std.json.TokenStream.init(file.buffer),
        //     .{.allocator = allocator}
        // );
        // std.debug.print("parsed2: {any}\n", .{ parsed2 });

        const node_types = switch (parsed.root) {
            .Array => |a| a.items,
            else => return error.RootNotArray
        };

        var field_set = std.StringHashMap(void).init(allocator);
        defer field_set.deinit();

        for (node_types) |maybe_node_type| {
            const node_type = switch (maybe_node_type) {
                .Object => |o| o,
                else => return error.RootArrayContainsNonObject,
            };

            const node_type_name = switch (node_type.get("type") orelse return error.NodeTypeWithoutTypeProperty) {
                .String => |s| s,
                else => return error.NodeTypeTypeNotString,
            };

            const is_hidden_node = std.mem.startsWith(u8, node_type_name, "_");
            if (is_hidden_node)
                continue;

            const is_anonymous_node = switch (node_type.get("named") orelse return error.NodeTypeWithoutNamedProperty) {
                .Bool => |s| s,
                else => return error.NodeTypeNamedNotBool,
            };
            if (is_anonymous_node)
                continue;

            const maybe_fields = if (node_type.get("fields")) |fields_val| switch (fields_val) {
                .Object => |o| o,
                else => return error.NodeTypeFieldsNotObject,
            } else null;

            if (maybe_fields) |fields| {
                var field_iterator1 = fields.iterator();
                while (field_iterator1.next()) |field| {
                    const field_name = field.key_ptr;
                    const field_type = field.value_ptr;
                    _ = field_type;
                    const had = try field_set.fetchPut(field_name.*, {});
                    if (had != null) {
                        _ = try std.fmt.format(write_ctx, "(define {s} '{s})\n", .{field_name.*, field_name.*});
                    }
                }

                var field_iterator2 = fields.iterator();
                _ = try std.fmt.format(write_ctx, "(define-complex-node {s}\n  (", .{node_type_name});
                while (field_iterator2.next()) |field| {
                    const field_name = field.key_ptr;
                    //write_ctx.write("({}: {})\n  ", .{field_name.*, "(DEFAULT_TYPE_IF_1)"});
                    _ = try std.fmt.format(write_ctx, "({s}: {s})\n  ", .{field_name.*, "(DEFAULT_TYPE_IF_1)"});
                    //std.fmt.format(write_ctx, );
                }
                _ = try write_ctx.write("))\n");
            } else {
                _ = try std.fmt.format(write_ctx, "(define-simple-node {s})\n", .{node_type_name});
            }
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const cli_params = comptime clap.parseParamsComptime(
        \\-h, --help    Display this help and exit
        \\<str>...
        \\
    );

    var diag = clap.Diagnostic{};
    var cli_args = clap.parse(clap.Help, &cli_params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch unreachable;
        return err;
    };
    defer cli_args.deinit();

    if (cli_args.args.help)
        return clap.usage(std.io.getStdErr().writer(), clap.Help, &cli_params);
    
    try convertNodeTypes(allocator, cli_args.positionals, std.io.getStdOut().writer());
}

// TODO: create automated tests for grammars like c++
