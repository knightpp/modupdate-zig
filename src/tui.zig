const std = @import("std");
const vaxis = @import("vaxis");
const FilterList = @import("filter_list.zig");
const Cell = vaxis.Cell;
const TextInput = vaxis.widgets.TextInput;
const border = vaxis.widgets.border;

// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    foo: u8,
};

pub fn choose(alloc: std.mem.Allocator, list: []const []const u8) ![][]const u8 {
    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var vx = try vaxis.init(alloc, .{});
    // deinit takes an optional allocator. If your program is exiting, you can
    // choose to pass a null allocator to save some exit time.
    defer vx.deinit(alloc, tty.anyWriter());

    // The event loop requires an intrusive init. We create an instance with
    // stable pointers to Vaxis and our TTY, then init the instance. Doing so
    // installs a signal handler for SIGWINCH on posix TTYs
    //
    // This event loop is thread safe. It reads the tty in a separate thread
    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    // Start the read loop. This puts the terminal in raw mode and begins
    // reading user input
    try loop.start();
    defer loop.stop();

    // Optionally enter the alternate screen
    try vx.enterAltScreen(tty.anyWriter());

    // We'll adjust the color index every keypress for the border
    var color_idx: u8 = 1;

    // init our text input widget. The text input widget needs an allocator to
    // store the contents of the input
    var text_input = TextInput.init(alloc, &vx.unicode);
    defer text_input.deinit();

    var filter_list = try FilterList.init(alloc, list, &vx.unicode.width_data.g_data, @ptrCast(&vx.unicode.width_data));
    defer filter_list.deinit();

    // Sends queries to terminal to detect certain features. This should always
    // be called after entering the alt screen, if you are using the alt screen
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);
    var buf_tty = std.io.BufferedWriter(8192, std.io.AnyWriter){ .unbuffered_writer = tty.anyWriter() };

    while (true) {
        // nextEvent blocks until an event is in the queue
        const event = loop.nextEvent();
        // exhaustive switching ftw. Vaxis will send events if your Event enum
        // has the fields for those events (ie "key_press", "winsize")
        switch (event) {
            .key_press => |key| {
                color_idx +%= 1;
                if (key.matches('c', .{ .ctrl = true })) {
                    return error.ctrl_c;
                } else if (key.matches('d', .{ .ctrl = true })) {
                    return error.ctrl_d;
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else {
                    try text_input.update(.{ .key_press = key });
                    try filter_list.update(.{ .key_press = key });
                }
            },

            // winsize events are sent to the application to ensure that all
            // resizes occur in the main thread. This lets us avoid expensive
            // locks on the screen. All applications must handle this event
            // unless they aren't using a screen (IE only detecting features)
            //
            // The allocations are because we keep a copy of each cell to
            // optimize renders. When resize is called, we allocated two slices:
            // one for the screen, and one for our buffered screen. Each cell in
            // the buffered screen contains an ArrayList(u8) to be able to store
            // the grapheme for that cell. Each cell is initialized with a size
            // of 1, which is sufficient for all of ASCII. Anything requiring
            // more than one byte will incur an allocation on the first render
            // after it is drawn. Thereafter, it will not allocate unless the
            // screen is resized
            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
            else => {},
        }

        // vx.window() returns the root window. This window is the size of the
        // terminal and can spawn child windows as logical areas. Child windows
        // cannot draw outside of their bounds
        const win = vx.window();

        // Clear the entire space because we are drawing in immediate mode.
        // vaxis double buffers the screen. This new frame will be compared to
        // the old and only updated cells will be drawn
        win.clear();

        // Create a style
        const style: vaxis.Style = .{
            .fg = .{ .index = color_idx },
        };

        // Create a bordered child window
        const input_window = win.child(.{
            .x_off = win.width / 2 - 20,
            .y_off = 0,
            .width = .{ .limit = 40 },
            .height = .{ .limit = 3 },
            .border = .{
                .where = .all,
                .style = style,
            },
        });

        const list_window = win.child(.{
            .x_off = 0,
            .y_off = 3,
            .width = .expand,
            .height = .expand,
            .border = .{
                .where = .all,
                .style = style,
            },
        });

        // Draw the text_input in the child window
        text_input.draw(input_window);
        filter_list.draw(list_window);

        try vx.render(buf_tty.writer().any());
        try buf_tty.flush();
    }

    const n = filter_list.selected.count();
    var selected = try std.ArrayList([]const u8).initCapacity(alloc, n);
    defer selected.deinit();

    var it = filter_list.selected.iterator(.{ .kind = .set });
    while (it.next()) |i| {
        const line = try alloc.dupe(u8, filter_list.list[i]);
        try selected.append(line);
    }

    return try selected.toOwnedSlice();
}
