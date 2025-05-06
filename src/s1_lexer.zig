//! Table-driven lexing
const std = @import("std");
const builtin = @import("builtin");
const lib = @import("s0_lib.zig");

//run: zig build test

// Reduce the number of state transitions we need to do by combining many u8
// into a single 'Class'
const Class = enum {
    whitespace,
    u,
    x,

    abc_a_f,
    abc_lc,
    abc_A_F,
    abc_UC,
    angle_r,
    bang,
    colon,
    comma,
    curly_l,
    curly_r,
    dash,
    dot,
    double_quote,
    equal,
    escape,
    fail,
    hash,
    newline,
    number,
    paren_l,
    paren_r,
    pipe,
    square_l,
    square_r,
    underline,
};
const char_classifier = blk: {
    var ret: [256]Class = undefined;
    //@memset(&ret, .fail);

    // Not sure how to do inclusive ranges: 'a'..='z'
    for (0..10) |c| ret['0' + c] = .number;
    for (0..6) |c| ret['A' + c] = .abc_A_F;
    for (0..6) |c| ret['a' + c] = .abc_a_f;
    for (6..26) |c| ret['A' + c] = .abc_UC;
    for (6..26) |c| ret['a' + c] = .abc_lc;
    const to_set = &[_]struct { u8, Class }{
        .{ 'u', .u }, // Override 'u' for quotes '\u{12345}'
        .{ 'x', .x }, // Override 'x' for quotes '\x65'
        .{ '"', .double_quote },
        .{ ',', .comma },
        .{ '!', .bang },
        .{ '#', .hash },
        .{ '(', .paren_l },
        .{ ')', .paren_r },
        .{ '-', .dash },
        .{ '.', .dot },
        .{ ':', .colon },
        .{ '=', .equal },
        .{ '>', .angle_r },
        .{ '[', .square_l },
        .{ '\\', .escape },
        .{ ']', .square_r },
        .{ '{', .curly_l },
        .{ '|', .pipe },
        .{ '}', .curly_r },
        .{ '_', .underline },
        .{ '\t', .whitespace },
        .{ ' ', .whitespace },
        .{ '\n', .newline },
        .{ '\r', .whitespace },
    };
    for (to_set) |pair| {
        ret[pair[0]] = pair[1];
        //_ = pair;
    }
    break :blk ret;
};

// In theory, the ideal lexer is a lookup table because there are no branches
// Lexing is simple enough that this optimization is not difficult to maintain
state: State = .s_a,
index_source: u32 = 0,
index_cursor: u32 = 0,
index_output: u32 = 0,
index_error: u1 = 0,
first_error: [2]?Token1 = .{ null, null },

const SELF = @This();
const State = enum {
    s_a,

    s_comment,
    s_error,
    s_tag,
    s_identifier,
    s_number,

    s_dash,
    s_dot,
    s_string1,
    s_string2,
    s_escape,
    s_hex1,
    s_hex2,
    s_unicode1,
    s_unicode2,
    s_unicode3,
};
const Error = error{
    LexArrowMissingDash,
    LexCharNotEscapable,
    LexEmptyUnicodeBlock,
    LexInvalidHex,
    LexNotInQuote,
    LexUnsupportedArithmeticSymbol,
    LexUnsupportedTagCharacter,
};
const Value = enum {
    whitespace,

    arrow,
    bang,
    byte,
    call,
    colon,
    comma,
    comment,
    curly_l,
    curly_r,
    dot,
    dot2,
    equal,
    ident,
    number,
    paren_l,
    paren_r,
    pipe,
    quote,
    skip,
    square_l,
    square_r,
    string,
    tag,
    unicode,
};
// First pass
const Token1 = struct {
    value: Error!Value,
    source: lib.Source,
};
// Second pass (after error handling)
const Token2 = struct {
    value: Value,
    source: lib.Source,
};

