# Regex library for zig
This library wraps the C regex library and provides a convenient API.

Compatible with zig version `0.0.13`

## Installation
1. Run `zig fetch --save git+https://github.com/skota-io/libregex-z`
2. In your `build.zig` <br>
```zig
const regexLib = b.dependency("libregex", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("libregex", regexLib.module("libregex"));
```

## Documentation
Detailed documentation is available here: https://skota-io.github.io/libregex-z
<br>
Also see the [usage section / quick start guide](#usage--quick-start-guide)

## Usage / Quick start guide
### 1. Initialize
```zig
const libregex = @import("libregex");
const Regex = libregex.Regex;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const pattern = "(v)([0-9]+.[0-9]+.[0-9]+)";
const regex = try Regex.init(gpa.allocator(), pattern, "x");
defer regex.deinit();
```

### 2. Check if some input matches pattern
```zig
const expect = @import("std").testing.expect;

try expect(try r.matches("v1.22.101"));
try expect(!try r.matches("1.2.3"));
```

### 3. Get matches in an input
```zig
const expect = @import("std").testing.expect;

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
```

### 4. Get sub-expressions
```zig

const input: []const u8 = "Latest stable version is v1.2.2. Latest version is v1.3.0";

var exec_result: [][]const u8 = undefined;
var exec_iterator = try r.getExecIterator(input);
defer exec_iterator.deinit();

exec_result = (try exec_iterator.next()).?;
try expect(std.mem.eql(u8, exec_result[0], "v1.2.2"));
try expect(std.mem.eql(u8, exec_result[1], "v"));
try expect(std.mem.eql(u8, exec_result[2], "1.2.2"));

exec_result = (try exec_iterator.next()).?;
try expect(std.mem.eql(u8, exec_result[0], "v1.3.0"));
try expect(std.mem.eql(u8, exec_result[1], "v"));
try expect(std.mem.eql(u8, exec_result[2], "1.3.0"));

try expect(try exec_iterator.next() == null);
```


Note: If you want to know how many sub-expressions your regex has, you get it by using
```zig
regex.num_subexpressions;
```
