const std = @import("std");
const Peekable = @import("peekable.zig").Peekable;
pub const tokenizer = @import("tokenizer.zig");

pub const Error = error{
    UnexpectedSyntax,
    EOF,
    ExpectedModule,
    ExpectedString,
};

pub const Ast = union(enum) {
    module: Module,
    go: Go,
    toolchain: Toolchain,
    require: Require,
    replace: Replace,
    exclude: Exclude,
    retract: Retract,
    retract_range: RetractRange,
    block_start: BlockStart,
    block_end: BlockEnd,
    comment: Comment,
};

pub const Module = struct {
    path: []const u8,
    comment: ?[]const u8 = null,

    fn parse(comptime T: type, it: *T) Error!Ast {
        const path = try parseString(T, it);
        const comment = try parseRestOfLine(T, it);
        return .{ .module = Module{ .path = path, .comment = comment } };
    }
};

pub const Go = struct {
    version: []const u8,
    comment: ?[]const u8 = null,

    fn parse(comptime T: type, it: *T) Error!Ast {
        const version = try parseString(T, it);
        const comment = try parseRestOfLine(T, it);
        return .{ .go = Go{ .version = version, .comment = comment } };
    }
};

pub const Toolchain = struct {
    name: []const u8,
    comment: ?[]const u8 = null,

    fn parse(comptime T: type, it: *T) Error!Ast {
        const name = try parseString(T, it);
        const comment = try parseRestOfLine(T, it);
        return .{ .toolchain = Toolchain{ .name = name, .comment = comment } };
    }
};

pub const BlockType = enum {
    require,
};

pub const BlockStart = struct {
    type: BlockType,
    comment: ?[]const u8 = null,

    fn parse(comptime T: type, bt: BlockType, it: *T) Error!Ast {
        const comment = try parseRestOfLine(T, it);
        return .{ .block_start = .{ .comment = comment, .type = bt } };
    }
};

pub const BlockEnd = struct {
    type: BlockType,
    comment: ?[]const u8 = null,

    fn parse(comptime T: type, bt: BlockType, it: *T) Error!Ast {
        const comment = try parseRestOfLine(T, it);
        return .{ .block_end = .{ .comment = comment, .type = bt } };
    }
};

pub const Require = struct {
    path: []const u8,
    version: []const u8,
    comment: ?[]const u8 = null,

    fn parse(comptime T: type, it: *T) Error!Ast {
        const path = try parseString(T, it);
        const version = try parseString(T, it);
        const comment = try parseRestOfLine(T, it);
        return .{
            .require = Require{
                .path = path,
                .version = version,
                .comment = comment,
            },
        };
    }
};

pub const Replace = struct {
    path: []const u8,
    version: ?[]const u8,

    replacement_path: []const u8,
    replacement_version: ?[]const u8,

    comment: ?[]const u8 = null,

    fn parse(comptime T: type, it: *T) Error!Ast {
        var replace: Replace = undefined;
        replace.path = try parseString(T, it);

        const maybeVersion: tokenizer.Token = it.next() orelse return Error.EOF;
        switch (maybeVersion) {
            .string => |str| {
                replace.version = str;
                const next = it.next() orelse return Error.EOF;
                if (next != .@"=>") return Error.UnexpectedSyntax;
            },
            .@"=>" => {
                replace.version = null;
            },
            else => return Error.UnexpectedSyntax,
        }

        replace.replacement_path = try parseString(T, it);

        replace.replacement_version = null;
        if (it.peek()) |token| {
            if (token == .string) {
                _ = it.next();
                replace.replacement_version = token.string;
            }
        }

        replace.comment = try parseRestOfLine(T, it);

        return .{ .replace = replace };
    }
};

pub const Exclude = struct {
    path: []const u8,
    version: []const u8,
    comment: ?[]const u8 = null,

    fn parse(comptime T: type, it: *T) Error!Ast {
        return .{ .exclude = Exclude{
            .path = try parseString(T, it),
            .version = try parseString(T, it),
            .comment = try parseRestOfLine(T, it),
        } };
    }
};

