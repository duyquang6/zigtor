const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const peer = @import("peer.zig");
const client = @import("client.zig");
const message = @import("message.zig");
const MessageEnum = message.MessageEnum;
const bitfield = @import("bitfield.zig");

const MaxBlockSize = 16384;

const P2PError = error{ChecksumMismatch};

pub const Torrent = struct {
    peer: []peer.PeerIPv4,
    peer_id: [20]*const u8,
    info_hash: [20]*const u8,
    piece_hashes: [][20]*const u8,
    piece_length: u32,
    length: u32,
    name: []*const u8,

    fn calculateBoundsForPiece(self: Torrent, index: u32) struct {
        begin: u32,
        end: u32,
    } {
        const begin = index * self.piece_length;
        const end = if (begin + self.piece_length > self.length) self.length else begin + self.piece_length;

        return .{ begin, end };
    }

    fn calculatePieceSize(self: Torrent, index: u32) u32 {
        const r = try self.calculateBoundsForPiece(index);
        return r.end - r.begin;
    }

    fn startDownload(self: Torrent, p: peer.PeerIPv4) !void {
        // const c = client.Client{ .peer_id = self.peer_id, .info_hash = self.info_hash };
        _ = self;
        _ = p;
    }
};

const PieceProgress = struct {
    index: u32,
    client: *client.Client,
    buf: []u8,
    downloaded: u32,
    requested: u32,
    backlog: u32,

    fn readMessage(self: *PieceProgress) !void {
        const maybe_msg = try self.client.read();
        if (maybe_msg == null) {
            return;
        }

        const msg = maybe_msg.?;

        switch (msg.id) {
            MessageEnum.Unchoke => {
                self.client.choked = false;
            },
            MessageEnum.Choke => {
                self.client.choked = true;
            },
            MessageEnum.Have => {
                const index = try msg.parseHave();
                bitfield.setPiece(self.client.bitfield, index);
            },
            MessageEnum.Piece => {
                const n = try msg.parsePiece(self.buf, self.index);

                self.downloaded += n;
                self.backlog -= 1;
            },
        }
    }
};

const PieceWork = struct {
    index: u32,
    hash: [20]*const u8,
    length: u32,

    fn attemptDownloadOnePiece(self: *PieceWork, c: *client.Client) ![]const u8 {
        const state = PieceProgress{
            .buf = [_]u8{0} ** 1024,
            .index = self.index,
            .client = c,
        };

        // TODO: set timeout 30s for one piece data
        while (state.downloaded < self.length) {
            // retry until receive full data
            if (!state.client.choked) {
                var blocksize = MaxBlockSize;
                if (self.length - state.requested < blocksize) {
                    blocksize -= self.length - state.requested;
                }

                try c.sendRequest(self.index, state.requested, blocksize);
                state.backlog += 1;
                state.requested += blocksize;
            }

            try state.readMessage();
        }

        return state.buf;
    }

    fn checkIntegrity(self: PieceWork, buf: []u8) !void {
        const hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(buf, &hash, .{});
        if (!std.mem.eql(u8, hash, self.hash)) {
            return P2PError.ChecksumMismatch;
        }
    }
};

const PieceResult = struct {
    index: u32,
    buf: []u8,
};

// test "PieceProgress readMessage OK" {
//     const p = PieceProgress{ .index = 0, .client = &client.Client{}, .buf = undefined, .downloaded = undefined, .requested = undefined, .backlog = undefined };
//     try p.readMessage();
// }
