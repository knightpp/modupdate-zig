const std = @import("std");
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const TextView = vaxis.widgets.TextView;
const DisplayWidth = @import("DisplayWidth");

/// The events that this widget handles
const Event = union(enum) {
    key_press: Key,
};

alloc: std.mem.Allocator,
gd: *const vaxis.grapheme.GraphemeData,
wd: *const usize,

list: []const []const u8,
selected: std.DynamicBitSet,
highlighted_line: usize = 0,
text_view: TextView = .{},
buffer: TextView.Buffer = .{},

const prefix = " [ ] ";
// style: vaxis.Style = .{ .dim = true },
// highlighted_style: vaxis.Style = .{ .dim = true, .bg = .{ .index = 0 } },

const Self = @This();

pub fn init(alloc: std.mem.Allocator, gd: *const vaxis.grapheme.GraphemeData, wd: *const usize) !Self {
    const list = &.{ "aaa", "bbb", "ccc", "привіт їжа", "日本, にっぽん / にほん" };
    const selected = try std.DynamicBitSet.initEmpty(alloc, list.len);

    var self = Self{
        .gd = gd,
        .wd = wd,
        .alloc = alloc,
        .list = list,
        .selected = selected,
    };
    try self.recreateBuffer();
    return self;
}

pub fn deinit(self: *Self) void {
    self.selected.deinit();
    self.buffer.deinit(self.alloc);
}

pub fn draw(self: *Self, win: vaxis.Window) void {
    self.text_view.draw(win, self.buffer);
}

pub fn update(self: *Self, event: Event) !void {
    switch (event) {
        .key_press => |key| {
            if (key.matchesAny(&.{ Key.up, 'e' }, .{})) {
                if (self.highlighted_line == 0) {
                    return;
                }

                self.highlighted_line = self.highlighted_line - 1;

                try self.recreateBuffer();
            } else if (key.matchesAny(&.{ Key.down, 'n' }, .{})) {
                self.highlighted_line = @min(self.highlighted_line + 1, self.list.len - 1);

                try self.recreateBuffer();
            } else if (key.matchesAny(&.{Key.right}, .{})) {
                self.selected.setValue(self.highlighted_line, true);

                try self.recreateBuffer();
            } else if (key.matchesAny(&.{ Key.space, Key.tab }, .{})) {
                self.selected.toggle(self.highlighted_line);

                try self.recreateBuffer();
            }
        },
    }
}

fn recreateBuffer(self: *Self) !void {
    self.buffer.clear(self.alloc);
    var writer = self.buffer.writer(
        self.alloc,
        self.gd,
        @ptrCast(self.wd),
    );
    for (self.list, 0..) |line, i| {
        const arrow = if (i == self.highlighted_line) ">" else " ";
        const indicator = if (self.selected.isSet(i)) "[x]" else "[ ]";

        try writer.print("{s} {s} {s}\n", .{ arrow, indicator, line });
    }
}
