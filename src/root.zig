const std = @import("std");
const libregex = @cImport({
    @cInclude("c_src/regex_adapter.h");
});

const expect = std.testing.expect;

pub const MatchIterator = struct {
    regex: Regex,
    allocator: std.mem.Allocator,
    offset: usize,
    input: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, r: Regex, input: []const u8) !MatchIterator {
        var c_str = std.ArrayList(u8).init(allocator);
        for (input) |char| try c_str.append(char);
        try c_str.append(0);

        return .{
            .allocator = allocator,
            .input = c_str,
            .regex = r,
            .offset = 0,
        };
    }

    pub fn deinit(self: MatchIterator) void {
        self.input.deinit();
    }

    pub fn next(self: *MatchIterator) ?[]const u8 {
        if (self.offset >= self.input.items.len) {
            return null;
        }

        const input: [:0]const u8 = @ptrCast(self.input.items[self.offset..self.input.items.len]);
        var pmatch: [1]libregex.regmatch_t = undefined;
        const result = libregex.regexec(self.regex.inner, input, 1, &pmatch, 0);
        if (result != 0) {
            return null;
        }
        defer {
            self.offset += @as(usize, @intCast(pmatch[0].rm_so)) + 1;
        }

        const start = @as(usize, @intCast(pmatch[0].rm_so)) + self.offset;
        const end = @as(usize, @intCast(pmatch[0].rm_eo)) + self.offset;

        return self.input.items[start..end];
    }
};

const Regex = struct {
    inner: *libregex.regex_t,
    re_nsub: c_ulonglong,

    fn init(pattern: [:0]const u8) !Regex {
        const res = libregex.compile_regex(pattern, libregex.REG_EXTENDED);
        if (res.compiled_regex == null) {
            return error.compile;
        }

        return .{
            .inner = res.compiled_regex.?,
            .re_nsub = res.re_nsub,
        };
    }

    fn deinit(self: Regex) void {
        libregex.free_regex_t(self.inner);
    }

    fn matches(self: Regex, input: [:0]const u8) bool {
        return 0 == libregex.regexec(self.inner, input, 0, null, 0);
    }

    fn exec(self: Regex, input: [:0]const u8) !void {
        const match_size = 1;
        var pmatch: [match_size]libregex.regmatch_t = undefined;

        var i: usize = 0;
        var string = input;
        const expected = [_][]const u8{ "John Do", "John Foo" };
        while (true) {
            if (0 != libregex.regexec(self.inner, string, match_size, &pmatch, 0)) {
                break;
            }

            const slice = string[@as(usize, @intCast(pmatch[0].rm_so))..@as(usize, @intCast(pmatch[0].rm_eo))];

            try std.testing.expectEqualStrings(expected[i], slice);

            string = string[@intCast(pmatch[0].rm_eo)..];
            i += 1;
        }

        try std.testing.expectEqual(i, 2);
    }

    fn getMatchIterator(self: Regex, allocator: std.mem.Allocator, input: []const u8) !MatchIterator {
        return MatchIterator.init(allocator, self, input);
    }
};

test "better impl" {
    const r = try Regex.init("^v[0-9]+.[0-9]+.[0-9]+");

    try expect(r.matches("v1.2.3"));
    try expect(r.matches("v1.22.101"));
    try expect(!r.matches("1.2.3"));

    const r2 = try Regex.init("(v)([0-9]+.[0-9]+.[0-9]+)");

    try expect(r2.matches("v1.2.3"));

    std.debug.print("re_nsub = {d}\n", .{r2.re_nsub});

    var iterator = try r2.getMatchIterator(std.testing.allocator, "v1.2.3 qenrfekrnf v2.3.4 3nfjfn v1.4.5");
    var result: ?[]const u8 = iterator.next();

    while (result != null) : (result = iterator.next()) {
        std.debug.print("match = {s}\n", .{result.?});
    }

    iterator.deinit();
}
