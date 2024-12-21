const std = @import("std");
const consts = @import("consts.zig");

threadlocal var random: ?std.rand.DefaultPrng = null;

pub fn initPrng() std.rand.DefaultPrng {
    const prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {
            seed = 0;
        };

        break :blk seed;
    });

    random = prng;
    return prng;
}

pub fn R(message: [consts.MY_HASH_LEN]u8) [consts.ALIGN_REDUNDANCY]u8 {
    const initedPrng = (random orelse blk: {
        break :blk initPrng();
    }).random();

    var rbuffer: [consts.ALIGN_REDUNDANCY - consts.MY_HASH_LEN]u8 = undefined;

    initedPrng.bytes(&rbuffer);

    return (rbuffer ++ message);
}

pub const RedundancyFunc = struct {
    vec: [consts.ALIGN_REDUNDANCY - consts.MY_HASH_LEN]u8,

    pub fn reduce(self: RedundancyFunc, message: [consts.MY_HASH_LEN]u8) [consts.ALIGN_REDUNDANCY]u8 {
        return (self.vec ++ message);
    }
};

pub fn newRedundancyFunc() RedundancyFunc {
    var xoshiro = random orelse blk: {
        break :blk initPrng();
    };

    var initedPrng = xoshiro.random();
    var rbuffer: [consts.ALIGN_REDUNDANCY - consts.MY_HASH_LEN]u8 = undefined;
    initedPrng.bytes(&rbuffer);

    return .{ .vec = rbuffer };
}

// type aliases

pub const REDUCED = [consts.ALIGN_REDUNDANCY]u8;
