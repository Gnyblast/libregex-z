//! This library wraps the [C regex library](https://www.gnu.org/software/libc/manual/html_node/Regular-Expressions.html) (regex.h)
//! and provides a very convinient API.
//!
//! To get started, you would have to first initialize the `Regex`.
//! The struct `Regex` is the entry point for working with regular expressions.
//!
//! Using this library you can do the following:
//!     - check if an input matches the pattern
//!     - find all matches in an input
//!     - extract sub-expressions from the matches
const std = @import("std");
const libregex = @cImport({
    @cInclude("c_src/regex_adapter.h");
});

const expect = std.testing.expect;

const MatchIterator = struct {
    regex: Regex,
    allocator: std.mem.Allocator,
    offset: usize,
    input: [:0]const u8,

    /// You wouldn't call this function. It is called internally by `Regex` struct when you call the `getMatchIterator` function.
    pub fn init(allocator: std.mem.Allocator, r: Regex, input: []const u8) !MatchIterator {
        const c_str: [:0]u8 = try std.mem.Allocator.dupeZ(allocator, u8, input);

        return .{
            .allocator = allocator,
            .input = c_str,
            .regex = r,
            .offset = 0,
        };
    }

    /// Frees the memory allocated by the `MatchIterator`
    pub fn deinit(self: MatchIterator) void {
        self.allocator.free(self.input);
    }

    /// Tries to find a match in the input and if a match is found, it returns a slice of `self.input` that contains the match.
    /// Note that `self.input` is not the same as the `input` that's passed when calling `getMatchIterator` function on the `Regex` struct.
    /// If a match is not found, it returns `null`. Returning `null` indicates the end of matches.
    pub fn next(self: *MatchIterator) error{OutOfMemory}!?[]const u8 {
        if (self.offset >= self.input.len - 1) {
            return null;
        }

        const input: [:0]const u8 = self.input[self.offset..self.input.len :0];
        var pmatch: [1]libregex.regmatch_t = undefined;
        const result = libregex.regexec(self.regex.inner, input, 1, &pmatch, 0);
        if (result != 0) {
            if (result == libregex.REG_NOMATCH) return null;

            return error.OutOfMemory;
        }
        defer {
            self.offset += @as(usize, @intCast(pmatch[0].rm_so)) + 1;
        }

        const start = @as(usize, @intCast(pmatch[0].rm_so)) + self.offset;
        const end = @as(usize, @intCast(pmatch[0].rm_eo)) + self.offset;

        return self.input[start..end];
    }
};

const ExecIterator = struct {
    regex: Regex,
    allocator: std.mem.Allocator,
    offset: usize,
    input: std.ArrayList(u8),
    exec_results: std.ArrayList(std.ArrayList([]const u8)),

    /// You wouldn't call this function. It is called internally by `Regex` struct when you call the `getExecIterator` function.
    pub fn init(allocator: std.mem.Allocator, r: Regex, input: []const u8) !ExecIterator {
        var c_str = std.ArrayList(u8).init(allocator);
        for (input) |char| try c_str.append(char);
        try c_str.append(0);

        return .{
            .allocator = allocator,
            .input = c_str,
            .regex = r,
            .offset = 0,
            .exec_results = std.ArrayList(std.ArrayList([]const u8)).init(allocator),
        };
    }

    /// Frees the memory allocated by the `ExecIterator`
    pub fn deinit(self: ExecIterator) void {
        for (self.exec_results.items) |res| {
            res.deinit();
        }
        self.exec_results.deinit();
        self.input.deinit();
    }

    /// Tries to find a match in the input and if a match is found, it returns a slice of strings.
    /// The length of the slice is always equal to (1 + number of sub expressions).
    /// To find out how many sub expressions your regex has, you can use the `num_subexpressions` field on the `Regex` struct.
    /// The first item in the slice contains the entire expression that matched the pattern.
    /// And then each item in the slice after that is a sub-expression.
    /// If a match is not found, it returns `null`. Returning `null` indicates the end of matches.
    /// Similar to the match iterator, each string is not copied in memory but rather, it is a slice of `self.input`, but note that `self.input` is not the same as the `input` that's passed when calling `getExecIterator` function on the `Regex` struct.
    /// So, `self.input` IS a copy of the `input` argument. And whenever a match is found the match returned is a slice of `self.input`.
    pub fn next(self: *ExecIterator) !?[][]const u8 {
        if (self.offset >= self.input.items.len - 1) {
            return null;
        }

        const input: [:0]const u8 = self.input.items[self.offset .. self.input.items.len - 1 :0];
        const exec_result = libregex.exec(self.regex.inner, input, self.regex.num_subexpressions, 0);
        defer libregex.free_match_ptr(exec_result.matches);

        if (exec_result.exec_code != 0) {
            if (exec_result.exec_code == libregex.REG_NOMATCH) return null;

            return error.OutOfMemory;
        }

        var match_list = std.ArrayList([]const u8).init(self.allocator);

        if (exec_result.matches[0].rm_so == exec_result.matches[0].rm_eo) {
            return null;
        }

        var offset_increment: usize = 0;

        for (exec_result.matches, 0..exec_result.n_matches) |_, i| {
            const pmatch = exec_result.matches[i];
            const start = @as(usize, @intCast(pmatch.rm_so));
            const end = @as(usize, @intCast(pmatch.rm_eo));

            const start_of_original_input = start + self.offset;
            const end_of_original_input = end + self.offset;

            const match: []const u8 = self.input.items[start_of_original_input..end_of_original_input];

            if (i == 0) {
                offset_increment = start + 1;
            }

            match_list.append(match) catch |e| {
                match_list.deinit();

                return e;
            };
        }

        self.offset += offset_increment;

        self.exec_results.append(match_list) catch |e| {
            match_list.deinit();

            return e;
        };

        return match_list.items;
    }
};

