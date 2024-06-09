const tb = @import("termbox2");
const std = @import("std");
const zf = @import("zf");

pub const Pos = struct {
    x: u32,
    y: u32,

    pub fn init(x: u32, y: u32) @This() {
        return .{ .x = x, .y = y };
    }
};

const border = struct {
    const double = struct {
        const ul_corner = "╔";
        const ll_corner = "╚";
        const ur_corner = "╗";
        const lr_corner = "╝";
        const vertical = "║";
        const horizontal = "═";
    };

    const single = struct {
        const ul_corner = "┌";
        const ll_corner = "└";
        const ur_corner = "┐";
        const lr_corner = "┘";
        const vertical = "│";
        const horizontal = "─";
    };
};

pub const Error = error{
    ScreenTooSmall,
};

pub const TextInput = struct {
    alloc: std.mem.Allocator,
    pos: Pos,
    buf: [256:0]u8,
    len: usize,
    list: *List,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, pos: Pos, list: *List) Self {
        return Self{
            .pos = pos,
            .buf = undefined,
            .list = list,
            .len = 0,
            .alloc = alloc,
        };
    }

    pub fn keyPress(self: *Self, ch: u8, key: u16) !void {
        if (self.len + 2 >= self.buf.len) return;

        if (key == tb.c.TB_KEY_BACKSPACE or key == tb.c.TB_KEY_BACKSPACE2) {
            if (self.len <= 0) return;

            self.buf[self.len] = 0;
            self.len -= 1;
        } else if (std.ascii.isAlphanumeric(ch)) {
            self.buf[self.len] = ch;
            self.len += 1;
        } else {
            return;
        }

        try self.sortList();
    }

    pub fn draw(self: *Self, screen_w: u32, screen_h: u32) !void {
        if (screen_h <= self.pos.y) return Error.ScreenTooSmall;

        var text = self.getInput();
        if (text.len > screen_w) {
            self.buf[screen_w] = 0;
            text = text[0..screen_w :0];
        }

        try tb.print(self.pos.x, self.pos.y, .cyan, .default, "> ");
        try tb.print(self.pos.x + 2, self.pos.y, .blue, .default, text);
    }

    fn getInput(self: *Self) [:0]const u8 {
        self.buf[self.len] = 0;
        return self.buf[0..self.len :0];
    }

    fn sortList(self: *Self) !void {
        self.list.current = 0;
        const input = self.getInput();

        var tokens = std.ArrayList([]const u8).init(self.alloc);
        defer tokens.deinit();

        var it = std.mem.tokenizeScalar(u8, input, ' ');
        while (it.next()) |word| {
            try tokens.append(word);
        }

        self.list.sort(tokens.items);
    }
};

pub const List = struct {
    alloc: std.mem.Allocator,
    pos: Pos,
    items: [][:0]const u8,
    sorted: [][:0]const u8,
    selected: []bool,
    current: usize,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, pos: Pos, items: []const []const u8) !Self {
        return Self{
            .alloc = alloc,
            .items = try cloneWithSentinel(alloc, items),
            .sorted = try cloneWithSentinel(alloc, items),
            .pos = pos,
            .selected = try alloc.alloc(bool, items.len),
            .current = 0,
        };
    }

    fn cloneWithSentinel(alloc: std.mem.Allocator, items: []const []const u8) ![][:0]const u8 {
        const items_c = try alloc.alloc([:0]u8, items.len);
        for (items_c, 0..) |*item_c, i| {
            const item = items[i];

            item_c.* = try alloc.allocSentinel(u8, item.len, 0);
            @memcpy(item_c.*, item);
        }
        return items_c;
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.selected);

        for (self.items) |value| {
            self.alloc.free(value);
        }
        self.alloc.free(self.items);

        for (self.sorted) |value| {
            self.alloc.free(value);
        }
        self.alloc.free(self.sorted);
    }

    pub fn keyPress(self: *Self, _: u8, key: u16) void {
        switch (key) {
            tb.c.TB_KEY_ARROW_DOWN => {
                self.goDown();
            },
            tb.c.TB_KEY_ARROW_UP => {
                self.goUp();
            },
            tb.c.TB_KEY_ARROW_LEFT => {
                self.set(self.current, false);
            },
            tb.c.TB_KEY_ARROW_RIGHT => {
                self.set(self.current, true);
            },
            tb.c.TB_KEY_TAB => {
                self.set(self.current, !self.selected[self.current]);
                self.goDown();
            },
            else => {},
        }
    }

    fn goUp(self: *Self) void {
        if (self.current - 1 < 0) {
            return;
        }

        self.current -= 1;
    }

    fn goDown(self: *Self) void {
        if (self.current + 1 >= self.items.len) {
            return;
        }

        self.current += 1;
    }

    pub fn draw(self: *Self, screen_w: u32, screen_h: u32) !void {
        if (screen_h <= self.pos.y) return Error.ScreenTooSmall;
        _ = screen_w;

        for (self.items, 0..) |item, i| {
            var x = self.pos.x;
            const y = self.pos.y + @as(u32, @intCast(i));
            if (self.current == i) {
                try tb.print(x, y, .default, .default, "* ");
            }
            x += 2;

            var checkbox = [4:0]u8{ '[', ' ', ']', ' ' };
            if (self.selected[i]) {
                checkbox[1] = 'x';
            }
            try tb.print(x, y, .default, .default, &checkbox);
            x += @intCast(checkbox.len);

            try tb.print(x, y, .default, .default, item);
        }
    }

    pub fn sort(self: *Self, tokens: []const []const u8) void {
        const comparison = struct {
            fn cmp(context: @TypeOf(tokens), lhs: [:0]const u8, rhs: [:0]const u8) bool {
                const rank_lhs = zf.rank(lhs, context, false, false) orelse 0;
                const rank_rhs = zf.rank(rhs, context, false, false) orelse 0;
                return rank_lhs > rank_rhs;
            }
        }.cmp;
        std.sort.pdq(
            [:0]const u8,
            self.sorted,
            tokens,
            comparison,
        );
    }

    fn set(self: *Self, index: usize, value: bool) void {
        if (self.selected.len <= index) return;

        self.selected[index] = value;
    }
};
