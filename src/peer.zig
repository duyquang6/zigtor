const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const bencode = @import("bencode.zig");

pub const ParsePeerError = error{MalformPeerData};

pub const PeerIPv4 = struct {
    ip: u32,
    port: u16,

    fn parse(allocator: std.mem.Allocator, peer_bin: []const u8) ![]PeerIPv4 {
        const peer_size = 6;
        const num_peers = peer_bin.len / peer_size;
        if (peer_bin.len % peer_size != 0) {
            return ParsePeerError.MalformPeerData;
        }

        var peers_arr = std.ArrayList(PeerIPv4).init(allocator);
        defer peers_arr.deinit();

        for (0..num_peers) |i| {
            const offset = i * peer_size;
            const ip = std.mem.readVarInt(u32, peer_bin[offset .. offset + 4], std.builtin.Endian.big);
            const port = std.mem.readVarInt(u16, peer_bin[offset + 4 .. offset + 6], std.builtin.Endian.big);

            try peers_arr.append(.{
                .ip = ip,
                .port = port,
            });
        }
        return peers_arr.toOwnedSlice();
    }
};

const PeerIPv6 = struct {};

const Peer = union(enum) {
    PeerV4: PeerIPv4,
    PeerV6: PeerIPv6,

    fn connect(self: Peer) !void {
        switch (self) {
            .PeerV4 => |val| {
                _ = val;
            },
            .PeerV6 => |_| {
                // TODO: not supported yet
                unreachable;
            },
        }
    }
};

fn print_peers(ps: []PeerIPv4) void {
    for (ps) |p| {
        print("\n", .{});
        print_ip(p.ip);
        std.debug.print("port={}", .{
            p.port,
        });
    }
    std.debug.print("\n", .{});
}

fn print_ip(ip: u32) void {
    var bitmask: u32 = std.math.maxInt(u32);
    inline for (0..4) |i| {
        const next_bitmask: u32 = bitmask >> 8;
        print("{}{s}", .{ (ip & (bitmask - next_bitmask)) >> (3 - i) * 8, "." });
        bitmask = next_bitmask;
    }
}

test "parse peer v4 binary" {
    const announce_file_path = "/home/ligt/zig/zigtor/announce_data";
    const announce_file = try std.fs.openFileAbsolute(announce_file_path, .{});
    defer announce_file.close();
    const announce_file_content = try announce_file.readToEndAlloc(testing.allocator, std.math.maxInt(usize));
    defer testing.allocator.free(announce_file_content);

    var announce_tree = try bencode.ValueTree.parse(announce_file_content, testing.allocator);
    defer announce_tree.deinit();

    const peers_binary = bencode.mapLookup(announce_tree.root.Map, "peers").?.String;

    const peers = try PeerIPv4.parse(testing.allocator, peers_binary);
    std.debug.print("\npeer_size={}\n", .{peers.len});
    print_peers(peers);

    defer testing.allocator.free(peers);
}
