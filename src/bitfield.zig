const std = @import("std");
const testing = std.testing;
const print = std.debug.print;

pub fn hasPiece(buf: []const u8, index: u32) bool {
    const byte_index = index / 8;
    const offset: u3 = @truncate(index % 8);

    if (byte_index < 0 or byte_index >= buf.len) {
        return false;
    }

    return buf[byte_index] >> (7 - offset) & 1 != 0;
}

test "hasPiece" {
    const buf = [_]u8{ 0b01010100, 0b01010100 };
    const outputs = [_]bool{ false, true, false, true, false, true, false, false, false, true, false, true, false, true, false, false, false, false, false, false };

    for (0..outputs.len) |i| {
        try testing.expectEqual(outputs[i], hasPiece(&buf, @intCast(i)));
    }
}

pub fn setPiece(buf: []u8, index: u32) void {
    const byte_index = index / 8;
    const offset: u3 = @truncate(index % 8);

    if (byte_index < 0 or byte_index >= buf.len) {
        return;
    }

    buf[byte_index] |= @as(u8, 1) << (7 - offset);
}

test "setPiece OK" {
    var input = [_]u8{ 0b01010100, 0b01010100 };
    setPiece(&input, 4);
}
