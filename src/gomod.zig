const std = @import("std");
const testing = std.testing;

pub const Require = struct {
    path: []const u8,
    version: []const u8,
    comment: ?[]const u8,
};

/// replace module-path [module-version] => replacement-path [replacement-version]
pub const Replace = struct {
    module_path: []const u8,
    module_version: ?[]const u8,

    replacement_path: []const u8,
    replacement_version: ?[]const u8,
};

pub const Directive = union(enum) {
    module: []const u8,
    comment: []const u8,
    go: []const u8,
    toolchain: []const u8,
    require: Require,
    replace: Replace,

    block_start,
    block_end,

    newline,

    pub fn format(
        self: Directive,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .module => |v| try writer.print(".module {s}", .{v}),
            .comment => |v| try writer.print(".comment {s}", .{v}),
            .go => |v| try writer.print(".go {s}", .{v}),
            .toolchain => |v| try writer.print(".toolchain {s}", .{v}),
            .block_start => try writer.print(".block_start", .{}),
            .block_end => try writer.print(".block_end", .{}),
            .newline => try writer.print(".newline", .{}),
            .require => |v| {
                try writer.print(".require path={s} version={s}", .{ v.path, v.version });
                if (v.comment) |comment| {
                    try writer.print(" comment={s}", .{comment});
                }
            },
            .replace => |v| try writer.print(".replace {s} {?s} => {s} {?s}", .{ v.module_path, v.module_version, v.replacement_path, v.replacement_version }),
        }
    }
};

pub fn AstIter(comptime R: type) type {
    const State = enum { require_block, main };

    return struct {
        const Self = @This();

        buf: [256]u8 = undefined,
        state: State = .main,
        reader: R,

        pub fn init(reader: R) Self {
            return .{ .reader = reader };
        }

        pub const Error = error{
            NoToken,
            ExtraToken,
            UnexpectedToken,
        };

        pub fn next(self: *Self) !?Directive {
            const slice: []u8 = self.buf[0..];
            const line: []u8 = (try self.reader.readUntilDelimiterOrEof(slice, '\n')) orelse return null;
            const trimmed = std.mem.trim(u8, line, " \t");

            switch (self.state) {
                .main => return try self.parseMain(trimmed),
                else => return try self.parseBlock(trimmed),
            }
        }

        const module_str = "module";
        const go_str = "go";
        const toolchain_str = "toolchain";
        const require_str = "require";
        const replace_str = "replace";
        const comment_str = "//";
        // const str_to_tag = std.ComptimeStringMap(Tag, .{
        //     .{ "module", Tag.module },
        //     .{ "go", Tag.go },
        //     .{ "toolchain", Tag.toolchain },
        //     .{ "require", Tag.require },
        //     .{ "//", Tag.comment },
        // });

        fn parseMain(self: *Self, line: []const u8) !Directive {
            if (line.len == 0) {
                return .newline;
            } else if (std.mem.startsWith(u8, line, module_str)) {
                const rest = std.mem.trimLeft(u8, line[module_str.len..], " \t");
                return .{ .module = rest };
            } else if (std.mem.startsWith(u8, line, go_str)) {
                const rest = std.mem.trimLeft(u8, line[go_str.len..], " \t");
                return .{ .go = rest };
            } else if (std.mem.startsWith(u8, line, toolchain_str)) {
                const rest = std.mem.trimLeft(u8, line[toolchain_str.len..], " \t");
                return .{ .toolchain = rest };
            } else if (std.mem.startsWith(u8, line, comment_str)) {
                return .{ .comment = line };
            } else if (std.mem.startsWith(u8, line, require_str)) {
                const rest = std.mem.trimLeft(u8, line[require_str.len..], " \t");
                if (std.mem.startsWith(u8, rest, "(")) {
                    self.state = .require_block;
                    return .block_start;
                }

                const strs = try parseTwoStrings(rest, " ");
                return .{
                    .require = .{
                        .path = strs.first,
                        .version = strs.second,
                        .comment = strs.rest,
                    },
                };
            } else if (std.mem.startsWith(u8, line, replace_str)) {
                const rest = std.mem.trimLeft(u8, line[replace_str.len..], " \t");

                return .{ .replace = try parseReplace(rest) };
            } else {
                std.log.err("unexpected token: {s}", .{line});
                return Error.UnexpectedToken;
            }
        }

        fn parseBlock(self: *Self, trimmed: []const u8) !Directive {
            if (std.mem.startsWith(u8, trimmed, ")")) {
                self.state = .main;
                return .block_end;
            }

            switch (self.state) {
                .require_block => {
                    const strs = try parseTwoStrings(trimmed, " ");
                    return .{
                        .require = Require{
                            .path = strs.first,
                            .version = strs.second,
                            .comment = strs.rest,
                        },
                    };
                },
                .main => unreachable,
            }
        }

        fn parseReplace(input: []const u8) !Replace {
            const delimiter_str = "=>";

            var replace: Replace = undefined;
            var it = std.mem.tokenizeScalar(u8, input, ' ');

            replace.module_path = it.next() orelse return error.NoToken;
            const maybeDelimiter = it.next() orelse return error.NoToken;
            if (std.mem.eql(u8, maybeDelimiter, delimiter_str)) {
                replace.module_version = null;
            } else {
                replace.module_version = maybeDelimiter;
                const delimiter = it.next() orelse return error.NoToken;
                if (!std.mem.eql(u8, delimiter, delimiter_str)) {
                    std.log.err("expected delimiter but found: {s}", .{delimiter});
                    return error.UnexpectedToken;
                }
            }

            replace.replacement_path = it.next() orelse return error.NoToken;
            replace.replacement_version = it.next() orelse null;

            return replace;
        }

        const TwoStrings = struct {
            first: []const u8,
            second: []const u8,
            rest: ?[]const u8,
        };

        fn parseTwoStrings(input: []const u8, comptime delimiter: []const u8) !TwoStrings {
            const trimmed = std.mem.trim(u8, input, " \t");

            var it = if (delimiter.len == 1)
                std.mem.tokenizeScalar(u8, trimmed, delimiter[0])
            else
                std.mem.tokenizeSequence(u8, trimmed, delimiter);

            var out: [2][]const u8 = undefined;
            for (0..out.len) |i| {
                const str = it.next() orelse return Error.NoToken;
                out[i] = std.mem.trim(u8, str, " \t");
            }

            return .{
                .first = out[0],
                .second = out[1],
                .rest = if (it.rest().len > 0) it.rest() else null,
            };
        }
    };
}

