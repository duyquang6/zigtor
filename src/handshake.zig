const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const bencode = @import("bencode.zig");

const Handshake = struct {
    pstr: [19]u8 = "BitTorrent protocol".*,
    info_hash: [20]u8,
    peer_id: [20]u8,

    fn serialize(self: Handshake) ![68]u8 {
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

    fn deserialize(r: []const u8) !Handshake {
        _ = r;
        return undefined;
    }
};

test "Handshake serialize" {
    const handshake = Handshake{
        .info_hash = [_]u8{ 134, 212, 200, 0, 36, 164, 105, 190, 76, 80, 188, 90, 16, 44, 247, 23, 128, 49, 0, 116 },
        .peer_id = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 },
    };

    const serialized = try handshake.serialize();
    std.debug.print("\nserialized={b}\n", .{serialized});
    const expected = [_]u8{ 19, 66, 105, 116, 84, 111, 114, 114, 101, 110, 116, 32, 112, 114, 111, 116, 111, 99, 111, 108, 0, 0, 0, 0, 0, 0, 0, 0, 134, 212, 200, 0, 36, 164, 105, 190, 76, 80, 188, 90, 16, 44, 247, 23, 128, 49, 0, 116, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 };

    try testing.expectEqualSlices(u8, &expected, &serialized);
}