const fsm_transition = blk: {
    const states = std.meta.tags(State);
    const classes = std.meta.tags(Class);
    var ret: [states.len][classes.len]struct { State, Target, Error!Value } = undefined;

    for (states) |state| {
        for (classes) |class| {
            ret[@intFromEnum(state)][@intFromEnum(class)] = sw: switch (state) {
                .s_a => switch (class) {
                    .abc_a_f, .abc_lc, .u, .x, .underline => .{ .s_identifier, .new, .ident },
                    .abc_A_F, .abc_UC => .{ .s_tag, .new, .tag },

                    .double_quote => .{ .s_string1, .new, .quote },
                    .dash => .{ .s_dash, .new, .number },
                    .number => .{ .s_number, .new, .number },

                    .escape => .{ .s_a, .err, error.LexNotInQuote },
                    .fail => .{ .s_a, .err, error.LexNotInQuote },

                    .angle_r => .{ .s_a, .err, error.LexArrowMissingDash },
                    .bang => .{ .s_a, .new, .bang },
                    .colon => .{ .s_a, .new, .colon },
                    .comma => .{ .s_a, .new, .comma },
                    .curly_l => .{ .s_a, .new, .curly_l },
                    .curly_r => .{ .s_a, .new, .curly_r },
                    .dot => .{ .s_dot, .new, .dot },
                    .equal => .{ .s_a, .new, .equal },
                    .hash => .{ .s_a, .new, .comment },
                    .paren_l => .{ .s_a, .new, .paren_l },
                    .paren_r => .{ .s_a, .new, .paren_r },
                    .pipe => .{ .s_a, .new, .pipe },
                    .square_l => .{ .s_a, .new, .square_l },
                    .square_r => .{ .s_a, .new, .square_r },
                    .whitespace, .newline => .{ .s_a, .new, .whitespace },
                },
                .s_comment => switch (class) {
                    .newline => .{ .s_a, .update, .comment },
                    else => .{ .s_comment, .update, .comment },
                },
                .s_identifier => switch (class) {
                    .abc_a_f, .abc_lc, .abc_A_F, .abc_UC => .{ .s_identifier, .update, .ident },
                    .number, .u, .x, .underline => .{ .s_identifier, .update, .ident },
                    .paren_l => .{ .s_a, .update, .call },
                    else => continue :sw .s_a,
                },
                .s_tag => switch (class) {
                    .abc_a_f, .abc_lc, .abc_A_F, .abc_UC => .{ .s_tag, .update, .tag },
                    .u, .x => .{ .s_tag, .update, .tag },
                    .whitespace => continue :sw .s_a,
                    else => .{ .s_a, .err, error.LexUnsupportedTagCharacter },
                },
                .s_number => switch (class) {
                    .number => .{ .s_number, .update, .number },
                    else => continue :sw .s_a,
                },

                .s_dash => switch (class) {
                    .angle_r => .{ .s_a, .update, .arrow },
                    .number => .{ .s_number, .update, .number },
                    else => .{ .s_a, .err, error.LexUnsupportedArithmeticSymbol },
                },
                .s_dot => switch (class) {
                    .dot => .{ .s_a, .update, .dot2 },
                    else => continue :sw .s_a,
                },
                .s_string1 => switch (class) {
                    .double_quote => .{ .s_a, .new, .quote },
                    .escape => .{ .s_escape, .new, .skip },
                    else => .{ .s_string2, .new, .string },
                },
                .s_string2 => switch (class) {
                    .double_quote => .{ .s_a, .new, .quote },
                    .escape => .{ .s_escape, .new, .skip },
                    else => .{ .s_string2, .update, .string },
                },
                .s_escape => switch (class) {
                    .u => .{ .s_unicode1, .update, .skip },
                    .x => .{ .s_hex1, .update, .skip },
                    .escape => .{ .s_string1, .update, .string },
                    else => .{ .s_a, .err, error.LexCharNotEscapable },
                },
                // Start \x
                .s_hex1 => switch (class) {
                    .abc_a_f, .abc_A_F, .number => .{ .s_hex2, .new, .byte },
                    else => .{ .s_error, .err, error.LexInvalidHex },
                },
                // Start \x0
                .s_hex2 => switch (class) {
                    .abc_a_f, .abc_A_F, .number => .{ .s_string1, .update, .byte },
                    else => continue :sw .s_string1,
                },
                // Start \u
                .s_unicode1 => switch (class) {
                    .curly_l => .{ .s_unicode2, .new, .skip },
                    else => .{ .s_error, .err, error.LexInvalidHex },
                },
                // Start \u{
                .s_unicode2 => switch (class) {
                    .abc_a_f, .abc_A_F, .number => .{ .s_unicode3, .new, .unicode },
                    .curly_r => .{ .s_error, .err, error.LexEmptyUnicodeBlock },
                    else => .{ .s_error, .err, error.LexInvalidHex },
                },
                .s_unicode3 => switch (class) {
                    .abc_a_f, .abc_A_F, .number => .{ .s_unicode3, .update, .unicode },
                    .curly_r => .{ .s_string1, .new, .skip },
                    else => .{ .s_error, .err, error.LexInvalidHex },
                },

                .s_error => .{ .s_error, .err, .whitespace },
            };
        }
    }

    break :blk ret;
};
const Target = enum {
    err,
    new,
    update,
};

