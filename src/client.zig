const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const net = std.net;
const handshake = @import("handshake.zig");
const message = @import("message.zig");
const peer = @import("peer.zig");

const ClientError = error{InvalidMessageID};
pub const Client = struct {
    conn: std.net.Stream,
    peer_id: [20]u8,
    info_hash: [20]u8,
    bitfield: []u8,
    choked: bool,

    pub fn init(p: peer.PeerIPv4, peer_id: [20]u8, info_hash: [20]u8) !Client {
        const addr = p.to_address();
        var conn = try std.net.tcpConnectToAddress(addr);
        errdefer conn.close();

        _ = try completeHandshake(conn, info_hash, peer_id);
        const bf = try receiveBitfield(conn);

        return .{ .conn = conn, .peer_id = peer_id, .info_hash = info_hash, .bitfield = bf, .choked = true };
    }

    pub fn read(self: Client) !?message.Message {
        var input_buf: [1024]u8 = undefined;
        _ = try self.conn.read(&input_buf);
        return message.Message.deserialize(&input_buf);
    }

    pub fn sendRequest(self: Client, index: u32, begin: u32, length: u32) !void {
        var buf: [1024]u8 = undefined;
        const msg = try message.Message.formatRequest(index, begin, length, &buf);
        var buffer: [1024]u8 = undefined;
        const send_data = try msg.serialize(&buffer);
        _ = try self.conn.write(send_data);
    }

    pub fn sendInterested(self: Client) !void {
        const msg = message.Message{
            .id = .Interested,
        };
        var buffer: [1024]u8 = undefined;
        const send_data = try msg.serialize(&buffer);
        _ = try self.conn.write(send_data);
    }

    pub fn sendNotInterested(self: Client) !void {
        const msg = message.Message{ .id = .NotInterested };
        var buffer: [1024]u8 = undefined;
        const send_data = try msg.serialize(&buffer);
        _ = try self.conn.write(send_data);
    }

    pub fn sendUnchoke(self: Client) !void {
        const msg = message.Message{
            .id = .Unchoke,
        };
        var buffer: [1024]u8 = undefined;
        const send_data = try msg.serialize(&buffer);
        _ = try self.conn.write(send_data);
    }

    pub fn sendHave(self: Client, index: u32) !void {
        var buf: [1024]u8 = undefined;
        const msg = try message.Message.formatHave(index, &buf);
        var buffer: [1024]u8 = undefined;
        const send_data = try msg.serialize(&buffer);
        _ = try self.conn.write(send_data);
    }
};

