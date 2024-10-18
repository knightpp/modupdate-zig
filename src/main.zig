const std = @import("std");
const lib = @import("lib.zig");
const choose = @import("tui.zig").choose;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        std.debug.assert(check == .ok);
    }

    const alloc = gpa.allocator();

    var target = try openTarget(alloc);
    defer target.close();

    const list = try runFilterUI(alloc, target);
    defer {
        for (list) |line| {
            alloc.free(line);
        }
        alloc.free(list);
    }

    if (list.len == 0) {
        return;
    }

    try runGoGet(alloc, list, target);
}

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

fn runFilterUI(alloc: std.mem.Allocator, target: Target) ![]const []const u8 {
    var list = std.ArrayList([]const u8).init(alloc);
    defer list.deinit();

    var buf_reader = std.io.bufferedReader(target.file.reader());
    const buf = try buf_reader.reader().readAllAlloc(alloc, 32 * 1024);
    defer alloc.free(buf);

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

        try list.append(require.path);
    }

    return try choose(alloc, list.items);
}

fn runGoGet(alloc: std.mem.Allocator, chosen: []const []const u8, target: Target) !void {
    var argv = try std.ArrayList([]const u8).initCapacity(alloc, 2 + chosen.len);
    defer argv.deinit();

    try argv.appendSlice(&.{ "go", "get" });
    try argv.appendSlice(chosen);

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