pub const Token = Token2;
pub fn max_size(input: []const u8) u32 {
    const extra = 2;
    std.debug.assert(input.len < std.math.maxInt(u32) - extra);
    return @intCast(input.len + extra);
}

// Trying to do no branching here
pub fn next(self: *SELF, char: u8) struct { u32, Token1 } {
    //_ = char;
    self.state = self.state;

    const char_class = char_classifier[char];
    self.state, const hello, const value = fsm_transition[@intFromEnum(self.state)][@intFromEnum(char_class)];

    // We reserve `output[0]` for errors
    const size: comptime_int = std.meta.tags(Target).len;
    const idx: u2 = @intFromEnum(hello);
    self.index_output += ([size]u1{ 0, 1, 0 })[idx];
    self.index_cursor = ([size]u32{ self.index_source, self.index_source, self.index_cursor })[idx];
    self.index_source += 1;

    const ret = Token1{ .value = value, .source = .{ .from = self.index_cursor, .till = self.index_source } };

    // Set the second index
    self.first_error[self.index_error] = ret;
    self.index_error = ([size]u1{ 1, self.index_error, self.index_error })[idx];

    return .{ ([3]u32{ 0, self.index_output, self.index_output })[idx], ret };
}

pub fn done(self: *SELF) !struct { u32, Token1 } {
    const close = self.index_source;
    var ret = self.next(' ');
    ret[1].source.till = close;

    if (self.first_error[0]) |maybe_error| {
        _ = try maybe_error.value;
    }
    return ret;
}

pub fn parse(allocator: std.mem.Allocator, input: []const u8) ![]Token2 {
    const pass1 = blk: {
        var ret: []Token1 = try allocator.alloc(Token1, max_size(input));
        var iter = SELF{};
        iter = iter;
        var output_index: u32 = 0;
        for (input) |c| {
            output_index, const token = iter.next(c);
            ret[output_index] = token;
            //std.debug.print("'{c}' {s} {any}\n", .{ c, @tagName(iter.state), token.value });
        }
        output_index, const token = try iter.done();
        ret[output_index] = token;
        break :blk ret[1..output_index];
    };

    std.debug.assert(@sizeOf(Token1) >= @sizeOf(Token2));
    var pass2: []Token2 = @alignCast(@ptrCast(pass1));
    pass2 = pass2;

    // All errors should be sent to ret[0] (entry before pass[0])
    // Unwrap all these errors reusing the same memory
    for (pass1, pass2) |p1, *p2| {
        p2.* = .{ .value = p1.value catch unreachable, .source = p1.source };
        //std.debug.print("{any} '{s}'\n", .{ p1.value, input[p1.source.from..p1.source.till] });
    }
    return pass2;
}

