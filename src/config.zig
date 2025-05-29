const std = @import("std");

// Server
pub const port = 8801;
pub const index_view = @embedFile("html/index.html");

// App
pub const max_total_members = 100;
pub const max_members_per_room = 8;
pub const max_total_rooms = 100;

// Game
pub const base_categories_list = @embedFile(categories_list_filepath ++ "base.txt");
pub const custom_categories_filepath = @as(usize, categories_list_filepath ++ "custom.txt");
pub const categories_list_filepath = @as([]const u8, "categories/");
pub const max_players_per_game = max_members_per_room;
pub const max_category_len = 128;
pub const max_num_categories = 256;
pub const max_categories_list_size = max_category_len * max_num_categories;
pub const max_answer_len = 128;
pub const valid_letters: []const u8 = "ABCDEFGHIJKLMNOPRSTW";
