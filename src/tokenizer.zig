const std = @import("std");
const testing = std.testing;

pub const Token = union(enum) {
    module,
    go,
    toolchain,
    require,
    replace,
    exclude,
    retract,

    newline,
    block_start,
    block_end,

    @"=>",

    comment: []const u8,
    string: []const u8,

    pub fn format(
        self: Token,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .comment => |str| try writer.print(".comment = '{s}'", .{str}),
            .string => |str| try writer.print(".string = '{s}'", .{str}),
            else => try writer.print(".{s}", .{@tagName(self)}),
        }
    }
};

pub const Iterator = struct {
    const Self = @This();
    const TokenIter = std.mem.TokenIterator(u8, .any);

    token_iter: TokenIter,

    pub fn init(bytes: []const u8) Self {
        return .{
            .token_iter = TokenIter{
                .buffer = bytes,
                .delimiter = " \n\t",
                .index = 0,
            },
        };
    }

    const token_map = std.StaticStringMap(Token).initComptime(.{
        .{ "module", Token.module },
        .{ "go", Token.go },
        .{ "toolchain", Token.toolchain },
        .{ "require", Token.require },
        .{ "replace", Token.replace },
        .{ "exclude", Token.exclude },
        .{ "retract", Token.retract },

        .{ "\n", Token.newline },
        .{ "(", Token.block_start },
        .{ ")", Token.block_end },
        .{ "=>", Token.@"=>" },
    });

    pub fn next(self: *Self) ?Token {
        var token: []const u8 = undefined;
        // this allows to return .newline
        if (self.token_iter.index < self.token_iter.buffer.len and self.token_iter.buffer[self.token_iter.index] == '\n') {
            token = "\n";
        } else {
            token = self.token_iter.peek() orelse return null;
        }

        if (std.mem.startsWith(u8, token, "//")) {
            const start = self.token_iter.index;
            var i = start;
            while (i < self.token_iter.buffer.len and self.token_iter.buffer[i] != '\n') : (i += 1) {}
            const comment = self.token_iter.buffer[start..i];
            const end = i;
            self.token_iter.index += end - start;
            return .{ .comment = comment };
        }

        // allows parsing 'require('
        if (token.len > 1 and std.mem.endsWith(u8, token, "(")) {
            token = token[0 .. token.len - 1];
        }

        self.token_iter.index += token.len;

        if (token_map.get(token)) |ast| {
            return ast;
        }

        return .{ .string = token };
    }

    pub fn reset(self: *Self) void {
        self.token_iter.reset();
    }
};

fn assert(modfile: []const u8, comptime expect: []const Token) !void {
    var it = Iterator.init(modfile);
    for (expect) |want| {
        const token = it.next() orelse return error.UnexpectedEOF;
        errdefer std.debug.print("got {}, expect {}\n", .{ token, want });

        switch (want) {
            .string => |str| {
                try testing.expect(token == .string);
                try testing.expectEqualStrings(str, token.string);
            },
            .comment => |str| {
                try testing.expect(token == .comment);
                try testing.expectEqualStrings(str, token.comment);
            },
            else => {
                try testing.expectEqual(want, token);
            },
        }
    }

    try std.testing.expectEqual(null, it.next());
}

test "real world" {
    const modfile =
        \\module github.com/knightpp/modupdate
        \\
        \\go 1.21
        \\
        \\require (
        \\	github.com/koki-develop/go-fzf v0.15.0
        \\	golang.org/x/mod v0.17.0
        \\)
        \\
        \\require (
        \\	github.com/atotto/clipboard v0.1.4 // indirect
        \\	github.com/aymanbagabas/go-osc52/v2 v2.0.1 // indirect
        \\	github.com/charmbracelet/bubbles v0.16.1 // indirect
        \\)
        \\
    ;

    const expect = [_]Token{} ++
        .{ .module, .{ .string = "github.com/knightpp/modupdate" }, .newline } ++
        .{.newline} ++
        .{ .go, .{ .string = "1.21" }, .newline } ++
        .{.newline} ++
        .{ .require, .block_start, .newline } ++
        .{ .{ .string = "github.com/koki-develop/go-fzf" }, .{ .string = "v0.15.0" }, .newline } ++
        .{ .{ .string = "golang.org/x/mod" }, .{ .string = "v0.17.0" }, .newline } ++
        .{ .block_end, .newline } ++
        .{.newline} ++
        .{ .require, .block_start, .newline } ++
        .{ .{ .string = "github.com/atotto/clipboard" }, .{ .string = "v0.1.4" }, .{ .comment = "// indirect" }, .newline } ++
        .{ .{ .string = "github.com/aymanbagabas/go-osc52/v2" }, .{ .string = "v2.0.1" }, .{ .comment = "// indirect" }, .newline } ++
        .{ .{ .string = "github.com/charmbracelet/bubbles" }, .{ .string = "v0.16.1" }, .{ .comment = "// indirect" }, .newline } ++
        .{ .block_end, .newline };

    try assert(modfile, &expect);
}

test "block start without space" {
    try assert(
        "require(\n)",
        &.{ .require, .block_start, .newline, .block_end },
    );
}

test "comment" {
    try assert(
        "//test comment",
        &.{.{ .comment = "//test comment" }},
    );
    try assert(
        "// test comment",
        &.{.{ .comment = "// test comment" }},
    );
    try assert(
        "   // test comment",
        &.{.{ .comment = "// test comment" }},
    );
}

test "=>" {
    try assert(
        "=>",
        &.{.@"=>"},
    );
}

test "replace" {
    try assert(
        "replace a => b",
        &.{ .replace, .{ .string = "a" }, .@"=>", .{ .string = "b" } },
    );
}
