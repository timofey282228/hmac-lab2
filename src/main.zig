const std = @import("std");
const red = @import("red.zig");
const consts = @import("consts.zig");
const hellman = @import("hellman.zig");
const hash = @import("hash.zig");
const filemap = @import("filemap.zig");

const FILEMAP_NAME = "filemap.json";

const ArgumentParsingError = error{ExpectedArgument};

pub fn main() !void {

    // Console output initialization
    // const console_cp = std.os.windows.kernel32.GetConsoleOutputCP();
    _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};

    // some lite argument parsing
    var arguments = try std.process.argsWithAllocator(allocator.allocator());
    // skip argv[0]
    _ = arguments.skip();

    while (arguments.next()) |arg| {
        if (std.mem.eql(u8, arg, "generate")) {
            if (arguments.next()) |kw| {
                if (std.mem.eql(u8, kw, "all")) {
                    std.debug.print("Generating all tables\n", .{});
                    try genAllTableFiles(allocator.allocator(), FILEMAP_NAME);
                    break;
                }
            }
        } else if (std.mem.eql(u8, arg, "attack")) {
            if (arguments.next()) |kw| {
                if (std.mem.eql(u8, kw, "all")) {
                    std.debug.print("Attacking random hashes on all stored tables\n", .{});
                    try attackAll(allocator.allocator());
                    break;
                }
                if (std.mem.eql(u8, kw, "specific")) {
                    std.debug.print("Attacking random hashes on the table with specified parameters\n", .{});

                    const k = try std.fmt.parseInt(
                        usize,
                        arguments.next() orelse return ArgumentParsingError.ExpectedArgument,
                        10,
                    );
                    const l = try std.fmt.parseInt(
                        usize,
                        arguments.next() orelse return ArgumentParsingError.ExpectedArgument,
                        10,
                    );
                    const n = try std.fmt.parseInt(
                        usize,
                        arguments.next() orelse return ArgumentParsingError.ExpectedArgument,
                        10,
                    );
                    try attackSpecificTable(allocator.allocator(), k, l, n);
                    break;
                }
            }
        }
    }
}

pub fn genAllTableFiles(allocator: std.mem.Allocator, filemap_path: []const u8) !void {
    var table_no: usize = 0;
    const all_table_params = try allocator.alloc(filemap.TableParams, 9);
    defer {
        // FIXME: this frees something extra leading to a segfault,
        // for (all_table_params) |*table| {
        //     table.deinit();
        // }
        allocator.free(all_table_params);
    }

    for ([_]u64{ 1 << 20, 1 << 22, 1 << 24 }) |k| {
        for ([_]u64{ 1 << 10, 1 << 11, 1 << 12 }) |l| {
            // for ([_]u64{ 13, 13, 13 }) |k| {
            //     for ([_]u64{ 13, 14, 15 }) |l| {
            std.debug.print("Generating (k = {d}, l = {d})... ", .{ k, l });
            const redundancy_function = red.newRedundancyFunc();
            var ht = hellman.HellmanTable.init(
                allocator,
                k,
                l,
                redundancy_function,
            );
            defer ht.deinit();

            try ht.buildTableParallel();
            // std.debug.print("Sorting... ", .{});
            try ht.sortTable();

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
            // std.debug.print("Saved to {s}\n", .{filename});

            all_table_params[table_no] = try filemap.TableParams.init(
                allocator,
                k,
                l,
                redundancy_function.vec,
                filename,
            );

            table_no += 1;
        }
    }

    var f = try filemap.Filemap.init(allocator, all_table_params);
    defer f.deinit();

    var fm_file = try std.fs.cwd().createFile(filemap_path, .{});
    defer fm_file.close();

    try f.writeToFile(fm_file);
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
                        attack_result.stats.n_comparisons,
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
                            attack_result.stats.n_comparisons,
                        },
                    );
                    return attack_result;
                }
            },
        }
    }
    return null;
}

fn getPrng() std.rand.DefaultPrng {
    return std.rand.DefaultPrng.init(blk: {
        var seed: u64 = 0;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {};
        break :blk seed;
    });
}

