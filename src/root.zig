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

pub const ExecResult = struct {
    match_list: std.ArrayList([]const u8),

    pub fn deinit(self: ExecResult) void {
        self.match_list.deinit();
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

    fn exec(self: Regex, allocator: std.mem.Allocator, input: [:0]const u8) !ExecResult {
        const exec_result = libregex.exec(self.inner, input, self.re_nsub, 0);

        if (exec_result.exec_code != 0) {
            std.debug.print("non zero exit code = {d}\n", .{exec_result.exec_code});

            return error.ExecError;
        }

        var result = ExecResult{
            .match_list = std.ArrayList([]const u8).init(allocator),
        };

        for (exec_result.matches, 0..exec_result.n_matches) |_, i| {
            const pmatch = exec_result.matches[i];
            const start = @as(usize, @intCast(pmatch.rm_so));
            const end = @as(usize, @intCast(pmatch.rm_eo));
            const match = input[start..end];

            try result.match_list.append(match);
        }

        return result;
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

    const exec_result = try r2.exec(std.testing.allocator, "Latest version is v1.2.2");

    std.debug.print("exec result: ", .{});
    for (exec_result.match_list.items) |match| {
        std.debug.print("{s} \t", .{match});
    }
    std.debug.print("\n", .{});

    exec_result.deinit();
    iterator.deinit();
}