pub const Retract = struct {
    version: []const u8,
    comment: ?[]const u8 = null,

    fn parse(comptime T: type, it: *T) Error!Ast {
        const retract = Retract{
            .version = try parseString(T, it),
            .comment = try parseRestOfLine(T, it),
        };

        if (std.mem.startsWith(u8, retract.version, "[") and
            std.mem.endsWith(u8, retract.version, "]"))
        {
            const versions = retract.version[1 .. retract.version.len - 1];
            var split = std.mem.splitScalar(u8, versions, ',');
            const low = split.next() orelse return Error.UnexpectedSyntax;
            const high = split.next() orelse return Error.UnexpectedSyntax;
            if (split.next()) |_| {
                return Error.UnexpectedSyntax;
            }

            return .{ .retract_range = RetractRange{
                .version_low = low,
                .version_high = high,
                .comment = retract.comment,
            } };
        }
        return .{ .retract = retract };
    }
};

pub const RetractRange = struct {
    version_low: []const u8,
    version_high: []const u8,
    comment: ?[]const u8 = null,
};

pub const Comment = struct {
    comment: []const u8,

    fn parse(comptime T: type, comment: []const u8, it: *T) Error!Ast {
        const token = it.next() orelse return Error.EOF;
        if (token != .newline) {
            return Error.UnexpectedSyntax;
        }

        return .{ .comment = Comment{ .comment = comment } };
    }
};

pub const AstIter = struct {
    const Self = @This();

    const State = enum {
        require_block,
        top_level,
    };

    it: Peekable(tokenizer.Token, tokenizer.Iterator),
    state: State,

    pub fn init(bytes: []const u8) Self {
        return .{
            .state = .top_level,
            .it = Peekable(tokenizer.Token, tokenizer.Iterator).init(tokenizer.Iterator.init(bytes)),
        };
    }

    pub fn next(self: *Self) Error!?Ast {
        const T = @TypeOf(self.it);
        const first = self.it.peek() orelse return null;
        switch (self.state) {
            .top_level => {
                _ = self.it.next();
                switch (first) {
                    .newline => return try self.next(),
                    .module => return try Module.parse(T, &self.it),
                    // .module => return .{ .module = try autoImplParse(Module, T)(&self.it) },
                    .go => return try Go.parse(T, &self.it),
                    .toolchain => return try Toolchain.parse(T, &self.it),
                    .require => {
                        const token = self.it.peek();
                        if (token) |ast| {
                            if (ast == .block_start) {
                                _ = self.it.next();
                                self.state = .require_block;
                                return try BlockStart.parse(T, .require, &self.it);
                            }
                        }

                        return try Require.parse(T, &self.it);
                    },
                    .comment => |str| return try Comment.parse(T, str, &self.it),
                    .replace => return try Replace.parse(T, &self.it),
                    .exclude => return try Exclude.parse(T, &self.it),
                    .retract => return try Retract.parse(T, &self.it),
                    else => std.debug.panic("unimplemented: {s}\n", .{@tagName(first)}),
                }
            },
            .require_block => {
                switch (first) {
                    .block_end => {
                        _ = self.it.next();
                        self.state = .top_level;
                        return try BlockEnd.parse(T, .require, &self.it);
                    },
                    .string => return try Require.parse(T, &self.it),
                    else => |other| {
                        std.debug.print("expected block end or string, got: {}\n", .{other});
                        return Error.UnexpectedSyntax;
                    },
                }
            },
        }
    }

    fn takeUntil(self: *Self, comptime end: anytype) !void {
        while (true) {
            const t = self.it.next() orelse return Error.EOF;
            if (t != end) {
                continue;
            }

            return;
        }
    }
};

fn parseString(comptime T: type, it: *T) Error![]const u8 {
    const string: tokenizer.Token = it.next() orelse return Error.EOF;
    if (string != .string) {
        return Error.ExpectedString;
    }

    return string.string;
}

fn parseRestOfLine(comptime T: type, it: *T) Error!?[]const u8 {
    const token: tokenizer.Token = it.next() orelse return null;
    switch (token) {
        .newline => return null,
        .comment => |comment| {
            const maybeNewline: ?tokenizer.Token = it.next();
            if (maybeNewline) |newline| {
                if (newline != .newline) {
                    return Error.UnexpectedSyntax;
                }
            }
            return comment;
        },
        else => return Error.UnexpectedSyntax,
    }
}