pub fn attackAll(allocator: std.mem.Allocator) !void {
    const fmap_file = try std.fs.cwd().openFile(
        FILEMAP_NAME,
        std.fs.File.OpenFlags{
            .mode = .read_only,
        },
    );

    var prng = getPrng();

    const fmap = try filemap.Filemap.initFromFile(allocator, &fmap_file);
    for (fmap.table_params) |table| {
        var ht = hellman.HellmanTable.init(
            allocator,
            table.k,
            table.l,
            red.RedundancyFunc{ .vec = table.redundancy_vector },
        );
        defer ht.deinit();

        try ht.loadTable(table.file_name);

        var counter: u64 = 0;
        const N = 10_000;
        for (0..N) |_| {
            var vector: [256 / 8]u8 = undefined;
            prng.random().bytes(&vector);

            if (try search_table_log_result_ex(hash.hash(&vector), &ht)) |attack_result| {
                std.debug.print("Random vector: {s}; found preimage in {d} cmps\n", .{
                    std.fmt.bytesToHex(vector, .lower),
                    attack_result.stats.n_comparisons,
                });
                counter += 1;
            }
        }
        std.debug.print("Success rate: {d} / {d}\n", .{ counter, N });
    }
}

const AttackError = error{TableNotGenerated};

pub fn attackSpecificTable(allocator: std.mem.Allocator, k: usize, l: usize, n: usize) !void {
    const fmap_file = try std.fs.cwd().openFile(
        FILEMAP_NAME,
        std.fs.File.OpenFlags{
            .mode = .read_only,
        },
    );

    var prng = getPrng();
    var fmap = try filemap.Filemap.initFromFile(allocator, &fmap_file);
    defer fmap.deinit();

    for (fmap.table_params) |table| {
        if (table.k == k and table.l == l) {
            std.debug.print("Using table with k = {d}, l = {d}, redundancy function seed {s}\n", .{
                table.k,
                table.l,
                std.fmt.bytesToHex(table.redundancy_vector, .upper),
            });
            var ht = hellman.HellmanTable.init(
                allocator,
                k,
                l,
                .{ .vec = table.redundancy_vector },
            );
            try ht.loadTable(table.file_name);
            try debugPrintAttack2(n, prng.random(), &ht);
            break;
        }
    } else return AttackError.TableNotGenerated;
}

fn debugPrintAttack(n: usize, prng: std.Random, table: *const hellman.HellmanTable) !void {
    var counter: u64 = 0;

    for (0..n) |_| {
        var vector: [256 / 8]u8 = undefined;
        prng.bytes(&vector);

        const randomVectorHex = std.fmt.bytesToHex(vector, .lower);

        if (try search_table_log_result_ex(hash.hash(&vector), table)) |attack_result| {
            std.debug.print("Random vector: {s}; found preimage in {d} cmps\n", .{
                randomVectorHex,
                attack_result.stats.?.n_comparisons,
            });
            counter += 1;
        }
    }

    std.debug.print("Success rate: {d} / {d}\n", .{ counter, n });
}

fn debugPrintAttack2(n: usize, prng: std.Random, table: *const hellman.HellmanTable) !void {
    var total_success: u64 = 0;
    var misfires: u64 = 0;

    for (0..n) |_| {
        var vector: [256 / 8]u8 = undefined;
        prng.bytes(&vector);

        const random_vector_hex = std.fmt.bytesToHex(vector, .upper);
        const random_vector_hash = hash.hash(&vector);
        const attack_result = try table.searchEx(random_vector_hash);

        if (attack_result.preimage) |preimage| {
            const x: []const u8 = switch (preimage) {
                .first => |x| &x,
                .second => |x| &x,
            };

            if (!std.mem.eql(u8, &hash.hash(x), &random_vector_hash)) {
                // std.debug.print(
                //     "Fail at {d} {d}\n",
                //     .{
                //         attack_result.stats.coordinates.?.i,
                //         attack_result.stats.coordinates.?.j,
                //     },
                // );
                misfires += 1;
                continue;
            }

            std.debug.print("{s}: h({}) = {s} (T = {d})\n", .{
                random_vector_hex,
                std.fmt.fmtSliceHexUpper(x),
                std.fmt.bytesToHex(random_vector_hash, .upper),
                attack_result.stats.n_comparisons,
            });

            total_success += 1;
        }
    }

    std.debug.print("Success rate: {d} / {d} = {d}\n", .{ total_success, n, (@as(f64, @floatFromInt(total_success)) / @as(f64, @floatFromInt(n))) });
    std.debug.print("Misfire rate: {d} / {d} = {d}\n", .{ misfires, n, (@as(f64, @floatFromInt(misfires)) / @as(f64, @floatFromInt(n))) });
}
