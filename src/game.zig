const std = @import("std");
const conf = @import("config.zig");

const random = std.crypto.random;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub const Scene = enum {
    lobby,
    reviewing,
    answering,
    voting,
    winning,
};

pub const Options = struct {
    rounds: u8 = 3,
    categories_per_round: u8 = 12,
    repeat_categories: bool = true,
    answering_time_limit: u16 = 120,
    voting_time_limit: ?u16 = null,
    special_points: bool = true,
};
