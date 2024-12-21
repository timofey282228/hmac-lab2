const std = @import("std");
const consts = @import("consts.zig");

pub fn hash(message: []const u8) [consts.MY_HASH_LEN]u8 {
    const Sha256 = std.crypto.hash.sha2.Sha256;
    var hasher = Sha256.init(.{});
    hasher.update(message);
    const digest = hasher.finalResult();
    return std.mem.bytesToValue([consts.MY_HASH_LEN]u8, digest[Sha256.digest_length - consts.MY_HASH_LEN .. Sha256.digest_length]);
}

// type aliases
pub const HASH = [consts.MY_HASH_LEN]u8;
