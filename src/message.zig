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
    // MsgNotInterested expresses disinterest in receiving data
    NotInterested,
    // MsgHave alerts the receiver that the sender has downloaded a piece
    Have,
    // MsgBitfield encodes which pieces that the sender has downloaded
    Bitfield,
    // MsgRequest requests a block of data from the receiver
    Request,
    // MsgPiece delivers a block of data to fulfill a request
    Piece,
    // MsgCancel cancels a request
    Cancel,
};

// pub const Request = struct {
//     Message: Message,
// };

pub const Message = struct {
    id: MessageEnum,
    payload: []const u8,

    fn formatRequest(index: u32, begin: u32, length: u32) !Message {
        var payload = [_]u8{0} ** 12;
        std.mem.writeInt(u32, payload[0..4], index, std.builtin.Endian.big);
        std.mem.writeInt(u32, payload[4..8], begin, std.builtin.Endian.big);
        std.mem.writeInt(u32, payload[8..12], length, std.builtin.Endian.big);
        return Message{ .id = .Request, .payload = &payload };
    }

    fn formatHave(index: u32) !Message {
        var payload = [_]u8{0} ** 4;
        std.mem.writeInt(u32, payload[0..4], index, std.builtin.Endian.big);
        return Message{ .id = .Have, .payload = &payload };
    }

    fn marshalPiece(self: Message, buf: []u8, index: u32) !u32 {
        if (self.id != .Piece) {
            return MessageError.Invalid;
        }

        if (self.payload.len < 8) {
            return MessageError.Invalid;
        }

        const parsed_index = std.mem.readInt(u32, self.payload[0..4], std.builtin.Endian.big);
        if (parsed_index != index) {
            return MessageError.Invalid;
        }

        const begin = std.mem.readInt(u32, self.payload[4..8], std.builtin.Endian.big);
        if (begin >= buf.len) {
            return MessageError.Invalid;
        }

        const piece_data = self.payload[8..];
        if (begin + piece_data.len > buf.len) {
            return MessageError.Invalid;
        }
        std.mem.copyForwards(u8, buf[begin..], piece_data);

        return @intCast(piece_data.len);
    }

    fn marshalHave(self: Message) !u32 {
        if (self.id != .Have) {
            return MessageError.Invalid;
        }

        if (self.payload.len != 4) {
            return MessageError.Invalid;
        }

        const parsed_index = std.mem.readInt(u32, self.payload[0..4], std.builtin.Endian.big);

        return @intCast(parsed_index);
    }

    fn serialize(self: Message) []const u8 {
        _ = self;
        return undefined;
    }
};

test "format REQUEST Message" {
    const msg = try Message.formatRequest(4, 567, 4321);
    const expected_payload = &[_]u8{
        0x00, 0x00, 0x00, 0x04, // index
        0x00, 0x00, 0x02, 0x37, // begin
        0x00, 0x00, 0x10, 0xe1, // length
    };
    const expected_msg = Message{ .id = .Request, .payload = expected_payload };

    try testing.expectEqual(expected_msg.id, msg.id);
    try testing.expectEqualSlices(u8, expected_msg.payload, msg.payload);
}

test "format HAVE Message" {
    const msg = try Message.formatHave(4);
    const expected_payload = &[_]u8{
        0x00, 0x00, 0x00, 0x04, // index
    };
    const expected_msg = Message{ .id = .Have, .payload = expected_payload };

    try testing.expectEqual(expected_msg.id, msg.id);
    try testing.expectEqualSlices(u8, expected_msg.payload, msg.payload);
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
