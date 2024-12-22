const std = @import("std");
const red = @import("red.zig");
const consts = @import("consts.zig");

pub const Filemap = struct {
    allocator: std.mem.Allocator,
    table_params: []TableParams,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, table_params: []const TableParams) !Self {
        return .{
            .allocator = allocator,
            .table_params = try allocator.dupe(TableParams, table_params),
        };
    }

    pub fn writeToFile(self: *const Self, file: std.fs.File) !void {
        // var jsonArray = std.json.Array.init(self.allocator);

        const tpj_slice: []TableParamsJson = try self.allocator.alloc(TableParamsJson, self.table_params.len);
        defer self.allocator.free(tpj_slice);

        for (self.table_params, tpj_slice) |tp, *dst| {
            const tpj = TableParamsJson{
                .k = tp.k,
                .l = tp.l,
                .redundancy_vector = std.fmt.bytesToHex(tp.redundancy_vector, .upper),
                .file_name = std.json.Value{
                    .string = tp.file_name,
                },
            };
            dst.* = tpj;
        }

        const json_bytes = try std.json.stringifyAlloc(self.allocator, tpj_slice, .{});
        defer self.allocator.free(json_bytes);

        try file.writeAll(json_bytes);
    }

    pub fn initFromFile(allocator: std.mem.Allocator, file: *const std.fs.File) !Self {
        const json_bytes = try file.readToEndAlloc(allocator, 1 << 12);
        defer allocator.free(json_bytes);

        const parsed_table_params = try std.json.parseFromSlice(
            []TableParamsJson,
            allocator,
            json_bytes,
            .{},
        );
        defer parsed_table_params.deinit();

        // freed on deinit
        const table_params = try allocator.alloc(TableParams, parsed_table_params.value.len);

        for (table_params, parsed_table_params.value) |*dst, src| {
            dst.* = try TableParams.initFromTPJ(allocator, src);
        }

        return .{
            .allocator = allocator,
            .table_params = table_params,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.table_params) |*tp| {
            tp.deinit();
        }
        self.allocator.free(self.table_params);
    }
};

const TableParamsJson = struct {
    k: u64,
    l: u64,
    redundancy_vector: [consts.ADD_REDUNDANCY_LEN * 2]u8,
    file_name: std.json.Value,
};

pub const TableParams = struct {
    allocator: std.mem.Allocator,
    k: u64,
    l: u64,
    redundancy_vector: [consts.ADD_REDUNDANCY_LEN]u8,
    file_name: []const u8,

    const Self = @This();
    pub fn initFromTPJ(allocator: std.mem.Allocator, params: TableParamsJson) !Self {
        var file_name_string: []const u8 = undefined;
        if (params.file_name == .string)
            file_name_string = params.file_name.string
        else
            return std.json.ParseFromValueError.UnexpectedToken;

        var redundadncy_vector: [consts.ADD_REDUNDANCY_LEN]u8 = undefined;

        _ = try std.fmt.hexToBytes(&redundadncy_vector, &params.redundancy_vector);

        return .{
            .allocator = allocator,
            .k = params.k,
            .l = params.l,
            .redundancy_vector = redundadncy_vector,
            .file_name = try allocator.dupe(u8, file_name_string),
        };
    }

    pub fn init(
        allocator: std.mem.Allocator,
        k: u64,
        l: u64,
        redundancy_vector: [consts.ADD_REDUNDANCY_LEN]u8,
        file_name: []const u8,
    ) !Self {
        return .{
            .allocator = allocator,
            .k = k,
            .l = l,
            .redundancy_vector = redundancy_vector,
            .file_name = try allocator.dupe(u8, file_name),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.file_name);
    }
};

test "store filemap" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().createFile("tables/TEST_filemapStored.json", .{});
    defer file.close();

    var filemap = try Filemap.init(
        allocator,
        &[_]TableParams{
            try TableParams.init(
                allocator,
                1024,
                1024,
                [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
                "whatever",
            ),
        },
    );
    defer filemap.deinit();

    try filemap.writeToFile(file);
}

// yes this one actually depends on the previous never do test like this irl i guess
test "load filemap" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("tables/TEST_filemapStored.json", .{});
    defer file.close();

    var filemap = try Filemap.initFromFile(allocator, &file);
    defer filemap.deinit();
}

test "table params" {
    const allocator = std.testing.allocator;
    var table_prams = try TableParams.init(
        allocator,
        1024,
        1024,
        [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        "whatever",
    );
    defer table_prams.deinit();
}
