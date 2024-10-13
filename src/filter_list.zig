const std = @import("std");
const vaxis = @import("vaxis");
const Key = vaxis.Key;

/// The events that this widget handles
const Event = union(enum) {
    key_press: Key,
};

list: []const []const u8,
selected: std.DynamicBitSet,
highlighted_line: usize = 0,
// style: vaxis.Style = .{ .dim = true },
// highlighted_style: vaxis.Style = .{ .dim = true, .bg = .{ .index = 0 } },

const Self = @This();
const prefix = " [ ] ";

pub fn init(alloc: std.mem.Allocator) !Self {
    const list = &.{ "aaa", "bbb", "ccc" };
    const selected = try std.DynamicBitSet.initEmpty(alloc, list.len);

    return Self{
        .list = list,
        .selected = selected,
    };
}

pub fn draw(self: *const Self, win: vaxis.Window) void {
    for (self.list, 0..) |line, y| {
        for (0..prefix.len) |col| {
            win.writeCell(col, y, .{ .char = .{ .grapheme = prefix[col .. col + 1] } });
        }
        for (prefix.len..prefix.len + line.len) |col| {
            const char = line[col - prefix.len .. col - prefix.len + 1];
            win.writeCell(col, y, .{ .char = .{ .grapheme = char } });
        }
        if (self.selected.isSet(y)) {
            win.writeCell(2, y, .{ .char = .{ .grapheme = "x" } });
        }
    }
    win.writeCell(0, self.highlighted_line, .{ .char = .{ .grapheme = ">" } });
}

pub fn update(self: *Self, event: Event) !void {
    switch (event) {
        .key_press => |key| {
            if (key.matchesAny(&.{ Key.up, 'e' }, .{})) {
                if (self.highlighted_line == 0) {
                    return;
                }

                self.highlighted_line = self.highlighted_line - 1;
            } else if (key.matchesAny(&.{ Key.down, 'n' }, .{})) {
                self.highlighted_line = @min(self.highlighted_line + 1, self.list.len - 1);
            } else if (key.matchesAny(&.{Key.right}, .{})) {
                self.selected.setValue(self.highlighted_line, true);
            } else if (key.matchesAny(&.{ Key.space, Key.tab }, .{})) {
                self.selected.toggle(self.highlighted_line);
            }
        },
    }
}
