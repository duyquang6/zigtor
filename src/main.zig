const std = @import("std");

pub fn main() !void {}

test {
    _ = @import("torrent_file.zig");
    _ = @import("peer.zig");
    _ = @import("handshake.zig");
    _ = @import("message.zig");
    _ = @import("bitfield.zig");
    _ = @import("client.zig");
    // _ = @import("p2p.zig");
}
