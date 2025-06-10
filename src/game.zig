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

pub const GameOptions = struct {
    rounds: u8 = 3,
    categories_per_round: u8 = 12,
    repeat_categories: bool = true,
    answering_time_limit: u16 = 120,
    voting_time_limit: ?u16 = null,
    alliteration_points: bool = true,
    scoring_mode: ScoringMode = .normal,
    weighted_scores: bool = false,
    
    pub const ScoringMode = enum {
        normal,
        creative,
    };

};

pub const GameState = struct {
    opts: GameOptions,

    const Self = @This();

    pub fn init(opts: GameOptions) Self {
        return Self{
            .opts = opts,
        };
    }
};
