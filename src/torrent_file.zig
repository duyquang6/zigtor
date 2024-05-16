const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const format = std.fmt.format;

const bencode = @import("bencode.zig");

const TorrentFileError = error{AnnounceURLNotFound};

pub const TorrentFile = struct {
    arena: std.heap.ArenaAllocator,
    announce_list: [][]const u8 = undefined,
    comment: []const u8 = undefined,
    creation_date: u64 = undefined,
    length: u64 = undefined,
    name: []const u8 = undefined,
    info_hash: [20]u8 = undefined,
    piece_length: u64 = undefined,
    pieces: []const u8 = undefined,

    fn deinit(self: *TorrentFile) void {
        self.arena.deinit();
    }

    fn parse(child_allocator: std.mem.Allocator, file_path: []const u8) !TorrentFile {
        var arena = std.heap.ArenaAllocator.init(child_allocator);
        const allocator = arena.allocator();

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
                try announce_urls.append(try allocator.dupe(u8, url.String));
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

        var info_hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(info_bencoded.items, info_hash[0..], .{});

        print("torrent_file = {s}, file_size = {}, piece_length = {}, piece_hash_len = {}\n", .{ file_path, file_path.len, piece_length, pieces.len });

        return TorrentFile{
            .creation_date = @intCast(creation_date),
            .comment = try comment_al.toOwnedSlice(),
            .length = @intCast(length),
            .name = try name_al.toOwnedSlice(),
            .arena = arena,
            .piece_length = piece_length,
            .pieces = try piece_al.toOwnedSlice(),
            .announce_list = try announce_urls.toOwnedSlice(),
            .info_hash = info_hash,
        };
    }

    fn buildTrackerURL(self: *TorrentFile, peer_id: *const [20]u8, port: u16) ![]const u8 {
        if (self.announce_list.len == 0) {
            return TorrentFileError.AnnounceURLNotFound;
        }

        const base_url = self.announce_list[0];

        var query = std.ArrayList(u8).init(self.arena.allocator());
        defer query.deinit();

        try format(query.writer(), "?info_hash={s}&peer_id={s}", .{ self.info_hash, peer_id });
        try format(query.writer(), "&port={}", .{port});
        try format(query.writer(), "&uploaded={}", .{0});
        try format(query.writer(), "&downloaded={}", .{0});
        try format(query.writer(), "&compact={}", .{1});
        try format(query.writer(), "&left={}", .{self.length});
        const start_url_index = query.items.len;
        // try query.appendSlice("https://tracker.gbitt.info:443/announce");
        try query.appendSlice(base_url);

        const query_uri_escape = std.Uri.Component{ .raw = query.items[0..start_url_index] };
        try query_uri_escape.format("query", .{}, query.writer());

        return (try query.toOwnedSlice())[start_url_index..];
    }
};
pub fn print_hex_bytes(bin_data: []u8) void {
    print("hex_bytes:0x", .{});
    for (bin_data) |h| {
        print("{x:0>2}", .{h});
    }
    print("\n", .{});
}
test "parse torrent file" {
    var torrent_file = try TorrentFile.parse(testing.allocator, "/home/ligt/zig/zigtor/[HorribleSubs] One Punch Man S2 - 01 [1080p].mkv.torrent");
    defer torrent_file.deinit();

    try testing.expectEqual(1554834963, torrent_file.creation_date);
    try testing.expectEqualStrings("[HorribleSubs] One Punch Man S2 - 01 [1080p].mkv", torrent_file.name);
    try testing.expectEqual(15, torrent_file.announce_list.len);

    const peer_id = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 };
    const tracker_url = try torrent_file.buildTrackerURL(&peer_id, 8080);
    print("tracker_url={s}\n", .{tracker_url});
    // try testing.expectEqualStrings("https://torrent.ubuntu.com/announce?info_hash=%9F%C2%0B%9E%98%EA%98%B4%A3%5Eb%23%04%1A%5E%F9N%A2x%09&peer_id=%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14&port=8080&uploaded=0&downloaded=0&compact=1&left=2715254784", tracker_url);
    // https://torrent.ubuntu.com/announce?compact=1&downloaded=0&info_hash=%9F%C2%0B%9E%98%EA%98%B4%A3%5Eb%23%04%1A%5E%F9N%A2x%09&left=2715254784&peer_id=%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14&port=8080&uploaded=0
    var client = std.http.Client{ .allocator = testing.allocator };
    defer client.deinit();
    _ = try client.fetch(.{ .location = .{ .url = tracker_url } });
}
