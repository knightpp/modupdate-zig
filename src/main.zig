const std = @import("std");
const log = std.log;
const lib = @import("gomodfile");
const tb = @import("termbox2");
const tui = @import("tui.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const alloc = gpa.allocator();

    try tb.init();
    defer tb.shutdown() catch |err| {
        std.log.err("could not shutdown: {}", .{err});
    };

    var target = try openTarget(alloc);
    defer target.close();

    const deps = try readDeps(alloc, target);
    defer {
        for (deps) |value| {
            alloc.free(value);
        }
        alloc.free(deps);
    }

    var list = try tui.List.init(alloc, .{ .x = 0, .y = 1 }, deps);
    var text_input = tui.TextInput.init(alloc, tui.Pos.init(0, 0), &list);
    defer list.deinit();

    var w = try tb.width();
    var h = try tb.height();

    try list.draw(w, h);
    try text_input.draw(w, h);
    try tb.present();

    while (true) {
        const event = try tb.poll_event();
        switch (event.type) {
            tb.c.TB_EVENT_KEY => {
                switch (event.key) {
                    tb.c.TB_KEY_ESC, tb.c.TB_KEY_CTRL_C, tb.c.TB_KEY_CTRL_D => return,
                    tb.c.TB_KEY_ENTER => break,
                    else => {},
                }

                try text_input.keyPress(@intCast(event.ch & 0xFF), event.key);
                list.keyPress(@intCast(event.ch & 0xFF), event.key);
                try tb.clear();
                try text_input.draw(w, h);
                try list.draw(w, h);
                try tb.present();
            },
            tb.c.TB_EVENT_MOUSE => {
                continue;
            },
            tb.c.TB_EVENT_RESIZE => {
                w = @intCast(event.w);
                h = @intCast(event.h);

                try tb.clear();
                try text_input.draw(w, h);
                try list.draw(w, h);
                try tb.present();
            },
            else => unreachable,
        }
    }

    var i = 0;
    for (list.selected) |value| {
        if (value) {
            i += 1;
        }
    }
    if (i == 0) return;

    try runGoGet(alloc, deps, target);
}

// pub fn main2() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer {
//         const check = gpa.deinit();
//         std.debug.assert(check == .ok);
//     }

//     const alloc = gpa.allocator();

// }

const Error = error{
    ChildNonZeroExit,
    NoArgument,
    NoFileOnChild,
};

const Target = struct {
    file: std.fs.File,
    dir: std.fs.Dir,

    fn close(self: @This()) void {
        var s = self;
        s.file.close();
        s.dir.close();
    }
};

fn openTarget(alloc: std.mem.Allocator) !Target {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.next();
    const path = args.next() orelse return Error.NoArgument;

    const cwd = std.fs.cwd();
    if (std.mem.eql(u8, std.fs.path.basename(path), "go.mod")) {
        return .{
            .file = try cwd.openFile(path, .{}),
            .dir = try cwd.openDir(std.fs.path.dirname(path) orelse "", .{}),
        };
    }

    const file_path = try std.fs.path.join(alloc, &.{ path, "go.mod" });
    defer alloc.free(file_path);

    return .{
        .file = try cwd.openFile(file_path, .{}),
        .dir = try cwd.openDir(path, .{}),
    };
}

fn readDeps(alloc: std.mem.Allocator, target: Target) ![]const []const u8 {
    var buf_reader = std.io.bufferedReader(target.file.reader());
    const buf = try buf_reader.reader().readAllAlloc(alloc, 128 * 1024);
    defer alloc.free(buf);

    var deps = std.ArrayList([]u8).init(alloc);

    var it = lib.AstIter.init(buf);
    while (try it.next()) |ast| {
        if (ast != .require) {
            continue;
        }

        const require = ast.require;
        if (require.comment) |comment| {
            if (std.mem.containsAtLeast(u8, comment, 1, "indirect")) {
                continue;
            }
        }

        const path = try alloc.alloc(u8, require.path.len);
        @memcpy(path, require.path);
        deps.append(path);
    }

    return deps.toOwnedSlice();
}

fn runGoGet(alloc: std.mem.Allocator, deps: []const []const u8, target: Target) !void {
    var argv = std.ArrayList([]const u8).init(alloc);
    defer argv.deinit();

    try argv.appendSlice(&.{ "go", "get" });
    for (deps) |dep| {
        try argv.append(dep);
    }

    {
        const cmdline = try std.mem.join(alloc, " ", argv.items);
        defer alloc.free(cmdline);

        try std.io.getStdOut().writer().print("{s}\n", .{cmdline});
    }

    var proc = std.process.Child.init(argv.items, alloc);
    proc.cwd_dir = target.dir;

    const term = try proc.spawnAndWait();
    if (term.Exited != 0) return Error.ChildNonZeroExit;
}
