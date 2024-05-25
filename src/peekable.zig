pub fn Peekable(comptime T: type, comptime Iterator: type) type {
    return struct {
        const Self = @This();

        future: ??T,
        it: Iterator,

        pub fn init(it: Iterator) Self {
            return .{
                .it = it,
                .future = null,
            };
        }

        pub fn next(self: *Self) ?T {
            if (self.future) |value| {
                self.future = null;
                return value;
            } else {
                return self.it.next();
            }
        }

        pub fn peek(self: *Self) ?T {
            if (self.future) |value| {
                return value;
            } else {
                const val = self.it.next();
                self.future = val;
                return val;
            }
        }
    };
}
