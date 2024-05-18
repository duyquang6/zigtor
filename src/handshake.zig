const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const bencode = @import("bencode.zig");

pub const HandshakeError = error{InvalidData};

const Handshake = struct {
    pstr: [19]u8 = "BitTorrent protocol".*,
    info_hash: [20]u8,
    peer_id: [20]u8,

    fn serialize(self: Handshake) [68]u8 {
        var buf: [68]u8 = std.mem.zeroes([68]u8);
        buf[0] = self.pstr.len;

        var curr: u8 = 1;
        @memcpy(buf[curr .. curr + 19], &self.pstr);

        curr += 19;
        @memcpy(buf[curr .. curr + 8], &std.mem.zeroes([8]u8));

        curr += 8;
        @memcpy(buf[curr .. curr + 20], &self.info_hash);

        curr += 20;
        @memcpy(buf[curr .. curr + 20], &self.peer_id);

        return buf;
    }

    fn deserialize(input: []const u8) !Handshake {
        if (input.len < 68) {
            return HandshakeError.InvalidData;
        }
        const pstrlen = input[0];
        if (pstrlen == 0) {
            return HandshakeError.InvalidData;
        }

        var cur: u8 = 1;
        const pstr = input[cur .. cur + pstrlen];
        cur += pstrlen;

        // reserved bytes
        cur += 8;

        const info_hash = input[cur .. cur + 20];

        cur += 20;
        const peer_id = input[cur .. cur + 20];

        return .{ .pstr = pstr[0..19].*, .info_hash = info_hash[0..20].*, .peer_id = peer_id[0..20].* };
    }
};

test "Handshake serialize" {
    const handshake = Handshake{
        .info_hash = [_]u8{ 134, 212, 200, 0, 36, 164, 105, 190, 76, 80, 188, 90, 16, 44, 247, 23, 128, 49, 0, 116 },
        .peer_id = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 },
    };

    const serialized = handshake.serialize();
    std.debug.print("\nserialized={b}\n", .{serialized});
    const expected = [_]u8{ 19, 66, 105, 116, 84, 111, 114, 114, 101, 110, 116, 32, 112, 114, 111, 116, 111, 99, 111, 108, 0, 0, 0, 0, 0, 0, 0, 0, 134, 212, 200, 0, 36, 164, 105, 190, 76, 80, 188, 90, 16, 44, 247, 23, 128, 49, 0, 116, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 };

    try testing.expectEqualSlices(u8, &expected, &serialized);

    const deserialized = try Handshake.deserialize(&serialized);
    try testing.expectEqualSlices(u8, &handshake.peer_id, &deserialized.peer_id);
    try testing.expectEqualSlices(u8, &handshake.info_hash, &deserialized.info_hash);
}