// Attempts to
pub fn reconstruct(alloc: std.mem.Allocator, input: []const u8, output: []Token2) !void {
    std.debug.assert(input.len >= output.len);
    std.debug.assert(input.len < std.math.maxInt(u32));
    var buffer = try std.ArrayList(u8).initCapacity(alloc, input.len);
    defer buffer.deinit();

    const validate_char_class = struct {
        fn lambda(s: []const u8, classes: []const Class) ![]const u8 {
            for (s) |c| {
                const class = char_classifier[c];
                _ = std.mem.indexOfScalar(Class, classes, class) orelse {
                    std.debug.print("'{s}' {s}\n", .{ s, @tagName(class) });
                    return error.Fail;
                };
            }
            return s;
        }
    }.lambda;

    var cursor: u32 = 0;
    for (output) |token| {
        const s = input[token.source.from..token.source.till];
        const to_add: [3][]const u8 = switch (token.value) {
            .whitespace => .{ "", "", try validate_char_class(s, &.{ .whitespace, .newline }) },

            .arrow => .{ "->", "", "" },
            .bang => .{ "!", "", "" },
            .byte => .{ "\\x", "", try validate_char_class(s, &.{ .abc_a_f,  .abc_A_F, .number }) },
            .call => .{ "", try validate_char_class(s[0..s.len - 1], &.{ .abc_a_f, .abc_lc, .abc_A_F, .abc_UC, .u, .x, .underline, .number }), "(" },
            .colon => .{ ":", "", "" },
            .comma => .{ ",", "", "" },
            .comment => .{ "", "", "" },
            .curly_l => .{ "{", "", "" },
            .curly_r => .{ "}", "", "" },
            .dot => .{ ".", "", "" },
            .dot2 => .{ "..", "", "" },
            .equal => .{ "=", "", "" },
            .ident => .{ "", "", try validate_char_class(s, &.{ .abc_a_f, .abc_lc, .abc_A_F, .abc_UC, .u, .x, .underline, .number }) },
            .tag => .{ "", "", try validate_char_class(s, &.{ .abc_a_f, .abc_lc, .abc_A_F, .abc_UC, .u, .x }) },
            .number => .{ s, "", "" },
            .paren_l => .{ "(", "", "" },
            .paren_r => .{ ")", "", "" },
            .pipe => .{ "|", "", "" },
            .quote => .{ "\"", "", "" },
            .skip => .{ "", "", "" },
            .square_l => .{ "[", "", "" },
            .square_r => .{ "]", "", "" },
            .string => .{ "", "", if (std.mem.eql(u8, s, "\\")) "\\\\" else s },
            .unicode => .{ "\\u{", try validate_char_class(s, &.{ .abc_a_f, .abc_A_F, .number }), "}" },
        };
        for (to_add) |x| {
            try buffer.appendSlice(x);
        }
        if (!std.mem.startsWith(u8, input[cursor..], buffer.items[cursor..])) {
            const index = if (cursor < 10) 0 else cursor - 10;
            std.debug.print("Lexing error {s}\n", .{@tagName(token.value)});
            std.debug.print("Context : {s}\n", .{input[index..cursor]});
            std.debug.print("Expected: {s}\n", .{input[cursor..buffer.items.len]});
            std.debug.print("Recieved: {s}{s}{s}\n", .{to_add[0], to_add[2], to_add[1]});
            return error.NotMatched;
        }
        cursor += @intCast(to_add[0].len + to_add[1].len + to_add[2].len);
    }
}

test "lex corner" {
    const T = Value;
    for ([_]struct { []const u8, []const T }{
        .{ "", &.{} },
        .{ "{}", &.{ .curly_l, .curly_r } },
    }) |x| {
        const buffer = try std.testing.allocator.alloc(u8, max_size(x[0]) * @sizeOf(Token1));
        defer std.testing.allocator.free(buffer);
        var fba = std.heap.FixedBufferAllocator.init(buffer);

        const lexemes = try parse(fba.allocator(), x[0]);

        var lex_values = try std.testing.allocator.alloc(Value, lexemes.len);
        defer std.testing.allocator.free(lex_values);
        for (lexemes, 0..) |t, i| lex_values[i] = t.value;

        try std.testing.expectEqualSlices(T, x[1], lex_values);
    }
}

test "hello" {
    const asdf =
        \\ let alice = {name: "Alice"}
        \\  let bob = {name: "Bob\x2D\x3e", height: 192}
        \\let can = {name: "C\u{56e7}\u{00006E}", height: -1}
        \\alice.name
    ;

    //var lexemes = try std.ArrayList(Token).initCapacity(std.testing.allocator, asdf.len);
    //defer lexemes.deinit();

    {
        var buffer: [max_size(asdf)]Token1 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(@ptrCast(&buffer));
        const list = parse(fba.allocator(), asdf) catch |err| switch (err) {
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
        try reconstruct(std.testing.allocator, asdf, list);
    }
}
