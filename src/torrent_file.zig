const std = @import("std");
const testing = std.testing;
const print = std.debug.print;

const bencode = @import("bencode.zig");
pub const TorrentFile = struct {
    allocator: std.mem.Allocator,
    announce_list: [][]const u8 = undefined,
    comment: []const u8 = undefined,
    creation_date: u64 = undefined,
    length: u64 = undefined,
    name: []const u8 = undefined,
    info_hash: []const u8 = undefined,
    piece_length: u64 = undefined,
    pieces: []const u8 = undefined,

    fn deinit(self: *TorrentFile) void {
        self.allocator.free(self.comment);
        self.allocator.free(self.announce_list);
        self.allocator.free(self.name);
        self.allocator.free(self.info_hash);
        self.allocator.free(self.pieces);
    }

    fn parse(allocator: std.mem.Allocator, file_path: []const u8) !TorrentFile {
        const torrent_file = try std.fs.openFileAbsolute(file_path, .{});
        defer torrent_file.close();
        const file_content = try torrent_file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(file_content);

        var parsedTree = try bencode.ValueTree.parse(file_content, allocator);
        defer parsedTree.deinit();
        const root_map = parsedTree.root.Map;

        const creation_date = bencode.mapLookup(root_map, "creation date").?.Integer;
        const comment = bencode.mapLookup(root_map, "comment").?.String;
        const announce_arr = bencode.mapLookup(root_map, "announce-list").?.Array;

        var announce_urls = std.ArrayList([]const u8).init(allocator);
        defer announce_urls.deinit();
        for (announce_arr.items) |item| {
            const urls = item.Array;
            if (urls.items.len != 1) unreachable;

            for (urls.items) |url| {
                try announce_urls.append(url.String);
            }
        }

        var comment_al = std.ArrayList(u8).init(allocator);
        defer comment_al.deinit();
        try comment_al.appendSlice(comment);

        // Parse torrent info
        const torrent_info_field = bencode.mapLookup(root_map, "info").?;
        const torrent_info_map = torrent_info_field.Map;

        const name = bencode.mapLookup(torrent_info_map, "name").?.String;
        var name_al = std.ArrayList(u8).init(allocator);
        defer name_al.deinit();
        try name_al.appendSlice(name);

        const length = bencode.mapLookup(torrent_info_map, "length").?.Integer;

        const piece_length: u64 = @intCast(bencode.mapLookup(torrent_info_map, "piece length").?.Integer);

        const pieces = bencode.mapLookup(torrent_info_map, "pieces").?.String;
        var piece_al = std.ArrayList(u8).init(allocator);
        defer piece_al.deinit();
        try piece_al.appendSlice(pieces);

        var info_bencoded = std.ArrayList(u8).init(allocator);
        defer info_bencoded.deinit();
        try torrent_info_field.stringifyValue(info_bencoded.writer());

        print("torrent_file = {s}, file_size = {}, piece_length = {}, piece_hash_len = {}\n", .{ file_path, file_path.len, piece_length, pieces.len });

        return TorrentFile{
            .creation_date = @intCast(creation_date),
            .comment = try comment_al.toOwnedSlice(),
            .length = @intCast(length),
            .name = try name_al.toOwnedSlice(),
            .allocator = allocator,
            .piece_length = piece_length,
            .pieces = try piece_al.toOwnedSlice(),
            .announce_list = try announce_urls.toOwnedSlice(),
            .info_hash = try info_bencoded.toOwnedSlice(),
        };
    }

    // fn buildTrackerURL(self: *TorrentFile, peer_id: [20]u8) void {}
};

test "parse torrent file" {
    var torrent_file = try TorrentFile.parse(testing.allocator, "/home/ligt/zig/zigtor/zig-bencode/input/ubuntu-20.04-desktop-amd64.iso.torrent");
    defer torrent_file.deinit();

    try testing.expectEqual(1587649533, torrent_file.creation_date);
    try testing.expectEqualStrings(
        "Ubuntu CD releases.ubuntu.com",
        torrent_file.comment,
    );
    try testing.expectEqualStrings("ubuntu-20.04-desktop-amd64.iso", torrent_file.name);
    try testing.expectEqual(2, torrent_file.announce_list.len);
}
