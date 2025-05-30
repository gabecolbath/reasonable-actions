const std = @import("std");
const conf = @import("config.zig");
const game = @import("game.zig");

const Html = []const u8;

pub const index: Html = @embedFile("html/index.html");
pub const scatty_index: Html = @embedFile("html/scatty-index.html");
pub const player_create_name: Html = @embedFile("html/player-create-name.html");
pub const room_list_item: Html = @embedFile("html/room-list-item.html");
pub const scatty_room: Html = @embedFile("html/scatty-room.html");
pub const scatty_game: Html = @embedFile("html/scatty-game.html");
pub const scatty_base_options: Html = @embedFile("html/scatty-base-options.html");
