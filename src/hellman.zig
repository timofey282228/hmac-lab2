const std = @import("std");
const consts = @import("consts.zig");
const red = @import("red.zig");
const hash = @import("hash.zig");

const HellmanTableErrors = error{TableNotInitialized};

pub const HellmanTable = struct {
    const TableEntry = struct {
        x: [consts.MY_HASH_LEN]u8,
        y: [consts.MY_HASH_LEN]u8,
    };

    k: u64,
    l: u64,
    allocator: std.mem.Allocator,
    r: red.RedundancyFunc,
    table: ?[]TableEntry = null,
    prng: std.Random.DefaultPrng,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, k: u64, l: u64, r: red.RedundancyFunc) !Self {
        var seed: u64 = 0;

        std.posix.getrandom(std.mem.asBytes(&seed)) catch |err| {
            std.debug.print("std.posix.getrandom failed: {any}\n", .{err});
        };
        std.debug.print("Seed: {d}\n", .{seed});

        const xoshiro = std.Random.DefaultPrng.init(seed);

        return .{
            .allocator = allocator,
            .k = k,
            .l = l,
            .prng = xoshiro,
            .r = r,
        };
    }

    pub fn buildTable(self: *Self) !void {
        const k = self.k;
        const l = self.l;
        const random = self.prng.random();

        var table = try self.allocator.alloc(TableEntry, k);

        var timer = try std.time.Timer.start();

        for (0..k) |i| {
            var x: [consts.MY_HASH_LEN]u8 = undefined;
            random.bytes(&x);

            var y: [consts.MY_HASH_LEN]u8 = hash.hash(&self.r.reduce(x));
            for (1..l) |_| {
                y = hash.hash(&self.r.reduce(y));
            }
            table[i] = TableEntry{ .x = x, .y = y };
            if (i > 0 and (i % 1 << 20 == 0)) {
                const current = timer.read();
                std.debug.print(
                    "Average time for a row (ns): {d}\r",
                    .{@divTrunc(current, i)},
                );
            }
        }

        self.table = table;
    }

    /// Generate a TableEntry using the passed in parameters and random generator interface
    inline fn genEntry(l: u64, r: red.RedundancyFunc, random: std.Random) TableEntry {
        var x: [consts.MY_HASH_LEN]u8 = undefined;
        random.bytes(&x);
        var y: [consts.MY_HASH_LEN]u8 = hash.hash(&r.reduce(x));
        for (1..l) |_| {
            y = hash.hash(&r.reduce(y));
        }

        return TableEntry{ .x = x, .y = y };
    }

    pub fn buildTableParallel(self: *Self) !void {
        var table = try self.allocator.alloc(TableEntry, self.k);

        const BuilderArgs = struct {
            entries: []TableEntry,
            l: u64,
            r: red.RedundancyFunc,
        };

        const Builder = struct {
            fn builderFunc(builder_args: *BuilderArgs) void {
                std.debug.print("Arg info: {any} for {any}\n", .{
                    builder_args.entries.ptr,
                    builder_args.entries.len,
                });

                // init a prng in this thread
                var seed: u64 = undefined;
                std.posix.getrandom(std.mem.asBytes(&seed)) catch |err| {
                    std.debug.print("std.posix.getrandom failed: {any}\n", .{err});
                };

                var xoshiro = std.Random.DefaultPrng.init(seed);
                const random = xoshiro.random();

                for (builder_args.entries) |*entry| {
                    entry.* = genEntry(builder_args.l, builder_args.r, random);
                }

                std.debug.print("exiting thread", .{});
            }
        };

        const cores = try std.Thread.getCpuCount();

        var threadsafe_gpa = std.heap.GeneralPurposeAllocator(
            .{ .thread_safe = true },
        ){};

        var thread_allocator = std.heap.ArenaAllocator.init(threadsafe_gpa.allocator());
        defer thread_allocator.deinit();

        std.debug.print(
            "Mind the size: {d}\nand the alignment: {d}\n",
            .{ @sizeOf(TableEntry), @alignOf(TableEntry) },
        );

        const step: u64 = self.k / cores;
        std.debug.print("Step: {d}\n", .{step});
        std.debug.print("K: {d}\n", .{self.k});

        const additional_threads = cores - 1;
        var threads = try thread_allocator.allocator().alloc(std.Thread, additional_threads);

        for (0..additional_threads) |i| {
            const builderArgs = try thread_allocator.allocator().create(BuilderArgs);
            const end = ((i + 1) * step);

            std.debug.print("End: {d}\n", .{end});

            builderArgs.* = .{
                .entries = table[i * step .. end],
                .l = self.l,
                .r = self.r,
            };

            threads[i] = try std.Thread.spawn(
                .{},
                Builder.builderFunc,
                .{builderArgs},
            );
        }

        std.debug.print(
            "Generating {d} entries on main thread\n",
            .{self.k - additional_threads * step},
        );

        // we'll just finish the rest of the table in this thread
        var timer = try std.time.Timer.start();
        for (additional_threads * step..self.k) |i| {
            table[i] = genEntry(self.l, self.r, self.prng.random());
            if (i % (1 << 10) == 0) {
                std.debug.print(
                    "Generated entry: {d}; rate: {d} ns\r",
                    .{ i, timer.lap() },
                );
            }
        }

        std.debug.print(
            "Also calculating on the main thread: {d} - {d}",
            .{ additional_threads * step, self.k },
        );

        // wait for the rest of the threads to finish
        for (0..additional_threads) |i| {
            std.debug.print("Joining: {d}\n", .{i});
            threads[i].join();
            std.debug.print("Joined: {d}\n", .{i});
        }

        self.table = table;
    }

    pub fn debugPrintTable(self: *const Self) void {
        const table = self.table orelse {
            std.debug.print("Table not built", .{});
            return;
        };

        for (0..self.k) |i| {
            const x = table[i].x;
            const y = table[i].y;
            std.debug.print("{s} -> {s}\n", .{
                std.fmt.bytesToHex(x, .upper),
                std.fmt.bytesToHex(y, .upper),
            });
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.table) |table| {
            self.allocator.free(table);
        }
    }

    pub fn search(self: *const Self, h: hash.HASH) ?Preimage {
        const table = self.table orelse return null;

        var y = h;
        var found_at: ?u64 = null;
        var chain_offset: u64 = undefined;

        find: for (0..self.l) |j| {
            std.debug.print("Trying chian offset {d}\n", .{j});
            // linsearch hell yeah
            for (0..self.k) |i| {
                const table_val = std.mem.bytesAsValue(u32, &table[i].y);
                const y_val = std.mem.bytesAsValue(u32, &y);

                std.debug.print("Comparing {s} with {s}\n", .{
                    std.fmt.bytesToHex(y, .upper),
                    std.fmt.bytesToHex(table[i].y, .upper),
                });

                if (y_val.* == table_val.*) {
                    std.debug.print("Found. Target: {s}; table {d}:{d}: {s}\n", .{
                        std.fmt.bytesToHex(y, .upper),
                        i,
                        j,
                        std.fmt.bytesToHex(table[i].y, .upper),
                    });

                    found_at = i;
                    chain_offset = j;
                    break :find;
                }
            }

            y = hash.hash(&self.r.reduce(y));
        }

        if (found_at) |i| {
            var x: hash.HASH = table[i].x;
            if (chain_offset == 0) {
                return Preimage{ .first = x };
            }

            std.debug.print("i: {d}, j: {d}\n", .{ i, chain_offset });

            for (0..self.l - 1 - chain_offset) |_| {
                std.debug.print("X: {s}\n", .{std.fmt.bytesToHex(x, .upper)});
                std.debug.print("h(R(X))\n", .{});
                x = hash.hash(&self.r.reduce(x));

                std.debug.print("X: {s}\n", .{std.fmt.bytesToHex(x, .upper)});
            }

            return Preimage{ .second = self.r.reduce(x) };
        }

        return null;
    }

    pub fn loadTable(self: *Self, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(
            file_path,
            .{ .mode = .read_only, .lock = .shared },
        );
        defer file.close();

        const table_data = try file.readToEndAlloc(self.allocator, (1 << 24) * 2 * 4);
        self.table = std.mem.bytesAsSlice(TableEntry, table_data);
    }

    pub fn storeTable(self: *const Self, file_path: []const u8) !void {
        const table = self.table orelse return HellmanTableErrors.TableNotInitialized;
        const file = try std.fs.cwd().createFile(
            file_path,
            std.fs.File.CreateFlags{
                .lock = .exclusive,
                .truncate = true,
            },
        );
        defer file.close();

        try file.writeAll(std.mem.sliceAsBytes(table));
    }
};

pub const Preimage = union(enum) {
    first: hash.HASH,
    second: red.REDUCED,
};

test "init deinit hellman" {
    const testing = @import("std").testing;
    var hellman_table = HellmanTable.init(
        testing.allocator,
        10,
        10,
        red.newRedundancyFunc(),
    );
    defer hellman_table.deinit();
}
