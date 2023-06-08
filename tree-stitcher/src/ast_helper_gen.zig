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

// high-level overview:
// see if we can use the node-types.json's fields property to generate the necessary
// ast builders

pub fn convertGrammars(allocator: std.mem.Allocator, grammar_paths: []const []const u8) !void {
    var parser = json.Parser.init(allocator, false);
    defer parser.deinit();

    if (grammar_paths.len == 0) {
        std.debug.print("no grammars provided\n", .{});
        return;
    }

    for (grammar_paths) |rel_path| {
        // TODO: don't use realpath, just some path join operation
        const abs_path = try std.fs.cwd().realpathAlloc(allocator, rel_path);
        const grammar_file = try FileBuffer.from_path(allocator, abs_path);
        // TODO: use typed json parsing with Grammar type
        const grammar = try parser.parse(grammar_file.buffer);
        //std.debug.print("grammar: {any}\n", .{grammar.root.get("name")});
        std.debug.print("{s}\n", .{grammar.root.Object.get("name").?.String});
        const rules = grammar.root.Object.get("rules").?.Object;
        const top_level_rule = rules.keys()[0];
        _ = top_level_rule;
        std.debug.print("{s}\n", .{grammar.root.Object.get("name").?.String});
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
    
    try convertGrammars(allocator, cli_args.positionals);
}

// TODO: create automated tests for grammars like c++