fn autoImplParse(comptime T: type, comptime I: type) fn (it: *I) Error!T {
    const type_info = @typeInfo(T);

    const st = switch (type_info) {
        .Struct => |st| st,
        else => @compileError("only structs are supported"),
    };

    return struct {
        fn parse(it: *I) Error!T {
            var t: T = undefined;
            comptime var extra_optionals: usize = 0;
            inline for (st.fields) |field| {
                switch (field.type) {
                    []const u8 => {
                        @field(t, field.name) = try parseString(I, it);
                    },
                    ?[]const u8 => comptime {
                        if (!std.mem.eql(u8, field.name, "comment")) {
                            extra_optionals += 1;
                        }
                    },
                    else => {
                        @compileLog("unsupported type", field.type);
                        @compileError("unsupported type");
                    },
                }
            }

            if (extra_optionals > 0) {
                @compileError("expected only one optional, comment");
            }

            t.comment = try parseRestOfLine(I, it);

            return t;
        }
    }.parse;
}

const testing = std.testing;

test "module" {
    {
        const input = "module abcd";
        const want = [_]Ast{.{ .module = Module{ .path = "abcd" } }};
        try assert(input, &want);
    }

    {
        const input = "module abcd // comment";
        const want = [_]Ast{.{ .module = Module{ .path = "abcd", .comment = "// comment" } }};
        try assert(input, &want);
    }
}

test "go" {
    {
        const input = "go v1.20";
        const want = [_]Ast{.{ .go = Go{ .version = "v1.20" } }};
        try assert(input, &want);
    }

    {
        const input = "go v1.20 // comment";
        const want = [_]Ast{.{ .go = Go{ .version = "v1.20", .comment = "// comment" } }};
        try assert(input, &want);
    }
}

test "toolchain" {
    {
        const input = "toolchain v1.22.0";
        const want = [_]Ast{.{ .toolchain = Toolchain{ .name = "v1.22.0" } }};
        try assert(input, &want);
    }

    {
        const input = "toolchain v1.22.0 // a comment";
        const want = [_]Ast{.{ .toolchain = Toolchain{ .name = "v1.22.0", .comment = "// a comment" } }};
        try assert(input, &want);
    }
}

test "require" {
    {
        const input = "require abcd.com v1";
        const want = [_]Ast{.{ .require = Require{ .path = "abcd.com", .version = "v1", .comment = null } }};
        try assert(input, &want);
    }

    {
        const input = "require abcd.com v1\n";
        const want = [_]Ast{.{ .require = Require{ .path = "abcd.com", .version = "v1", .comment = null } }};
        try assert(input, &want);
    }

    {
        const input = "require abcd.com v1 // comment";
        const want = [_]Ast{.{ .require = Require{ .path = "abcd.com", .version = "v1", .comment = "// comment" } }};
        try assert(input, &want);
    }

    {
        const input = "require (\n\tabcd.com v1\n)";
        const want = [_]Ast{} ++
            .{.{ .block_start = BlockStart{ .type = .require, .comment = null } }} ++
            .{.{ .require = Require{ .path = "abcd.com", .version = "v1", .comment = null } }} ++
            .{.{ .block_end = BlockEnd{ .type = .require, .comment = null } }};
        try assert(input, &want);
    }

    {
        const input = "require (\n\tabcd.com v1 // a comment\n)\n";
        const want = [_]Ast{} ++
            .{.{ .block_start = BlockStart{ .type = .require, .comment = null } }} ++
            .{.{ .require = Require{ .path = "abcd.com", .version = "v1", .comment = "// a comment" } }} ++
            .{.{ .block_end = BlockEnd{ .type = .require, .comment = null } }};
        try assert(input, &want);
    }
}

test "replace" {
    {
        const input = "replace abcd => dcbd";
        const want = [_]Ast{.{ .replace = Replace{ .path = "abcd", .version = null, .replacement_path = "dcbd", .replacement_version = null } }};
        try assert(input, &want);
    }

    {
        const input = "replace abcd v1 => dcbd";
        const want = [_]Ast{.{ .replace = Replace{ .path = "abcd", .version = "v1", .replacement_path = "dcbd", .replacement_version = null } }};
        try assert(input, &want);
    }

    {
        const input = "replace abcd => dcbd v1";
        const want = [_]Ast{.{ .replace = Replace{ .path = "abcd", .version = null, .replacement_path = "dcbd", .replacement_version = "v1" } }};
        try assert(input, &want);
    }

    {
        const input = "replace abcd v1 => dcbd v2";
        const want = [_]Ast{.{ .replace = Replace{ .path = "abcd", .version = "v1", .replacement_path = "dcbd", .replacement_version = "v2" } }};
        try assert(input, &want);
    }
}

