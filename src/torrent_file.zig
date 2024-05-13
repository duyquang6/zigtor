const std = @import("std");
const testing = std.testing;
const print = std.debug.print;

const bencode = @import("zig-bencode.zig");
const TorrentFile = struct {
    announce_list: [][]const u8 = undefined,
    comment: []const u8 = undefined,
    creation_date: u64 = undefined,
    http_seeds: [][]const u8 = undefined,
    info: TorrentInfo = undefined,
};

const TorrentInfo = struct {
    length: u64 = undefined,
    name: []const u8 = undefined,
    piece_length: []const u8 = undefined,
    pieces: []const u8 = undefined,
};

pub fn parseTorrentFile(allocator: std.mem.Allocator, file_path: []const u8) !TorrentFile {
    const torrent_file = try std.fs.openFileAbsolute(file_path, .{});
    defer torrent_file.close();
    const file_content = try torrent_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_content);

    var parsedTree = try bencode.ValueTree.parse(file_content, allocator);
    defer parsedTree.deinit();

    print("torrent_file = {s}, file_size = {}\n", .{ file_path, file_path.len });
    const creation_date = bencode.mapLookup(parsedTree.root.Map, "creation date").?.Integer;
    const comment = bencode.mapLookup(parsedTree.root.Map, "comment").?.String;

    var comment_owned = std.ArrayList(u8).init(allocator);
    defer comment_owned.deinit();
    try comment_owned.appendSlice(comment);

    // Parse torrent info
    const torrent_info_map = bencode.mapLookup(parsedTree.root.Map, "info").?.Map;
    const name = bencode.mapLookup(torrent_info_map, "name").?.String;

    var name_owned = std.ArrayList(u8).init(allocator);
    defer name_owned.deinit();
    try name_owned.appendSlice(name);

    const length = bencode.mapLookup(torrent_info_map, "length").?.Integer;

    const torrent_info: TorrentInfo = .{ .length = @as(i64, length) };

    return TorrentFile{ .creation_date = @intCast(creation_date), .comment = try comment_owned.toOwnedSlice(), .info = torrent_info };
}
test "parse torrent file" {
    const torrent_file = try parseTorrentFile(testing.allocator, "/home/ligt/zig/zigtor/zig-bencode/input/ubuntu-20.04-desktop-amd64.iso.torrent");
    defer testing.allocator.free(torrent_file.comment);

    try testing.expectEqual(1587649533, torrent_file.creation_date);
    try testing.expectEqualStrings(
        "Ubuntu CD releases.ubuntu.com",
        torrent_file.comment,
    );
}

pub fn main() void {}