const TestServer = struct {
    fn init() !net.Server {
        const localhost = try net.Address.parseIp("127.0.0.1", 0);
        const server = try localhost.listen(.{});
        std.debug.print("\nserver_address={}\n", .{server.listen_address});

        return server;
    }

    fn deinit(self: *TestServer) void {
        self.server.deinit();
    }

    fn acceptConn(self: *net.Server, expected: ?[]const u8, payload: ?[]const u8) !void {
        std.debug.print("\naccepting connection\n", .{});
        // handle logic connection
        var conn = try self.accept();
        defer conn.stream.close();

        if (expected) |v| {
            var buf: [1024]u8 = undefined;
            const msg_size = try conn.stream.read(&buf);
            try testing.expectEqualSlices(u8, v, buf[0..msg_size]);
        }

        if (payload) |v| {
            _ = try conn.stream.write(v);
        }
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

    const t = try std.Thread.spawn(.{}, TestServer.sendMsgToServer, .{ server.listen_address, "SYN"[0..] });
    defer t.join();

    try TestServer.acceptConn(&server, "SYN", "ACK");
}

test "read OK" {
    var server = try TestServer.init();
    defer server.deinit();

    const S = struct {
        fn read(address: net.Address) !void {
            var conn = try net.tcpConnectToAddress(address);
            defer conn.close();

            const client = Client{ .conn = conn, .peer_id = undefined, .info_hash = undefined, .bitfield = undefined, .choked = undefined };
            const msg = (try client.read()).?;

            try testing.expectEqualSlices(u8, &[_]u8{
                0x00, 0x00, 0x05, 0x3c,
            }, msg.payload.?);
        }
    };

    const t = try std.Thread.spawn(.{}, S.read, .{server.listen_address});
    defer t.join();

    try TestServer.acceptConn(&server, null, &[_]u8{
        0x00, 0x00, 0x00, 0x05,
        4,    0x00, 0x00, 0x05,
        0x3c,
    });
}

test "sendHave OK" {
    var server = try TestServer.init();
    defer server.deinit();

    const S = struct {
        fn send(address: net.Address) !void {
            var conn = try net.tcpConnectToAddress(address);
            defer conn.close();

            const client = Client{ .conn = conn, .peer_id = undefined, .info_hash = undefined, .choked = undefined, .bitfield = undefined };

            _ = try client.sendHave(1340);
            print("\nclose conn\n", .{});
        }
    };

    const t = try std.Thread.spawn(.{}, S.send, .{server.listen_address});
    defer t.join();

    try TestServer.acceptConn(&server, &[_]u8{
        0x00, 0x00, 0x00, 0x05,
        4,    0x00, 0x00, 0x05,
        0x3c,
    }, null);
}

test "sendNotInterested OK" {
    const localhost = try net.Address.parseIp("127.0.0.1", 0);
    var server = try localhost.listen(.{});

    defer server.deinit();

    const S = struct {
        fn send(address: net.Address) !void {
            var conn = try net.tcpConnectToAddress(address);
            defer conn.close();

            const client = Client{ .conn = conn, .peer_id = undefined, .info_hash = undefined, .choked = undefined, .bitfield = undefined };

            _ = try client.sendNotInterested();
            print("\nclose conn\n", .{});
        }
    };

    const t = try std.Thread.spawn(.{}, S.send, .{server.listen_address});
    defer t.join();

    try TestServer.acceptConn(&server, &[_]u8{
        0x00, 0x00, 0x00, 0x01,
        3,
    }, null);
}

test "sendInterested OK" {
    var server = try TestServer.init();
    defer server.deinit();

    const S = struct {
        fn send(address: net.Address) !void {
            var conn = try net.tcpConnectToAddress(address);
            defer conn.close();

            const client = Client{ .conn = conn, .peer_id = undefined, .info_hash = undefined, .choked = undefined, .bitfield = undefined };

            _ = try client.sendInterested();
            print("\nclose conn\n", .{});
        }
    };

    const t = try std.Thread.spawn(.{}, S.send, .{server.listen_address});
    defer t.join();

    try TestServer.acceptConn(&server, &[_]u8{
        0x00, 0x00, 0x00, 0x01,
        2,
    }, null);
}

test "sendUnchoke OK" {
    var server = try TestServer.init();
    defer server.deinit();

    const S = struct {
        fn send(address: net.Address) !void {
            var conn = try net.tcpConnectToAddress(address);
            defer conn.close();

            const client = Client{ .conn = conn, .peer_id = undefined, .info_hash = undefined, .choked = undefined, .bitfield = undefined };

            _ = try client.sendUnchoke();
            print("\nclose conn\n", .{});
        }
    };

    const t = try std.Thread.spawn(.{}, S.send, .{server.listen_address});
    defer t.join();

    try TestServer.acceptConn(&server, &[_]u8{
        0x00, 0x00, 0x00, 0x01,
        1,
    }, null);
}

test "sendRequest OK" {
    var server = try TestServer.init();
    defer server.deinit();

    const S = struct {
        fn send(address: net.Address) !void {
            var conn = try net.tcpConnectToAddress(address);
            defer conn.close();

            const client = Client{ .conn = conn, .peer_id = undefined, .info_hash = undefined, .choked = undefined, .bitfield = undefined };

            _ = try client.sendRequest(1, 2, 3);
            print("\nclose conn\n", .{});
        }
    };

    const t = try std.Thread.spawn(.{}, S.send, .{server.listen_address});
    defer t.join();

    try TestServer.acceptConn(&server, &[_]u8{
        0x00, 0x00, 0x00, 0x0d,
        6,    0x00, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00,
        0x03,
    }, null);
}

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
//
test "completeHandshake OK" {
    const localhost = try net.Address.parseIp("127.0.0.1", 0);
    var psrv = try localhost.listen(.{});
    // var psrv = try TestServer.init();
    defer psrv.deinit();

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
    const t = try std.Thread.spawn(.{}, S.completeHandshakeSend, .{ psrv.listen_address, info_hash, peer_id });
    defer t.join();

    try TestServer.acceptConn(
        &psrv,
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

        return v.payload.?;
    }

    return ClientError.InvalidMessageID;
}

test "receiveBitfield OK" {
    const localhost = try net.Address.parseIp("127.0.0.1", 0);
    var server = try localhost.listen(.{});

    const S = struct {
        fn testReceiveBitfield(address: net.Address) !void {
            var conn = try net.tcpConnectToAddress(address);
            defer conn.close();

            _ = try receiveBitfield(conn);
        }
    };

    const server_send_data = [_]u8{ 0x00, 0x00, 0x00, 0x06, 5, 1, 2, 3, 4, 5 };
    const t = try std.Thread.spawn(.{}, S.testReceiveBitfield, .{server.listen_address});
    defer t.join();

    try TestServer.acceptConn(
        &server,
        null,
        &server_send_data,
    );
}