test "exclude" {
    {
        const input = "exclude abcd v1.0.0";
        const want = [_]Ast{.{ .exclude = Exclude{ .path = "abcd", .version = "v1.0.0" } }};
        try assert(input, &want);
    }

    {
        const input = "exclude abcd v1.0.0 // a comment";
        const want = [_]Ast{.{ .exclude = Exclude{ .path = "abcd", .version = "v1.0.0", .comment = "// a comment" } }};
        try assert(input, &want);
    }
}

test "retract" {
    // retract [version-low,version-high] // rationale
    {
        const input = "retract v1.0.0";
        const want = [_]Ast{.{ .retract = Retract{ .version = "v1.0.0" } }};
        try assert(input, &want);
    }

    {
        const input = "retract v1.0.0 // a comment";
        const want = [_]Ast{.{ .retract = Retract{ .version = "v1.0.0", .comment = "// a comment" } }};
        try assert(input, &want);
    }

    {
        const input = "retract [v1.0.0,v2.0.0]";
        const want = [_]Ast{.{ .retract_range = RetractRange{ .version_low = "v1.0.0", .version_high = "v2.0.0" } }};
        try assert(input, &want);
    }

    {
        const input = "retract [v1.0.0,v2.0.0] // a comment";
        const want = [_]Ast{.{ .retract_range = RetractRange{ .version_low = "v1.0.0", .version_high = "v2.0.0", .comment = "// a comment" } }};
        try assert(input, &want);
    }
}

test "real world" {
    const file =
        \\module example.com/user
        \\
        \\go 1.22
        \\
        \\// comment before replace
        \\replace cloud.google.com/go/bigtable => cloud.google.com/go/bigtable v1.20.0
        \\
        \\require (
        \\	cloud.google.com/go/bigtable v1.21.0
        \\	cloud.google.com/go/datastore v1.15.0
        \\	cloud.google.com/go/pubsub v1.36.2
        \\)
        \\
        \\require (
        \\	cloud.google.com/go/bigtable v1.21.0 // indirect
        \\	cloud.google.com/go/datastore v1.15.0 // indirect
        \\	cloud.google.com/go/pubsub v1.36.2 // indirect
        \\)
        \\
    ;

    const want = [_]Ast{} ++
        .{.{ .module = Module{ .path = "example.com/user" } }} ++
        .{.{ .go = Go{ .version = "1.22" } }} ++
        .{.{ .comment = Comment{ .comment = "// comment before replace" } }} ++
        .{.{
        .replace = Replace{
            .path = "cloud.google.com/go/bigtable",
            .version = null,
            .replacement_path = "cloud.google.com/go/bigtable",
            .replacement_version = "v1.20.0",
        },
    }} ++
        .{.{ .block_start = BlockStart{ .type = .require } }} ++
        .{.{ .require = Require{ .path = "cloud.google.com/go/bigtable", .version = "v1.21.0" } }} ++
        .{.{ .require = Require{ .path = "cloud.google.com/go/datastore", .version = "v1.15.0" } }} ++
        .{.{ .require = Require{ .path = "cloud.google.com/go/pubsub", .version = "v1.36.2" } }} ++
        .{.{ .block_end = BlockEnd{ .type = .require } }} ++
        .{.{ .block_start = BlockStart{ .type = .require } }} ++
        .{.{ .require = Require{ .path = "cloud.google.com/go/bigtable", .version = "v1.21.0", .comment = "// indirect" } }} ++
        .{.{ .require = Require{ .path = "cloud.google.com/go/datastore", .version = "v1.15.0", .comment = "// indirect" } }} ++
        .{.{ .require = Require{ .path = "cloud.google.com/go/pubsub", .version = "v1.36.2", .comment = "// indirect" } }} ++
        .{.{ .block_end = BlockEnd{ .type = .require } }};
    try assert(file, &want);
}

fn assert(text: []const u8, want_slice: []const Ast) !void {
    var it = AstIter.init(text);

    for (want_slice) |want| {
        const got = try it.next() orelse return error.EOF;

        errdefer std.debug.print("want = {}\ngot  = {}\n", .{ std.json.fmt(want, .{}), std.json.fmt(got, .{}) });

        try testing.expectEqualDeep(want, got);
    }
    try testing.expectEqual(null, try it.next());
}
