const std = @import("std");
const parser = @import("./parser.zig");

pub fn main() anyerror!void {
    //std.log.info("All your codebase are belong to us.", .{});
    std.log.info("found this {}", .{parser.next_token("node example =")});
    //std.log.info("found \"{s}\"", .{(try parser.next_token("\"escape containing\\\" string \" ")).literal.string});
    std.log.info("found \"{s}\"", .{(try parser.next_token("\"escape containing\\\" string \" ")).literal.string});
}
