const std = @import("std");
const conf = @import("config.zig");

pub const index: []const u8 = @embedFile("html/index.html");
pub const scatty_index: []const u8 = @embedFile("html/scatty-index.html");
pub const player_create_name: []const u8 = @embedFile("html/player-create-name.html");
pub const room_list_item: []const u8 = @embedFile("html/room-list-item.html");
pub const scatty_room: []const u8 = @embedFile("html/scatty-room.html");
pub const scatty_game: []const u8 = @embedFile("html/scatty-game.html");
