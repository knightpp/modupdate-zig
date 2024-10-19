const zbench = @import("zbench");
const std = @import("std");
const benchmarks = @import("benchmarks.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        std.debug.assert(check == .ok);
    }

    var bench = zbench.Benchmark.init(gpa.allocator(), .{});
    defer bench.deinit();

    try bench.add("Ast Benchmark", benchmarks.astBenchmark, .{});
    try bench.add("Tokenizer Benchmark", benchmarks.tokenizerBenchmark, .{});
    try bench.run(std.io.getStdErr().writer());
}
