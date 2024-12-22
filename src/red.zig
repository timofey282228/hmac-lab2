const std = @import("std");
const consts = @import("consts.zig");

pub const RedundancyFunc = struct {
    vec: [consts.ALIGN_REDUNDANCY_LEN - consts.MY_HASH_LEN]u8,

    pub fn reduce(self: RedundancyFunc, message: [consts.MY_HASH_LEN]u8) [consts.ALIGN_REDUNDANCY_LEN]u8 {
        return (self.vec ++ message);
    }
};

pub fn newRedundancyFunc() RedundancyFunc {
    var xoshiro = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {
            seed = 0;
        };

        break :blk seed;
    });

    var initedPrng = xoshiro.random();
    var rbuffer: [consts.ALIGN_REDUNDANCY_LEN - consts.MY_HASH_LEN]u8 = undefined;
    initedPrng.bytes(&rbuffer);

    return .{ .vec = rbuffer };
}

// type aliases
pub const REDUCED = [consts.ALIGN_REDUNDANCY_LEN]u8;
