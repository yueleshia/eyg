const std = @import("std");
const lexer = @import("s1_lexer.zig");
//const ir = @import("s2_ir.zig");

pub fn main() !void {
    const asdf =
        \\ let alice = {name: "Alice"}
        \\  let bob = {name: "Bob\x2D\x3e", height: 192}
        \\let can = {name: "C\u{56e7}\u{00006E}", height: -1}
        \\alice.name
    ;

    //var lexemes = try std.ArrayList(Token).initCapacity(std.testing.allocator, asdf.len);
    //defer lexemes.deinit();

    const list = blk: {
        const list = lexer.parse(std.heap.page_allocator, asdf) catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            error.LexArrowMissingDash => |e| return e,
            error.LexCharNotEscapable => |e| return e,
            error.LexEmptyUnicodeBlock => |e| return e,
            error.LexInvalidHex => |e| return e,
            error.LexNotInQuote => |e| return e,
            error.LexUnsupportedArithmeticSymbol => |e| return e,
            error.LexUnsupportedTagCharacter => |e| return e,
        };
        for (list) |t| {
            switch (t.value) {
                .skip => {},
                .whitespace => {},
                .comment => {},
                else => {},
                //else => std.debug.print("{any} '{s}'\n", .{ t.value, asdf[t.source.from..t.source.till] }),
            }
        }
        try lexer.reconstruct(std.heap.page_allocator, asdf, list);
        break :blk list;
    };
    _ = list;

    //_ = try ir.parse(std.heap.page_allocator, asdf, list);
}

test "simple test" {
    _ = lexer;
}
