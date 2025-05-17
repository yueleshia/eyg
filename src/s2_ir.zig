//! Internal representation
const std = @import("std");
const lib = @import("s0_lib.zig");
const lexer = @import("s1_lexer.zig");

const SELF = @This();

const Entry = struct {
    n: [:0]const u8, // name
    l: []const u8, // label
    w: type, // write
    i: type, // internal representation
};
const token_data = [_]Entry{
    .{ .n = "variable", .l = "v", .w = struct{}, .i = lib.Source},
    .{ .n = "lambda", .l = "f", .w = struct{}, .i = lib.Source},
    .{ .n = "apply", .l = "a", .w = struct{ lhs: *u32 }, .i = struct { lhs: u32, rhs: u32 } },
    .{ .n = "let", .l = "a", .w = struct { rhs: *u32 }, .i = struct { lhs: u32, rhs: u32, ident: lib.Source } },
    //.{ .n = "binary", .l = "x" },
    .{ .n = "integer", .l = "i", .w = struct{}, .i = lib.Source },
    .{ .n = "string", .l = "s", .w = struct{}, .i = lib.Source },
    .{ .n = "tail", .l = "ta", .w = struct{}, .i = struct {} },
    .{ .n = "cons", .l = "c", .w = struct{ rhs: *u32 }, .i = struct { lhs: u32, rhs: u32 } },
    .{ .n = "vacant", .l = "z", .w = void, .i = struct {} },
    .{ .n = "empty", .l = "u", .w = void, .i = struct {} },
    .{ .n = "extend", .l = "e", .w = void, .i = struct { lhs: u32, rhs: u32, label: lib.Source } },
    .{ .n = "select", .l = "g", .w = void, .i = lib.Source },
    .{ .n = "overwrite", .l = "o", .w = void, .i = struct {} },
    //.{ .n = "tag", .l = "t", .w = void, .i = lib.Source },
    .{ .n = "case", .l = "m", .w = struct { rhs: *u32 }, .i = struct { lhs: u32, rhs: u32, tag: lib.Source} },
    .{ .n = "nocases", .l = "n", .w = void, .i = struct {} },
    //.{ .n = "perform", .l = "p", .w = void, .i = struct {}  },
    //.{ .n = "handle", .l = "h", .w = void, .i = struct {}  },
    //.{ .n = "shallow", .l = "hs", .w = void, .i = struct {}  },
    .{ .n = "builtin", .l = "b", .w = void, .i = lib.Source },
    //.{ .n = "reference", .l = "#" },
    //.{ .n = "release", .l = "#" },
};

const IRWrite = blk: {
    var fields: [token_data.len]std.builtin.Type.UnionField = undefined;
    for (&fields, token_data) |*f, d| f.* = .{ .name = d.n, .type = d.w, .alignment = @alignOf(d.w) };
    break :blk @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = Value,
        .fields = &fields,
        .decls = &.{},
    } });
};

const IRField = blk: {
    var fields: [token_data.len]std.builtin.Type.UnionField = undefined;
    for (&fields, token_data) |*f, d| f.* = .{ .name = d.n, .type = d.i, .alignment = @alignOf(d.i) };
    break :blk @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = Value,
        .fields = &fields,
        .decls = &.{},
    } });
};

