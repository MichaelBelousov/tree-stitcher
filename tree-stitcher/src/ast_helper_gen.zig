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

// TODO:
const JsonSchemaErrors = error {};

// high-level overview:
// see if we can use the node-types.json's fields property to generate the necessary
// ast builders

/// given a json value pointing to this type: {type: string, named: boolean}[],
/// if there is only one non-hidden element with named=true, return it
fn getOnlyNamedType(type_list: json.Value) !?json.ObjectMap {
    var found: ?json.ObjectMap = null;

    switch (type_list) {
        .Array => |a| for (a.items) |maybe_type| switch (maybe_type) {
            .Object => |type_| {
                // TODO: dedup with below?
                const is_named_node = if (type_.get("named")) |type_name| switch (type_name) {
                    .Bool => |s| s,
                    else => return error.TypeNamedNotBool,
                } else return error.TypeWithoutNamedProperty;

                if (!is_named_node)
                continue;

                const type_name = if (type_.get("type")) |type_type| switch (type_type) {
                    .String => |s| s,
                    else => return error.TypeTypeNotString,
                } else return error.TypeWithoutTypeProperty;

                const is_hidden_node = std.mem.startsWith(u8, type_name, "_");
                if (is_hidden_node)
                continue;

                // this is the second, so it's not the only one, return empty
                if (found != null) return null
                else found = type_;
            },
            else => return error.TypeListElementNotObject
        },
        else => return error.TypeListNotArray,
    }

    return found;
}

pub fn convertNodeTypes(
    allocator: std.mem.Allocator,
    paths: []const []const u8,
    scm_write_ctx: anytype,
    sld_write_ctx: anytype,
    out_name: []const u8,
) !void {
    var parser = json.Parser.init(allocator, false);
    defer parser.deinit();

    if (paths.len != 1) {
        std.debug.print("You must provide exactly one path", .{});
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
        _ = try std.fmt.format(scm_write_ctx, ";; ast-helper-gen for '{s}'\n", .{rel_path});
        _ = try std.fmt.format(sld_write_ctx,
            \\;; ast-helper-gen for '{s}'
            \\(define-library (sizr langs cpp)
            \\(import
            \\  (sizr langs support)
            \\  (scheme base)
            \\  (scheme read)
            \\  (scheme write))
            \\(export
            \\
        , .{rel_path});

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
            if (is_hidden_node) {
                continue;
            }

            const is_anonymous_node = switch (node_type.get("named") orelse return error.NodeTypeWithoutNamedProperty) {
                .Bool => |s| !s,
                else => return error.NodeTypeNamedNotBool,
            };
            if (is_anonymous_node)
                continue;

            const maybe_fields = if (node_type.get("fields")) |fields_val| switch (fields_val) {
                .Object => |o| if (o.count() > 0) o else null,
                else => return error.NodeTypeFieldsNotObject,
            } else null;

            if (maybe_fields) |fields| {
                var field_iterator1 = fields.iterator();
                while (field_iterator1.next()) |field| {
                    const field_name = field.key_ptr.*;
                    const had = try field_set.fetchPut(field_name, {});
                    if (had == null) {
                        _ = try std.fmt.format(scm_write_ctx, "(define {s}: '{s}:)\n", .{field_name, field_name});
                        _ = try std.fmt.format(sld_write_ctx, "  {s}:\n", .{field_name});
                    }
                }

                _ = try std.fmt.format(scm_write_ctx, "(define-complex-node {s}\n  (", .{node_type_name});
                _ = try std.fmt.format(sld_write_ctx, "  {s}\n", .{node_type_name});

                var field_iterator2 = fields.iterator();
                while (field_iterator2.next()) |field| {
                    const field_name = field.key_ptr;
                    const field_val = field.value_ptr;
                    const maybe_single_field_type = switch (field_val.*) {
                        .Object => |o| if (o.get("types")) |field_types| try getOnlyNamedType(field_types)
                            else return error.FieldWithoutTypes,
                        else => return error.FieldNotObject,
                    };

                    const field_required = switch (field_val.*) {
                        .Object => |o| if (o.get("required")) |required| switch (required) {
                            .Bool => |b| b,
                            else => return error.FieldRequiredNotBool,
                        } else return error.FieldWithoutRequiredProperty,
                        else => return error.FieldNotObject,
                    };

                    if (maybe_single_field_type) |single_field_type| {
                        const single_field_type_name = if (single_field_type.get("type")) |single_field_type_name| switch (single_field_type_name) {
                            .String => |s| s,
                            else => return error.TypeTypeNotString,
                        } else return error.TypeWithoutTypeProperty;

                        _ = try std.fmt.format(
                            scm_write_ctx,
                            "({s}: ({s}))\n  ",
                            .{field_name.*, single_field_type_name}
                        );
                    } else if (field_required) {
                        _ = try std.fmt.format(scm_write_ctx, "({s}:)\n  ", .{field_name.*});
                    } else {
                        _ = try std.fmt.format(scm_write_ctx, "({s}: \"\")\n  ", .{field_name.*});
                    }
                }
                _ = try scm_write_ctx.write("))\n");
            } else {
                _ = try std.fmt.format(scm_write_ctx, "(define-simple-node {s})\n", .{node_type_name});
            }
        }

        const maybe_last_slash_index = std.mem.lastIndexOf(u8, out_name, "/");
        const out_base_name = if (maybe_last_slash_index)
            |last_slash_index| out_name[last_slash_index + 1..]
            else out_name;

        _ = try std.fmt.format(sld_write_ctx,
            \\)
            \\  (include "{s}.scm"))
        , .{out_base_name});
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const cli_params = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help and exit
        \\-o, --out-name <str>  The path and name of the produced .scm and .sld files
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

    const out_name = cli_args.args.@"out-name" orelse "out";

    const scm_path = try std.fmt.allocPrint(allocator, "{s}.scm", .{out_name});
    const scm_file = try std.fs.cwd().createFile(scm_path, .{});
    defer scm_file.close();

    const sld_path = try std.fmt.allocPrint(allocator, "{s}.sld", .{out_name});
    const sld_file = try std.fs.cwd().createFile(sld_path, .{});
    defer sld_file.close();
    
    try convertNodeTypes(allocator, cli_args.positionals, scm_file.writer(), sld_file.writer(), out_name);
}

// TODO: create automated tests for grammars like c++
