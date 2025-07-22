const config = @import("config.zig");

pub const game_player_limit = config.server.room_member_limit;
pub const game_limit = config.server.room_limit;
pub const player_limit = config.server.member_limit; 
