const std = @import("std");
const testing = std.testing;
const print = std.debug.print;

const bencode = @import("zig-bencode");
const TorrentFile = struct {
    announce: []const u8 = undefined,
    comment: []const u8 = undefined,
    creation_date: u64 = undefined,
    http_seeds: [][]const u8 = undefined,
    info: TorrentInfo = undefined,
};

const TorrentInfo = struct {
    length: u8,
    name: []const u8,
    piece_length: []const u8,
    pieces: []const u8,
};

pub fn parseTorrentFile(allocator: std.mem.Allocator, file_path: []const u8) !TorrentFile {
    const torrent_file = try std.fs.openFileAbsolute(file_path, .{});
    defer torrent_file.close();
    const file_content = try torrent_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_content);

    var parsedTree = try bencode.ValueTree.parse(file_content, allocator);
    defer parsedTree.deinit();

    print("torrent_file = {s}, file_size = {}", .{ file_path, file_path.len });
    return TorrentFile{ .creation_date = 100 };
}
test "parse torrent file" {
    _ = try parseTorrentFile(testing.allocator, "/Users/duyquang6/zig/zigtor/zig-bencode/input/ubuntu-20.04-desktop-amd64.iso.torrent");
}

pub fn main() void {}
