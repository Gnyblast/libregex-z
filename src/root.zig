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

pub const ExecIterator = struct {
    regex: Regex,
    allocator: std.mem.Allocator,
    offset: usize,
    input: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, r: Regex, input: []const u8) !ExecIterator {
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

    pub fn deinit(self: ExecIterator) void {
        self.input.deinit();
    }

    pub fn next(self: *ExecIterator) !?ExecResult {
        if (self.offset >= self.input.items.len) {
            return null;
        }

        const input: [:0]const u8 = @ptrCast(self.input.items[self.offset..self.input.items.len]);
        const exec_result = libregex.exec(self.regex.inner, input, self.regex.re_nsub, 0);
        defer libregex.free_match_ptr(exec_result.matches);

        if (exec_result.exec_code != 0) {
            if (exec_result.exec_code == libregex.REG_NOMATCH) return null;

            return error.OutOfMemory;
        }

        var result = ExecResult{
            .match_list = std.ArrayList([]const u8).init(self.allocator),
        };

        if (exec_result.matches[0].rm_so == exec_result.matches[0].rm_eo) {
            return null;
        }

        for (exec_result.matches, 0..exec_result.n_matches) |_, i| {
            const pmatch = exec_result.matches[i];
            const start = @as(usize, @intCast(pmatch.rm_so));
            const end = @as(usize, @intCast(pmatch.rm_eo));
            const match = input[start..end];

            if (i == 0) {
                self.offset += start + 1;
            }

            try result.match_list.append(match);
        }

        return result;
    }
};

const Regex = struct {
    inner: *libregex.regex_t,
    re_nsub: c_ulonglong,

    fn init(pattern: [:0]const u8, flags: c_int) !Regex {
        const res = libregex.compile_regex(pattern, flags);
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

    fn matches(self: Regex, input: [:0]const u8) !bool {
        const result = libregex.regexec(self.inner, input, 0, null, 0);

        if (result == 0) return true;
        if (result == libregex.REG_NOMATCH) return false;

        return error.OutOfMemory;
    }

    fn getMatchIterator(self: Regex, allocator: std.mem.Allocator, input: []const u8) !MatchIterator {
        return MatchIterator.init(allocator, self, input);
    }

    fn getExecIterator(self: Regex, allocator: std.mem.Allocator, input: []const u8) !ExecIterator {
        return ExecIterator.init(allocator, self, input);
    }
};

test "matches" {
    const r = try Regex.init("^v[0-9]+.[0-9]+.[0-9]+");
    defer r.deinit();

    try expect(try r.matches("v1.2.3"));
    try expect(try r.matches("v1.22.101"));
    try expect(!try r.matches("1.2.3"));
}

test "full match iterator" {
    const r = try Regex.init("(v)([0-9]+.[0-9]+.[0-9]+)");
    defer r.deinit();

    const input: []const u8 =
        \\ The latest stable version is v2.1.0. If you are using an older verison of x then please use v1.12.2
        \\ You can also try the nightly version v2.2.0-beta-2
    ;

    var iterator = try r.getMatchIterator(std.testing.allocator, input);
    defer iterator.deinit();

    try expect(std.mem.eql(u8, "v2.1.0", iterator.next().?));
    try expect(std.mem.eql(u8, "v1.12.2", iterator.next().?));
    try expect(std.mem.eql(u8, "v2.2.0", iterator.next().?));

    try expect(iterator.next() == null);
}

test "exec iterator" {
    const r = try Regex.init("(v)([0-9]+.[0-9]+.[0-9]+)");
    defer r.deinit();

    const input: []const u8 = "Latest stable version is v1.2.2. Latest version is v1.3.0";
    var expected: []const []const u8 = undefined;
    var exec_result: ExecResult = undefined;

    var exec_iterator = try r.getExecIterator(std.testing.allocator, input);
    defer exec_iterator.deinit();

    expected = &[_][]const u8{ "v1.2.2", "v", "1.2.2" };
    exec_result = (try exec_iterator.next()).?;
    for (expected, 0..) |e, i| {
        try expect(std.mem.eql(u8, e, exec_result.match_list.items[i]));
    }
    exec_result.deinit();

    expected = &[_][]const u8{ "v1.3.0", "v", "1.3.0" };
    exec_result = (try exec_iterator.next()).?;
    for (expected, 0..) |e, i| {
        try expect(std.mem.eql(u8, e, exec_result.match_list.items[i]));
    }
    exec_result.deinit();

    try expect(try exec_iterator.next() == null);

    try expect(exec_result.match_list.items.len == expected.len);
}
