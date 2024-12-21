const std = @import("std");
const red = @import("red.zig");
const consts = @import("consts.zig");
const hellman = @import("hellman.zig");
const hash = @import("hash.zig");

pub fn main() !void {

    // Console output initialization
    // const console_cp = std.os.windows.kernel32.GetConsoleOutputCP();

    _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    // const redundancy_function = red.getRedundancyFunc();
    // TESTING
    const rf_bytes = [_]u8{0} ** (12);
    const redundancy_function = red.RedundancyFunc{ .vec = rf_bytes };

    var ht = try hellman.HellmanTable.init(
        allocator.allocator(),
        1 << 20,
        1 << 10,
        redundancy_function,
    );
    defer ht.deinit();

    std.debug.print("{s}\n", .{std.fmt.bytesToHex(redundancy_function.vec, .lower)});

    // try ht.loadTable("./table.bin");
    try ht.buildTableParallel();
    ht.debugPrintTable();
    try ht.storeTable("tabletoo.bin");

    // get a random target for testing
    // const target: hash.HASH = ht.table.?[ht.prng.random().intRangeAtMost(u64, 0, ht.k - 1)].y;
    const target = "\x45\xd7\xca\xf7";

    std.debug.print("Target: {s}\n", .{std.fmt.bytesToHex(target, .upper)});

    const maybe_prewhatever = ht.search(std.mem.bytesToValue(hash.HASH, target));
    if (maybe_prewhatever) |prewhatever| {
        switch (prewhatever) {
            .first => |x| {
                std.debug.print(
                    "Pre: {s}\n",
                    .{std.fmt.bytesToHex(x, .upper)},
                );
            },
            .second => |x| {
                std.debug.print(
                    "Sec: {s}\n",
                    .{std.fmt.bytesToHex(x, .upper)},
                );
            },
        }
    } else {
        std.debug.print("NAH\n", .{});
    }
}
