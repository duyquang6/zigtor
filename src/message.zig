const std = @import("std");
const testing = std.testing;
const print = std.debug.print;

pub const MessageError = error{Invalid};
pub const MessageEnum = enum {
    // Choke chokes the receiver
    Choke,
    // Unchoke unchokes the receiver
    Unchoke,
    // Interested expresses interest in receiving data
    Interested,
    // NotInterested expresses disinterest in receiving data
    NotInterested,
    // Have alerts the receiver that the sender has downloaded a piece
    Have,
    // Bitfield encodes which pieces that the sender has downloaded
    Bitfield,
    // Request requests a block of data from the receiver
    Request,
    // Piece delivers a block of data to fulfill a request
    Piece,
    // Cancel cancels a request
    Cancel,
};

// pub const Request = struct {
//     Message: Message,
// };

pub const Message = struct {
    id: MessageEnum,
    payload: ?[]const u8 = null,

    pub fn formatRequest(index: u32, begin: u32, length: u32, buffer: []u8) !Message {
        std.mem.writeInt(u32, buffer[0..4], index, std.builtin.Endian.big);
        std.mem.writeInt(u32, buffer[4..8], begin, std.builtin.Endian.big);
        std.mem.writeInt(u32, buffer[8..12], length, std.builtin.Endian.big);

        return Message{ .id = .Request, .payload = buffer[0..12] };
    }

    pub fn formatHave(index: u32, buffer: []u8) !Message {
        std.mem.writeInt(u32, buffer[0..4], index, std.builtin.Endian.big);
        return Message{ .id = .Have, .payload = buffer[0..4] };
    }

    pub fn marshalPiece(self: Message, buf: []u8, index: u32) !u32 {
        if (self.id != .Piece) {
            return MessageError.Invalid;
        }

        if (self.payload) |payload| {
            if (payload.len < 8) {
                return MessageError.Invalid;
            }
            const parsed_index = std.mem.readInt(u32, payload[0..4], std.builtin.Endian.big);
            if (parsed_index != index) {
                return MessageError.Invalid;
            }
            const begin = std.mem.readInt(u32, payload[4..8], std.builtin.Endian.big);
            if (begin >= buf.len) {
                return MessageError.Invalid;
            }
            const piece_data = payload[8..];
            if (begin + piece_data.len > buf.len) {
                return MessageError.Invalid;
            }
            std.mem.copyForwards(u8, buf[begin..], piece_data);

            return @intCast(piece_data.len);
        }
        return MessageError.Invalid;
    }

    pub fn marshalHave(self: Message) !u32 {
        if (self.id != .Have) {
            return MessageError.Invalid;
        }

        if (self.payload) |payload| {
            if (payload.len != 4) {
                return MessageError.Invalid;
            }
            const parsed_index = std.mem.readInt(u32, payload[0..4], std.builtin.Endian.big);
            return @intCast(parsed_index);
        }
        return MessageError.Invalid;
    }

    pub fn serialize(self: ?Message, buf: []u8) ![]const u8 {
        if (self) |msg| {
            if (msg.payload) |payload| {
                const length: u32 = @intCast(payload.len + 1);

                std.mem.writeInt(u32, buf[0..4], length, std.builtin.Endian.big);
                buf[4] = @intFromEnum(msg.id);
                @memcpy(buf[5 .. payload.len + 5], payload);

                return buf[0 .. 5 + payload.len];
            } else {
                std.mem.writeInt(u32, buf[0..4], 1, std.builtin.Endian.big);
                buf[4] = @intFromEnum(msg.id);

                return buf[0..5];
            }
        }

        return &[_]u8{0} ** 4;
    }

    pub fn deserialize(input: []const u8) ?Message {
        if (input.len < 4) {
            return null;
        }
        const length = std.mem.readInt(u32, input[0..4], std.builtin.Endian.big);

        // keepalive
        if (length == 0) {
            return null;
        }

        const msg_buf = input[4 .. 4 + length];

        return Message{ .id = @enumFromInt(msg_buf[0]), .payload = msg_buf[1..] };
    }
};

test "format REQUEST Message" {
    var buf: [1024]u8 = undefined;
    const msg = try Message.formatRequest(4, 567, 4321, &buf);
    const expected_payload = &[_]u8{
        0x00, 0x00, 0x00, 0x04, // index
        0x00, 0x00, 0x02, 0x37, // begin
        0x00, 0x00, 0x10, 0xe1, // length
    };
    const expected_msg = Message{ .id = .Request, .payload = expected_payload };

    try testing.expectEqual(expected_msg.id, msg.id);
    try testing.expectEqualSlices(u8, expected_msg.payload.?, msg.payload.?);
}

test "format HAVE Message" {
    var payload: [1024]u8 = undefined;
    const msg = try Message.formatHave(4, &payload);
    const expected_payload = &[_]u8{
        0x00, 0x00, 0x00, 0x04, // index
    };
    const expected_msg = Message{ .id = .Have, .payload = expected_payload };

    try testing.expectEqual(expected_msg.id, msg.id);
    try testing.expectEqualSlices(u8, expected_msg.payload.?, msg.payload.?);
}

test "marshalPiece OK" {
    var buf = [_]u8{0} ** 10;
    const payload = [_]u8{
        0x00, 0x00, 0x00, 0x04, // begin
        0x00, 0x00, 0x00, 0x02, //begin
        0xaa, 0xbb, 0xcc, 0xdd,
        0xee, 0xff, // block
    };
    const piece_msg = Message{ .id = .Piece, .payload = &payload };
    const piece_data_len = try piece_msg.marshalPiece(&buf, 4);
    try testing.expectEqual(6, piece_data_len);

    const expect_buf = [_]u8{
        0x00, 0x00, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00, 0x00,
    };

    try testing.expectEqualSlices(u8, &expect_buf, &buf);
}

test "marshalHave OK" {
    const payload = [_]u8{
        0x00, 0x00, 0x00, 0x04, // begin
    };
    const have_msg = Message{ .id = .Have, .payload = &payload };
    const index = try have_msg.marshalHave();
    try testing.expectEqual(4, index);
}

test "serialize OK" {
    const payload = [_]u8{ 1, 2, 3, 4 };
    const input_msg = Message{ .id = .Have, .payload = payload[0..] };
    const output_expected = [_]u8{ 0, 0, 0, 5, 4, 1, 2, 3, 4 };

    var buf: [1024]u8 = undefined;
    const actual = try input_msg.serialize(&buf);
    try testing.expectEqualSlices(u8, output_expected[0..], actual);

    // const keepalive: ?Message = null;

    const output_keepalive_expected = [_]u8{ 0, 0, 0, 0 };

    const actual_keepalive_out = try Message.serialize(null, &buf);
    try testing.expectEqualSlices(u8, output_keepalive_expected[0..], actual_keepalive_out);
}
test "deserialize OK" {
    const input = [_]u8{ 0, 0, 0, 5, 4, 1, 2, 3, 4 };
    const output_msg = Message{ .id = .Have, .payload = &[_]u8{ 1, 2, 3, 4 } };

    const msg = Message.deserialize(&input).?;

    try testing.expectEqual(output_msg.id, msg.id);
    try testing.expectEqualSlices(u8, output_msg.payload.?, msg.payload.?);
}
