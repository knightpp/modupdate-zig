const std = @import("std");
const gomod = @import("gomod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        std.debug.assert(check == .ok);
    }

    const alloc = gpa.allocator();

    var target = try openTarget(alloc);
    defer target.close();

    const output = try runFilterUI(alloc, target);
    defer output.deinit();

    try runGoGet(alloc, output, target);
}

const Error = error{
    ChildNonZeroExit,
    NoArgument,
    NoFileOnChild,
};

const Target = struct {
    file: std.fs.File,
    dir: std.fs.Dir,

    fn close(self: *@This()) void {
        self.file.close();
        self.dir.close();
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

fn runFilterUI(alloc: std.mem.Allocator, target: Target) !std.ArrayList(u8) {
    var child = std.process.Child.init(&.{
        "gum",
        "filter",
        "--no-limit",
    }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;

    try child.spawn();

    {
        var buf = std.io.bufferedReader(target.file.reader());
        const reader = buf.reader();

        var stdin = child.stdin orelse return Error.NoFileOnChild;
        var stdin_buf = std.io.bufferedWriter(stdin.writer());
        const writer = stdin_buf.writer();

        var it = gomod.AstIter(@TypeOf(reader)).init(reader);
        while (try it.next()) |dir| {
            if (dir != .require) {
                continue;
            }

            const require = dir.require;
            if (require.comment) |comment| {
                if (std.mem.containsAtLeast(u8, comment, 1, "indirect")) {
                    continue;
                }
            }

            try writer.print("{s}\n", .{require.path});
        }

        try stdin_buf.flush();
        stdin.close();
    }

    var output = std.ArrayList(u8).init(alloc);
    errdefer output.deinit();

    var stdout = child.stdout orelse return Error.NoFileOnChild;
    var buffered = std.io.bufferedReader(stdout.reader());
    const reader = buffered.reader();

    try reader.readAllArrayList(&output, 4096);

    child.stdin = null; // if file is null .wait won't close it
    const term = try child.wait();
    if (term.Exited != 0) return Error.ChildNonZeroExit;

    return output;
}

fn runGoGet(alloc: std.mem.Allocator, output: std.ArrayList(u8), target: Target) !void {
    var argv = std.ArrayList([]const u8).init(alloc);
    defer argv.deinit();

    try argv.appendSlice(&.{ "go", "get" });
    var tokens = std.mem.tokenizeScalar(u8, output.items, '\n');
    while (tokens.next()) |token| {
        try argv.append(token);
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
