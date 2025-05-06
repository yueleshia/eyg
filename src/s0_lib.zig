pub const Source = struct {
    from: u32,
    till: u32,

    const Self = @This();

    pub fn to_str(self: Self, input: []const u8) []const u8 {
        return input[self.from..self.till];
    }
};