inline fn reflect(comptime value: Value, comptime is_write: bool, token: Token, extra: []u32) @FieldType(if (is_write) IRWrite else IRField, @tagName(value)) {
    if (!is_write) std.debug.assert(value == token.value);

    switch (value) {
        inline .variable => if (!is_write) return .{ .from = token.one, .till = token.two },
        inline .lambda => if (!is_write) return .{ .from = token.one, .till = token.two },
        inline .apply => return if (is_write) .{ .lhs = &extra[0] } else return .{ .rhs = token.one, .lhs= extra[token.two] },
        inline .let => return if (is_write) .{ .rhs = &extra[0] } else .{ .lhs = token.one, .rhs = extra[token.two], .ident = .{ .from = extra[token.two + 1], .till = extra[token.two + 2] }},
        //inline .binary => {},
        inline .integer => if (!is_write) return .{ .from = token.one, .till = token.two },
        inline .string => if (!is_write) return .{ .from = token.one, .till = token.two },
        inline .tail => {},
        inline .cons => return if (is_write) .{ .rhs = &extra[0] } else .{ .lhs = token.two, .rhs = extra[token.one] },
        inline .vacant => {},
        inline .empty => {},
        inline .extend => return if (is_write) .{ .rhs = &extra[0] } else .{ .lhs = token.one, .rhs = extra[token.two], .label = .{ .from = extra[token.two + 1], .till = extra[token.two + 2] }},
        inline .select => {},
        inline .overwrite => {},
        //inline .tag => {},
        inline .case => return if (is_write) .{ .rhs = &extra[0] } else .{ .lhs = token.one, .rhs = extra[token.two], .tag = .{ .from = extra[token.two + 1], .till = extra[token.two + 2] } },
        inline .nocases => .{},
        //inline .perform => {},
        //inline .handle => {},
        //inline .shallow => {},
        inline .builtin => return .{ .from = token.one, .till = token.two },
        //inline .reference => {},
        //inline .release => {},
    }
}
pub fn tok(self: *SELF, comptime value: Value, x: struct { u32, u32 }, source: lib.Source) Token {
    const rhs: comptime_int = 0; // To override in main loop and should always end up in self.extra
    const lhs = self.index_output + 1;
    const ptr: u32 = @intCast(self.extra.items.len);

    defer self.index_output += 1;

    const one: u32, const two: u32 = switch (value) {
        inline .variable => x,
        inline .lambda => x,
        inline .apply => blk: {
            const data = &[_]u32{lhs, ptr, rhs};
            self.extra.appendSliceAssumeCapacity(data[2..]);
            break :blk data[0..2].*;
        },
        inline .let => blk: {
            const data = &[_]u32{lhs, ptr, rhs, x[0], x[1]};
            self.extra.appendSliceAssumeCapacity(data[2..]);
            break :blk data[0..2].*;
        },
        //inline .binary => {},
        inline .integer => x,
        inline .string => x,
        inline .tail => .{ 0 , 0 },
        inline .cons => blk: {
            const data = &[_]u32{ptr, lhs, rhs};
            self.extra.appendSliceAssumeCapacity(data[2..]);
            break :blk data[0..2].*;
        },
        inline .vacant => .{ 0, 0 },
        inline .empty => .{ 0, 0 },
        inline .extend => blk: {
            const data = &[_]u32{lhs, ptr, rhs, x[0], x[1]};
            self.extra.appendSliceAssumeCapacity(data[2..]);
            break :blk data[0..2].*;
        },
        inline .select => x,
        inline .overwrite => .{0,0},
        //inline .tag => {},
        inline .case => blk: {
            const data = &[_]u32{lhs, ptr, rhs, x[0], x[1]};
            self.extra.appendSliceAssumeCapacity(data[2..]);
            break :blk data[0..2].*;
        },
        inline .nocases => .{0,0},
        //inline .perform => {},
        //inline .handle => {},
        //inline .shallow => {},
        inline .builtin => x,
        //inline .reference => {},
        //inline .release => {},
    };
    return .{ .value = value, .one = one, .two = two, .source = source };
}


