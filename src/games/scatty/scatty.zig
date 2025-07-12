const std = @import("std");


const games = @import("../games.zig");
const renders = @import("render.zig");
const updates = @import("update.zig");
const starts = @import("start.zig");
const categories = @import("categories.zig");


const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged; 


const Event = games.Event;
const EventMap = games.EventMap;
const GameInterface = games.Game;
const Sources = games.RoomSource;
const Controller = GameInterface.Controller;
const GameSetup = GameInterface.Setup;
const Scene = GameInterface.Scene;
const View = GameInterface.View;


pub const Options = struct {
    rounds: u8 = 3,
    categories_per_round: u8 = 12,
    repeat_categories: bool = true,
    answering_time_limit: u16 = 120,
    voting_time_limit: ?u16 = null,
    alliteration_points: bool = true,
    weighted_scores: bool = true,
    show_names: bool = true,

    const ScoringMode = enum { 
        normal, creative 
    };
};


pub const State = struct {
    pub const Game = struct {
        round: u8 = 0,
        categories: categories.Round,
    };

    pub const Player = struct {
        score: Score = .{},
        answers: Answers,

        const Score = struct {
            round: u16 = 0,
            game: u16 = 0,
            cumulative: u16 = 0,
        };

        const Answers = struct {
            arena: ArenaAllocator,
            list: ArrayListUnmanaged([]const u8) = .{},  

            pub fn load(self: *Answers, allocator: Allocator, ans: [][]const u8) !void {
                self.list.ensureTotalCapacity(allocator, self.list.items.len + ans.len);
                for (ans) |answer| {
                    const processed = self.arena.allocator().dupe(u8, answer) catch "";
                    self.list.appendAssumeCapacity(processed);
                }
            }

            pub fn clear(self: *Answers, allocator: Allocator) void {
                self.list.clearAndFree(allocator);
                _ = self.arena.reset(.free_all);
            }
        };

    };
};

pub const controllers = Controller{
    .setup = setup,
    .start = start,
    .end = end,
};


pub fn setup(allocator: Allocator) !GameSetup {
    const opts = try allocator.create(Options);
    errdefer allocator.destroy(opts);
    opts.* = Options{};

    const state = try allocator.create(State.Game);
    errdefer allocator.destroy(state);
    state.* = State.Game{ .round = try categories.Round.init(allocator, opts) };

    return GameSetup{
        .opts = opts,
        .state = state,
    };
}


pub fn start(_: Allocator, _: Sources) !Scene {
    return Scene{ 
        .start = starts.lobby,
        .update = updates.lobby,
        .render = renders.lobby,
    };
}

pub fn end(_: Allocator, data: GameSetup) !void {
    const resolved_state: State.Game = @ptrCast(@alignCast(data.state));
    resolved_state.categories.deinit();
}