test "module" {
    var stream = std.io.fixedBufferStream(
        \\ module example.com/user/repo
    );

    var ast = AstIter(@TypeOf(stream.reader())){
        .reader = stream.reader(),
    };

    const mod = (try ast.next()).?;
    try testing.expectEqualStrings("example.com/user/repo", mod.module);
    try testing.expectEqual(try ast.next(), null);
}

test "go" {
    var stream = std.io.fixedBufferStream(
        \\ module example.com/user/repo
        \\ go v1.22
    );

    var ast = AstIter(@TypeOf(stream.reader())).init(stream.reader());
    _ = (try ast.next()).?;

    const mod = (try ast.next()).?;
    try testing.expectEqualStrings("v1.22", mod.go);
    try testing.expectEqual(try ast.next(), null);
}

test "toolchain" {
    var stream = std.io.fixedBufferStream(
        \\ module example.com/user/repo
        \\ go v1.22
        \\ toolchain v1.22.42
    );

    var ast = AstIter(@TypeOf(stream.reader())).init(stream.reader());
    _ = (try ast.next()).?;
    _ = (try ast.next()).?;

    const mod = (try ast.next()).?;
    try testing.expectEqualStrings("v1.22.42", mod.toolchain);
    try testing.expectEqual(try ast.next(), null);
}

test "single require" {
    var stream = std.io.fixedBufferStream(
        \\ require example.com/user/repo v1.0.0
    );

    var ast = AstIter(@TypeOf(stream.reader())).init(stream.reader());

    const dir = (try ast.next()).?;
    try testing.expectEqualStrings("example.com/user/repo", dir.require.path);
    try testing.expectEqualStrings("v1.0.0", dir.require.version);
    try testing.expectEqual(null, dir.require.comment);
    try testing.expectEqual(null, try ast.next());
}

test "block require" {
    var stream = std.io.fixedBufferStream(
        \\require (
        \\  example.com/user/repo v1.0.0
        \\)
    );

    var ast = AstIter(@TypeOf(stream.reader())).init(stream.reader());

    try testing.expectEqual(try ast.next(), .block_start);

    const dir = (try ast.next()).?;
    try testing.expectEqualStrings("example.com/user/repo", dir.require.path);
    try testing.expectEqualStrings("v1.0.0", dir.require.version);
    try testing.expectEqual(null, dir.require.comment);

    try testing.expectEqual(.block_end, try ast.next());
    try testing.expectEqual(null, try ast.next());
}

test "mulpitle block require" {
    var stream = std.io.fixedBufferStream(
        \\require (
        \\  example.com/user/repo v1.0.0
        \\  example.com/user/repo v1.0.0
        \\  example.com/user/repo v1.0.0
        \\  example.com/user/repo v1.0.0
        \\)
    );

    var ast = AstIter(@TypeOf(stream.reader())).init(stream.reader());

    try testing.expectEqual(try ast.next(), .block_start);

    for (0..4) |_| {
        const dir = (try ast.next()).?;
        try testing.expectEqualStrings("example.com/user/repo", dir.require.path);
        try testing.expectEqualStrings("v1.0.0", dir.require.version);
        try testing.expectEqual(null, dir.require.comment);
    }

    try testing.expectEqual(try ast.next(), .block_end);
    try testing.expectEqual(try ast.next(), null);
}

test "newline" {
    var stream = std.io.fixedBufferStream(
        \\ require example.com/user/repo v1.0.0
        \\
        \\ require example.com/user/repo v1.0.0
    );

    var ast = AstIter(@TypeOf(stream.reader())).init(stream.reader());

    var dir = (try ast.next()).?;
    try testing.expectEqualStrings("example.com/user/repo", dir.require.path);
    try testing.expectEqualStrings("v1.0.0", dir.require.version);

    try testing.expectEqual(.newline, try ast.next());

    dir = (try ast.next()).?;
    try testing.expectEqualStrings("example.com/user/repo", dir.require.path);
    try testing.expectEqualStrings("v1.0.0", dir.require.version);
    try testing.expectEqual(null, dir.require.comment);

    try testing.expectEqual(null, try ast.next());
}

test "single require with comment" {
    var stream = std.io.fixedBufferStream(
        \\ require example.com/user/repo v1.0.0 // indirect
    );

    var ast = AstIter(@TypeOf(stream.reader())).init(stream.reader());

    const dir = (try ast.next()).?;
    try testing.expectEqualStrings("example.com/user/repo", dir.require.path);
    try testing.expectEqualStrings("v1.0.0", dir.require.version);
    try testing.expectEqualStrings("// indirect", dir.require.comment orelse "");

    try testing.expectEqual(null, try ast.next());
}
