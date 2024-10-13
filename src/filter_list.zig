const std = @import("std");
const vaxis = @import("vaxis");

list: []const []const u8 = &.{ "aaa", "bbb", "ccc" },
highlighted_line: usize = 0,
// style: vaxis.Style = .{ .dim = true },
// highlighted_style: vaxis.Style = .{ .dim = true, .bg = .{ .index = 0 } },

const Self = @This();
const prefix = " [ ] ";

pub fn draw(self: @This(), win: vaxis.Window) void {
    for (self.list, 0..) |line, y| {
        for (0..prefix.len) |col| {
            win.writeCell(col, y, .{ .char = .{ .grapheme = prefix[col .. col + 1] } });
        }
        for (prefix.len..prefix.len + line.len) |col| {
            const char = line[col - prefix.len .. col - prefix.len + 1];
            win.writeCell(col, y, .{ .char = .{ .grapheme = char } });
        }
    }
    win.writeCell(0, self.highlighted_line, .{ .char = .{ .grapheme = ">" } });
}
