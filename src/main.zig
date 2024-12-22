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

    var redundancy: [consts.ALIGN_REDUNDANCY - consts.MY_HASH_LEN]u8 = undefined;
    // TODO: dynamic
    _ = try std.fmt.hexToBytes(&redundancy, "b61578bc95896e712956552f");
    var ht = hellman.HellmanTable.init(
        allocator.allocator(),
        1048576,
        4096,
        red.RedundancyFunc{ .vec = redundancy },
    );
    try ht.loadTable("tables/b61578bc95896e712956552f_1048576_4096.bin");
    std.debug.print("Sorting the table...\n", .{});
    try ht.sortTable();
    std.debug.print("Table sorted. Starting experiments...\n", .{});

    // var counter: u64 = 0;
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = 0;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    var counter: u64 = 0;
    const N = 10_000;
    for (0..N) |_| {
        var vector: [256 / 8]u8 = undefined;
        prng.random().bytes(&vector);

        if (try search_table_log_result_ex(hash.hash(&vector), &ht)) |attack_result| {
            std.debug.print("Random vector: {s}; found preimage in {d} cmps\n", .{
                std.fmt.bytesToHex(vector, .lower),
                attack_result.stats.?.n_comparisons,
            });
            counter += 1;
        }
    }
    std.debug.print("Success rate: {d} / {d}", .{ counter, N });
}

pub fn genAllTableFiles(allocator: std.mem.Allocator) !void {
    for ([_]u64{ 1 << 20, 1 << 22, 1 << 24 }) |k| {
        for ([_]u64{ 1 << 10, 1 << 11, 1 << 12 }) |l| {
            const redundancy_function = red.newRedundancyFunc();
            var ht = hellman.HellmanTable.init(
                allocator,
                k,
                l,
                redundancy_function,
            );
            defer ht.deinit();

            try ht.buildTableParallel();

            const filename = try std.fmt.allocPrint(
                allocator,
                "{s}_{d}_{d}.bin",
                .{
                    std.fmt.bytesToHex(redundancy_function.vec, .lower),
                    k,
                    l,
                },
            );
            defer allocator.free(filename);

            const file = try std.fs.cwd().createFile(
                filename,
                .{ .lock = .exclusive },
            );
            defer file.close();

            try ht.storeTableF(file);
        }
    }
}

pub fn search_table_log_result(h: hash.HASH, table: *const hellman.HellmanTable) !bool {
    const maybe_prewhatever = table.search(h);
    if (maybe_prewhatever) |prewhatever| {
        switch (prewhatever) {
            .first => |x| {
                std.debug.print(
                    "Pre: h({s}) = {s}\n",
                    .{
                        std.fmt.bytesToHex(x, .upper),
                        std.fmt.bytesToHex(h, .upper),
                    },
                );
                return true;
            },
            .second => |x| {
                if (std.mem.eql(u8, &hash.hash(&x), &h)) {
                    std.debug.print(
                        "Sec: h({s}) = {s}\n",
                        .{
                            std.fmt.bytesToHex(x, .upper),
                            std.fmt.bytesToHex(h, .upper),
                        },
                    );
                    return true;
                }
            },
        }
    }
    return false;
}

pub fn search_table_log_result_ex(h: hash.HASH, table: *const hellman.HellmanTable) !?hellman.AttackResult {
    const attack_result = try table.searchEx(h);
    if (attack_result.preimage) |prewhatever| {
        switch (prewhatever) {
            .first => |x| {
                std.debug.print(
                    "Pre: h({s}) = {s} (needed {d} cmps)\n",
                    .{
                        std.fmt.bytesToHex(x, .upper),
                        std.fmt.bytesToHex(h, .upper),
                        attack_result.stats.?.n_comparisons,
                    },
                );
                return attack_result;
            },
            .second => |x| {
                if (std.mem.eql(u8, &hash.hash(&x), &h)) {
                    std.debug.print(
                        "Sec: h({s}) = {s} (needed {d} cmps)\n",
                        .{
                            std.fmt.bytesToHex(x, .upper),
                            std.fmt.bytesToHex(h, .upper),
                            attack_result.stats.?.n_comparisons,
                        },
                    );
                    return attack_result;
                }
            },
        }
    }
    return null;
}
