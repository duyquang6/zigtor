const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const net = std.net;
const handshake = @import("handshake.zig");
const message = @import("message.zig");

const ClientError = error{InvalidMessageID};
pub const Client = struct {
    peer_id: [20]u8,
    info_hash: [20]u8,
};

fn completeHandshake(stream: std.net.Stream, info_hash: [20]u8, peer_id: [20]u8) !handshake.Handshake {
    const req = handshake.Handshake{ .peer_id = peer_id, .info_hash = info_hash };
    const send_bytes = req.serialize();

    _ = try stream.write(&send_bytes);

    var buf: [256]u8 = undefined;

    _ = try stream.read(&buf);

    const res = try handshake.Handshake.deserialize(&buf);

    if (!std.mem.eql(u8, &req.info_hash, &res.info_hash)) {
        return handshake.HandshakeError.InvalidData;
    }

    return res;
}

test "completeHandshake OK" {
    var psrv = try TestServer.init();
    defer psrv.deinit();

    std.debug.print("\nserver_address={}\n", .{psrv.server.listen_address});

    const S = struct {
        fn completeHandshakeSend(address: net.Address, info_hash: [20]u8, peer_id: [20]u8) !void {
            var conn = try net.tcpConnectToAddress(address);
            defer conn.close();

            _ = try completeHandshake(conn, info_hash, peer_id);
        }
    };

    const info_hash = [_]u8{ 134, 212, 200, 0, 36, 164, 105, 190, 76, 80, 188, 90, 16, 44, 247, 23, 128, 49, 0, 116 };
    const peer_id = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 };
    const server_handshake = [_]u8{ 19, 66, 105, 116, 84, 111, 114, 114, 101, 110, 116, 32, 112, 114, 111, 116, 111, 99, 111, 108, 0, 0, 0, 0, 0, 0, 0, 0, 134, 212, 200, 0, 36, 164, 105, 190, 76, 80, 188, 90, 16, 44, 247, 23, 128, 49, 0, 116, 45, 83, 89, 48, 48, 49, 48, 45, 192, 125, 147, 203, 136, 32, 59, 180, 253, 168, 193, 19 };
    const client_handshake = [_]u8{ 19, 66, 105, 116, 84, 111, 114, 114, 101, 110, 116, 32, 112, 114, 111, 116, 111, 99, 111, 108, 0, 0, 0, 0, 0, 0, 0, 0, 134, 212, 200, 0, 36, 164, 105, 190, 76, 80, 188, 90, 16, 44, 247, 23, 128, 49, 0, 116, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 };
    const t = try std.Thread.spawn(.{}, S.completeHandshakeSend, .{ psrv.server.listen_address, info_hash, peer_id });
    defer t.join();

    try TestServer.acceptConn(
        psrv,
        &client_handshake,
        &server_handshake,
    );
}

fn receiveBitfield(stream: net.Stream) ![]const u8 {
    var input_buf: [1024]u8 = undefined;

    _ = try stream.read(&input_buf);

    const msg = message.Message.deserialize(&input_buf);
    if (msg) |v| {
        if (v.id != message.MessageEnum.Bitfield) {
            return ClientError.InvalidMessageID;
        }

        return v.payload;
    }

    return ClientError.InvalidMessageID;
}

const TestServer = struct {
    server: *net.Server,
    fn init() !TestServer {
        const localhost = try net.Address.parseIp("127.0.0.1", 0);
        var server = try localhost.listen(.{});

        return TestServer{ .server = &server };
    }

    fn deinit(self: *TestServer) void {
        self.server.deinit();
    }

    fn acceptConn(self: TestServer, expected: []const u8, payload: []const u8) !void {
        std.debug.print("\naccepting connection\n", .{});
        // handle logic connection
        var conn = try self.server.accept();
        defer conn.stream.close();

        var buf: [1024]u8 = undefined;
        const msg_size = try conn.stream.read(&buf);

        try testing.expectEqualSlices(u8, expected, buf[0..msg_size]);

        _ = try conn.stream.write(payload);
    }

    fn sendMsgToServer(server_address: net.Address, payload: []const u8) !void {
        std.debug.print("\nstart send msg\n", .{});
        // connect to server
        const conn = try net.tcpConnectToAddress(server_address);
        defer conn.close();

        std.debug.print("\nstart write conn msg\n", .{});
        _ = try conn.write(payload);

        std.debug.print("\nstart read conn msg\n", .{});
        // initialize a buffer to keep the server response
        var buf: [1024]u8 = undefined;
        const size = try conn.read(buf[0..]);

        std.debug.print("\nSize={},ResponseBuffer={s}\n", .{ size, buf[0..size] });
    }
};

test "listen on a port, send bytes, receive bytes" {
    var server = try TestServer.init();
    defer server.deinit();
    std.debug.print("\nserver_address={}\n", .{server.server.listen_address});

    const t = try std.Thread.spawn(.{}, TestServer.sendMsgToServer, .{ server.server.listen_address, "SYN"[0..] });
    defer t.join();

    try TestServer.acceptConn(server, "SYN", "ACK");
}