pub const Regex = struct {
    inner: *libregex.regex_t,

    /// Contains the number of sub expressions in the regex.
    /// This field is set when you call `Regex.init`
    num_subexpressions: usize,
    allocator: std.mem.Allocator,

    /// Initialize the Regex using this function.
    /// `pattern` is the regular expression you wish to compile.
    /// `flags` are used to control the way a regular expression works. Example
    pub fn init(allocator: std.mem.Allocator, pattern: []const u8, flags: c_int) !Regex {
        const c_str = try std.mem.Allocator.dupeZ(allocator, u8, pattern);
        defer allocator.free(c_str);

        const res = libregex.compile_regex(c_str, flags);
        if (res.compiled_regex == null) {
            return error.compile;
        }

        return .{
            .inner = res.compiled_regex.?,
            .num_subexpressions = @intCast(res.re_nsub),
            .allocator = allocator,
        };
    }

    /// Frees the memory allocated for the compiled regex. Note: the compiled regex is created when the `init` function is called.
    pub fn deinit(self: Regex) void {
        libregex.free_regex_t(self.inner);
    }

    /// Check if `input` matches the pattern or not.
    pub fn matches(self: Regex, input: []const u8) error{OutOfMemory}!bool {
        const c_str: [:0]u8 = try std.mem.Allocator.dupeZ(self.allocator, u8, input);
        defer self.allocator.free(c_str);

        const result = libregex.regexec(self.inner, c_str, 0, null, 0);

        if (result == 0) return true;
        if (result == libregex.REG_NOMATCH) return false;

        return error.OutOfMemory;
    }

    /// Create a `MatchIterator` by calling this function.
    /// A match iterator is used to iterate over all the matches in a given `input`.
    /// Note that match iterator does not iterate over sub expressions. If you need to get sub expressions as well then you need to use `ExecIterator`.
    /// For more details on how to use a `MatchIterator` see the documentation for the methods present on the `MatchIterator`.
    pub fn getMatchIterator(self: Regex, input: []const u8) !MatchIterator {
        return MatchIterator.init(self.allocator, self, input);
    }

    /// Create an `ExecIterator` by calling this function.
    /// An exec iterator is similar to a match iterator but an exec iterator returns the match found along with all the sub-expressions in the match.
    /// A match iterator on the other hand does not return sub-expressions.
    /// For more details on how to use an `ExecIterator` see the documentation for the methods present on the `ExecIterator`.
    pub fn getExecIterator(self: Regex, input: []const u8) !ExecIterator {
        return ExecIterator.init(self.allocator, self, input);
    }
};

test "matches" {
    const r = try Regex.init(std.testing.allocator, "^v[0-9]+.[0-9]+.[0-9]+", libregex.REG_EXTENDED);
    defer r.deinit();

    try expect(try r.matches("v1.2.3"));
    try expect(try r.matches("v1.22.101"));
    try expect(!try r.matches("1.2.3"));
}

test "full match iterator" {
    const r = try Regex.init(std.testing.allocator, "(v)([0-9]+.[0-9]+.[0-9]+)", libregex.REG_EXTENDED);
    defer r.deinit();

    const input: []const u8 =
        \\ The latest stable version is v2.1.0. If you are using an older verison of x then please use v1.12.2
        \\ You can also try the nightly version v2.2.0-beta-2
    ;

    var iterator = try r.getMatchIterator(input);
    defer iterator.deinit();

    try expect(std.mem.eql(u8, "v2.1.0", (try iterator.next()).?));
    try expect(std.mem.eql(u8, "v1.12.2", (try iterator.next()).?));
    try expect(std.mem.eql(u8, "v2.2.0", (try iterator.next()).?));

    try expect(try iterator.next() == null);
}

test "exec iterator" {
    const r = try Regex.init(std.testing.allocator, "(v)([0-9]+.[0-9]+.[0-9]+)", libregex.REG_EXTENDED);
    defer r.deinit();

    const input: []const u8 = "Latest stable version is v1.2.2. Latest version is v1.3.0";
    var expected: []const []const u8 = undefined;
    var exec_result: [][]const u8 = undefined;

    var exec_iterator = try r.getExecIterator(input);
    defer exec_iterator.deinit();

    expected = &[_][]const u8{ "v1.2.2", "v", "1.2.2" };
    exec_result = (try exec_iterator.next()).?;

    for (expected, 0..) |e, i| {
        try expect(std.mem.eql(u8, e, exec_result[i]));
    }

    expected = &[_][]const u8{ "v1.3.0", "v", "1.3.0" };
    exec_result = (try exec_iterator.next()).?;
    for (expected, 0..) |e, i| {
        try expect(std.mem.eql(u8, e, exec_result[i]));
    }

    try expect(try exec_iterator.next() == null);
}
