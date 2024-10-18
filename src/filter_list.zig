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

// style: vaxis.Style = .{ .dim = true },
// highlighted_style: vaxis.Style = .{ .dim = true, .bg = .{ .index = 0 } },

const Self = @This();

pub fn init(alloc: std.mem.Allocator, list: []const []const u8, gd: *const vaxis.grapheme.GraphemeData, wd: *const usize) !Self {
    var selected = try std.DynamicBitSet.initEmpty(alloc, list.len);
    errdefer selected.deinit();

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
    const visibility_start = self.text_view.scroll_view.scroll.y;
    const visibility_end = self.text_view.scroll_view.scroll.y + win.height - 1;
    if (self.highlighted_line >= visibility_end) {
        self.text_view.scroll_view.scroll.y += self.highlighted_line - visibility_end;
    }
    if (self.highlighted_line <= visibility_start) {
        self.text_view.scroll_view.scroll.y -= visibility_start - self.highlighted_line;
    }

    self.text_view.draw(win, self.buffer);
}

pub fn update(self: *Self, event: Event) !void {
    switch (event) {
        .key_press => |key| {
            if (key.matchesAny(&.{ Key.up, 'e' }, .{})) {
                if (self.highlighted_line == 0) {
                    return;
                }

                self.cursorUp();
            } else if (key.matchesAny(&.{ Key.down, 'n' }, .{})) {
                self.cursorDown();
            } else if (key.matches(Key.right, .{})) {
                self.selected.setValue(self.highlighted_line, true);
            } else if (key.matches(Key.space, .{})) {
                self.selected.toggle(self.highlighted_line);
            } else if (key.matches(Key.tab, .{})) {
                self.selected.toggle(self.highlighted_line);
                self.cursorDown();
            } else {
                return;
            }

            try self.recreateBuffer();
        },
    }
}

fn cursorDown(self: *Self) void {
    self.highlighted_line = @min(self.highlighted_line + 1, self.list.len - 1);
}

fn cursorUp(self: *Self) void {
    self.highlighted_line = self.highlighted_line - 1;
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