const Value = blk: {
    var fields: [token_data.len]std.builtin.Type.EnumField = undefined;
    for (&fields, token_data, 0..) |*f, d, i| f.* = .{ .name = d.n, .value = i };
    break :blk @Type(.{ .@"enum" = .{
        .tag_type = u8,
        .fields = &fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });
};
const Token = struct {
    value: Value,
    one: u32 = 0,
    two: u32 = 0,
    source: lib.Source,
};

pub fn max_size(input: []const u8) u32 {
    const extra = 2;
    std.debug.assert(input.len < std.math.maxInt(u32) - extra);
    return @intCast(input.len + extra);
}

const Stack = struct {
    value: enum {
        apply,
        let,
        list, // All same type
        match_input,
        match_tag,
        pattern,
        record,
    },
    extra: u32,
    source: lib.Source,
};

const State = enum {
    s_z,

    s_expr,
    s_expr_apply,
    s_expr_apply_arg,
    s_expr_list,

    s_bang,
    s_lambda_arrow,
    s_lambda_param,
    s_lambda_separator,
    s_lambda_start,
    s_let,
    s_let_equal,
    s_match_pattern,
    s_match_start,
    s_record_colon,
    s_record_field,
    s_record_value,
    s_string,
};

inline fn store_str(self: *SELF, str: []const u8) struct { u32, u32 } {
    self.strings.appendSliceAssumeCapacity(str);
    defer self.cursor_string = @intCast(self.strings.items.len);
    return .{ self.cursor_string, @intCast(self.strings.items.len) };
}

inline fn state_after_expr(self: *SELF) State {
    if (self.buffer.getLastOrNull()) |token| switch (token.value) {
        .apply => return .s_expr_apply_arg,
        .let => {
            _ = self.buffer.pop();
            reflect(.let, true, undefined, self.extra.items[token.extra..]).rhs.* = self.index_output + 1;
            return .s_expr;
        },
        .list => {
            return .s_expr_list;
        },
        .match_input => {
            _ = self.buffer.pop();
            reflect(.apply, true, undefined, self.extra.items[token.extra..]).lhs.* = self.index_output + 1;
            return .s_match_start;
        },
        .match_tag => {
            _ = self.buffer.pop();
            reflect(.case, true, undefined, self.extra.items[token.extra..]).rhs.* = self.index_output + 1;
            return .s_match_pattern;
        },
        .pattern => @panic("@TODO: pattern"),
        .record => return .s_record_value,
    } else return .s_z;
}

pub fn next(self: *SELF, source: []const u8, input: lexer.Token) !?Token {
    const token_src = input.source.to_str(source);

    //std.debug.print("{s} ", .{@tagName(input.value)});
    //for (self.buffer.items) |x| std.debug.print("{s} -> {d} ", .{@tagName(x.value), x.extra});
    //std.debug.print("\n", .{});

    sw: switch (self.state) {
        .s_z => switch (input.value) {
            .whitespace => {},
            else => return error.IREndedEarly,
        },
        .s_expr => switch (input.value) {
            .whitespace => {},
            .quote => {
                self.state = .s_string;
                self.cursor_source = input.source.till; // after opening quote
            },
            .ident => {
                if (std.mem.eql(u8, "let", token_src)) {
                    self.buffer.appendAssumeCapacity(.{ .value = .let, .extra = @intCast(self.extra.items.len), .source = input.source });
                    self.state = .s_let;
                } else if (std.mem.eql(u8, "match", token_src)) {
                    self.buffer.appendAssumeCapacity(.{ .value = .match_input, .extra = @intCast(self.extra.items.len), .source = input.source });
                    return self.tok(.apply, .{self.index_output + 1, 0}, input.source);
                } else {
                    // @TODO: Check if variable is defined by let?
                    self.state = self.state_after_expr();
                    return self.tok(.variable, self.store_str(token_src), input.source);
                }
            },

            .square_l => {
                self.state = .s_expr_list;
                self.buffer.appendAssumeCapacity(.{ .value = .list, .extra = @intCast(self.extra.items.len), .source = input.source});
                return self.tok(.cons, .{self.index_output, 0}, input.source);
            },
            .number => {
                self.state = self.state_after_expr();
                return self.tok(.integer, .{0, 0}, input.source);
            },

            .curly_l => {
                self.state = .s_record_field;
                self.buffer.appendAssumeCapacity(.{ .value = .record, .extra = @intCast(self.extra.items.len), .source = input.source });
            },

            .bang => self.state = .s_bang,
            else => return error.IRTODO,
        },
        .s_expr_apply => {
            switch (input.value) {
                .paren_r => {
                    if (self.buffer.pop()) |last| switch (last.value) {
                        .apply => self.state = self.state_after_expr(),
                        .let, .list, .match_input, .match_tag, .record, .pattern => return error.IRMistmatchedBrackets,
                    } else return error.IRTODO;
                },
                else => continue :sw .s_expr,
            }
        },
        .s_expr_apply_arg => switch (input.value) {
            .whitespace => {},
            .comma => self.state = .s_expr_apply,
            .paren_r => continue :sw .s_expr_apply,
            else => return error.IRNeedCommaAfterArgument,
        },
        .s_expr_list => switch (input.value) {
            .comma => {
                if (self.buffer.pop()) |last| switch (last.value) {
                    .list => {
                        self.buffer.appendAssumeCapacity(.{ .value = .list, .extra = @intCast(self.extra.items.len), .source = input.source});
                        reflect(.cons, true, undefined, self.extra.items[last.extra..]).rhs.* = self.index_output;
                        return self.tok(.cons, .{0, 0}, input.source);
                    },
                    .apply, .let, .match_input, .match_tag, .record, .pattern => return error.IRMistmatchedBrackets,
                } else return error.IRTODO;
            },
            .square_r => {
                if (self.buffer.pop()) |last| switch (last.value) {
                    .list => {
                        self.state = self.state_after_expr();
                        reflect(.cons, true, undefined, self.extra.items[last.extra..]).rhs.* = self.index_output;
                        return self.tok(.tail, .{0, 0}, input.source);
                    },
                    .apply, .let, .match_input, .match_tag, .record, .pattern => return error.IRMistmatchedBrackets,
                } else return error.IRTODO;
            },
            .dot2 => {
                // @TODO: not sure how to handle this yet
                return self.tok(.overwrite, .{0, 0}, input.source);
            },
            else => continue :sw .s_expr,
        },

        .s_let => switch (input.value) {
            .whitespace => {},
            .ident => {
                self.state = .s_let_equal;
                return self.tok(.let, self.store_str(token_src), input.source);
            },
            .curly_l => @panic("@TODO: destructure record"),
            else => return error.IRLetMissingLabel,
        },
        .s_let_equal => switch (input.value) {
            .whitespace => {},
            .equal => {
                self.state = .s_expr;
            },
            else => return error.IRLetMissingEqual,
        },

        .s_bang => switch (input.value) {
            .call => {
                self.state = .s_expr_apply;
                self.buffer.appendAssumeCapacity(.{ .value = .apply, .extra = @intCast(self.extra.items.len), .source = input.source});
                return self.tok(.apply, self.store_str(token_src[0..token_src.len - 1]), input.source);
            },
            else => return error.IRBangExpectingFunctionCall,
        },

        .s_record_field => switch (input.value) {
            .whitespace => {},
            .ident => {
                self.state = .s_record_colon;
                return self.tok(.extend, self.store_str(token_src), input.source);
            },
            .dot2 => {
                self.state = .s_expr;
                return self.tok(.overwrite, .{0, 0}, input.source);
            },
            .curly_r => continue :sw .s_record_value,
            else => return error.IRTODO_field,
        },
        .s_record_colon => switch (input.value) {
            .whitespace => {},
            .colon => self.state = .s_expr,
            else => return error.IRTODO_field_colon,
        },
        .s_record_value => switch (input.value) {
            .whitespace => {},
            .comma => self.state = .s_record_field,
            .curly_r => {
                if (self.buffer.pop()) |last| switch (last.value) {
                    .record => {
                        self.state = self.state_after_expr();
                        return self.tok(.empty, .{0, 0}, input.source);
                    },
                    .apply, .let, .list, .match_input, .match_tag, .pattern => return error.IRMistmatchedBrackets,
                } else return error.IRTODO;
            },
            else => return error.IRTODO_record_value,
        },

        .s_match_start => switch (input.value) {
            .whitespace => {},
            .curly_l => {
                self.state = .s_match_pattern;
                self.buffer.appendAssumeCapacity(.{ .value = .match_tag, .extra = @intCast(self.extra.items.len), .source = input.source });
            },
            //.curly_l => {},
            //.ident => {},
            else => return error.IRMatchNotATag,
            //else => return .{ .value = .vacant, .source = input.source },
        },
        .s_match_pattern => switch (input.value) {
            .whitespace => {},
            //.curly_l => {},
            //.ident => {},
            .tag => {
                self.state = .s_lambda_start;
                self.buffer.appendAssumeCapacity(.{ .value = .match_tag, .extra = @intCast(self.extra.items.len), .source = input.source});
                //reflect(.match_tag, true, undefined, self.extra.items[last.extra..]).rhs.* = self.index_output;
                //std.debug.print("asdfasdf {s}\n", .{token_src});
                return self.tok(.case, self.store_str(token_src), input.source);
            },
            .curly_r => {
                if (self.buffer.pop()) |last| switch (last.value) {
                    .match_tag => {
                        self.state = self.state_after_expr();
                        return self.tok(.nocases, .{0, 0}, input.source);
                    },
                    .apply, .let, .list, .match_input, .pattern, .record => return error.IRMistmatchedBrackets,
                } else return error.IRTODO;
            },
            else => return error.IRMatchNotATag,
        },
        //.s_match_record => {},
        //.s_match_list => {},


        .s_lambda_start => switch (input.value) {
            .whitespace => {},
            .paren_l => self.state = .s_lambda_param,
            else => return error.IRTODO,
        },
        .s_lambda_param => switch (input.value) {
            .whitespace => {},
            .ident => {
                self.state = .s_lambda_separator;
                return self.tok(.lambda, self.store_str(token_src), input.source);
            },
            else => return error.IRTODO,
        },
        .s_lambda_separator => switch (input.value) {
            .whitespace => {},
            .comma => self.state = .s_lambda_param,
            .paren_r => self.state = .s_lambda_arrow,
            else => return error.IRTODO,
        },
        .s_lambda_arrow => switch (input.value) {
            .whitespace => {},
            .arrow => {
                //self.buffer.appendAssumeCapacity(.{ .value = .apply, .source = input.source});
                self.state = .s_expr;
            },
            else => return error.IRTODO,
        },
        
        .s_string => switch (input.value) {
            .skip => {},
            .string => {
                self.strings.appendSliceAssumeCapacity(token_src);
            },
            .byte => {
                std.debug.assert(2 == token_src.len);
                const byte = hexadecimal_parse(2, u8, token_src[0..2].*);
                //std.debug.print("byte_str {s} '{b}'\n", .{token_src, byte});
                self.strings.appendAssumeCapacity(byte);
            },
            .unicode => {
                // 10FFFF is the max code point (u21)
                // FFFFFF is the max possible input (u24)
                if (token_src.len > 6) return error.IRUnicodeCodePointTooLong;
                var byte_str: [6]u8 = @splat('0');
                @memcpy(byte_str[6 - token_src.len .. 6], token_src);

                const value = hexadecimal_parse(6, u24, byte_str);
                // Same error as std.unicode.utf8Encode
                const code_point: u21 = if (value < 0x110000) @intCast(value) else return error.CodepointTooLarge;

                var bytes: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(code_point, &bytes) catch |err| switch (err) {
                    error.CodepointTooLarge => unreachable,
                    else => return err,
                };
                self.strings.appendSliceAssumeCapacity(bytes[0..len]);
            },

            .quote => {
                self.state = self.state_after_expr();
                const map = lib.Source{ .from = self.cursor_source, .till = input.source.from }; // within quotes
                defer self.cursor_string = @intCast(self.strings.items.len);
                return self.tok(.nocases, .{self.cursor_string, @intCast(self.strings.items.len)}, map);
            },
            else => unreachable,
        },
    }

    return null;
}

pub fn done(self: *SELF) !Token {
    _ = self;
    return .{ .value = .variable, .one = 0, .two= 0, .source = .{ .from = 0, .till = 0 } };
}

pub fn parse(allocator: std.mem.Allocator, source: []const u8, input: []lexer.Token) ![]Token {
    var iter = SELF{
        .balance = try std.ArrayList(Value).initCapacity(allocator, input.len / 2 + 1),
        .strings = try std.ArrayList(u8).initCapacity(allocator, input.len),
        .buffer = try std.ArrayList(Stack).initCapacity(allocator, input.len),
        .extra = try std.ArrayList(u32).initCapacity(allocator, input.len),
    };
    var output = try std.ArrayList(Token).initCapacity(allocator, input.len);

    for (input) |lexeme| {
        const maybe = iter.next(source, lexeme) catch |err| {
            std.debug.print("{any} {!} {s} '{s}'\n", .{ iter.state, err, @tagName(lexeme.value), lexeme.source.to_str(source) });
            std.process.exit(1);
        };
        //if (maybe) |token| std.debug.print("Parsing: {any} '{s}' '{s}'\n", .{iter.state, lexeme.source.to_str(source), @tagName(token.value)});
        if (maybe) |token| output.appendAssumeCapacity(token);
    }
    _ = try iter.done();

    std.debug.print("ended on state {any}\n", .{ iter.state });
    for (iter.buffer.items) |x| {
        std.debug.print("  {any} {s}\n", .{ x.value, x.source.to_str(source) });
    }

    var index: u32 = 0;
    for (0.., output.items) |i, x| {
        std.debug.print("{d} ", .{i});
        switch (x.value) {
            .let => {
                const data = reflect(.let, false, x, iter.extra.items);
                std.debug.print("{s} '{s}' -> {d}\n", .{ @tagName(x.value), data.ident.to_str(iter.strings.items), data.rhs });
            },
            .cons => {
                const data = reflect(.cons, false, x, iter.extra.items);
                std.debug.print("{s} -> {d} {d}<-{d}\n", .{ @tagName(x.value), data.rhs, x.one, iter.extra.items[x.one] });
            },
            .extend => {
                const data = reflect(.extend, false, x, iter.extra.items);
                std.debug.print("{s} '{s}'\n", .{ @tagName(x.value), data.label.to_str(iter.strings.items) });
                index += 1;
            },
            .lambda, .variable => {
                std.debug.print("{s} '{s}'\n", .{ @tagName(x.value), iter.strings.items[x.one..x.two] });
                index += 1;
            },
            .string => {
                std.debug.print("{s} '{s}' '{s}'\n", .{ @tagName(x.value), iter.strings.items[x.one..x.two], x.source.to_str(source) });
            },
            .apply => {
                const data = reflect(.apply, false, x, iter.extra.items);
                std.debug.print("apply({d}, {d})\n", .{data.lhs, data.rhs});
            },
            else => std.debug.print("{s} '{s}'\n", .{ @tagName(x.value), x.source.to_str(source) }),
        }
    }
    //std.debug.print("===\n{s}\n===\n", .{iter.strings.items});

    var stack = try std.ArrayList(struct {u32, u32}).initCapacity(allocator, input.len);
    // Depth-first expansion (FILO: pop in order, push in reverse order)
    stack.appendAssumeCapacity(.{0, 0});
    while (stack.pop()) |x| {
        const idx, const padding = x;
        const token = output.items[idx];
        for (0..padding) |_| std.debug.print("  ", .{});

        switch (token.value) {
            .let => {
                const data = reflect(.let, false, token, iter.extra.items);
                std.debug.print("{d} let({s} = {d}) then {d}\n", . {idx, data.ident.to_str(iter.strings.items), data.lhs, data.rhs});
                stack.appendAssumeCapacity(.{data.rhs, padding + 1});
                stack.appendAssumeCapacity(.{data.lhs, padding + 1});
            },
            .cons => { // @TODO: This adds four nodes, but we only use two nodes
                const data = reflect(.cons, false, token, iter.extra.items);

                std.debug.print("{d} call\n", . {idx});
                for (0..padding) |_| std.debug.print("  ", .{});
                std.debug.print("  {d} call\n", .{idx});
                for (0..padding) |_| std.debug.print("  ", .{});
                std.debug.print("    {d} cons\n", .{idx});
                stack.appendAssumeCapacity(.{data.rhs, padding + 1});
                stack.appendAssumeCapacity(.{data.lhs, padding + 2});
            },
            .integer => {
                std.debug.print("{d} {s}\n", . {idx, token.source.to_str(source)});
            },
            .extend => {
                const data = reflect(.extend, false, token, iter.extra.items);

                std.debug.print("{d} call {d} {d}\n", . {idx, data.lhs, data.rhs});
                for (0..padding) |_| std.debug.print("  ", .{});
                std.debug.print("  {d} call\n", .{idx});
                for (0..padding) |_| std.debug.print("  ", .{});
                std.debug.print("    {d} extend({s})\n", . {idx, token.source.to_str(source)});
                //stack.appendAssumeCapacity(.{data.rhs, padding + 1});
                stack.appendAssumeCapacity(.{data.lhs, padding + 2});
            },
            .apply => {
                const data = reflect(.apply, false, token, iter.extra.items);
                std.debug.print("{d} call({d}, {d})\n", .{idx, data.lhs, data.rhs});
                stack.appendAssumeCapacity(.{data.rhs, padding + 1});
                stack.appendAssumeCapacity(.{data.lhs, padding + 1});
            },
            .case => {
                const data = reflect(.case, false, token, iter.extra.items);

                std.debug.print("{d} call\n", . {idx});
                for (0..padding) |_| std.debug.print("  ", .{});
                std.debug.print("  {d} call\n", .{idx});
                for (0..padding) |_| std.debug.print("  ", .{});
                std.debug.print("    {d} case ({s})\n", .{idx, data.tag.to_str(iter.strings.items)});
                stack.appendAssumeCapacity(.{data.rhs, padding + 1});
                stack.appendAssumeCapacity(.{data.lhs, padding + 2});
            },
            else => {
                std.debug.print("{d} {s}\n", .{idx, @tagName(token.value)});
            },
        }
    }


    return output.items;
}

// @TODO: add tests for this
// https://lemire.me/blog/2019/04/17/parsing-short-hexadecimal-strings-efficiently/
// We know that it must be '0'..'9', 'a'..'f', 'A'..'F' from lex step
inline fn hexadecimal_parse(len: comptime_int, T: type, input: [len]u8) T {
    const conversion = comptime blk: {
        var buf: ['f' + 1]u8 = undefined;
        for (0..10) |i| buf['0' + i] = i;
        for (0..6) |i| buf['A' + i] = 10 + i;
        for (0..6) |i| buf['a' + i] = 10 + i;
        break :blk buf;
    };
    var ret: T = 0;
    inline for (0..len) |i| {
        const shift = comptime i * 4;
        const to_add: T = conversion[input[len - 1 - i]];
        ret += to_add << shift;
    }
    return ret;
}

state: State = .s_expr,
balance: std.ArrayList(Value),
strings: std.ArrayList(u8),
buffer: std.ArrayList(Stack),
extra: std.ArrayList(u32),
cursor_string: u32 = 0,
cursor_source: u32 = 0,
index_output: u32 = 0,
