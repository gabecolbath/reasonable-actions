const std = @import("std");
const games = @import("../games.zig");
const server = @import("../../server.zig");
const categories = @import("categories.zig");
const command = @import("../../command.zig");
const mustache = @import("mustache");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Client = server.Client;
const Command = command.Command;
const CommandMap = command.CommandMap;
const CommandHandler = command.Handler;
const Game = games.Game;
const Player = games.Player;


const Options = struct {
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


pub const PlayerState = struct {
    score: Score = .{},
    answers: [][]const u8,

    const Self = @This(); 
    
    const Score = struct {
        round: u16 = 0,
        game: u16 = 0,
        cumulative: u16 = 0,
    };

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        
        var answers = try allocator.alloc([]const u8, 1);
        answers[0] = "test";
        self.* = .{ .answers = answers };
        
        return self; 
    }

    pub fn deinit(ptr: *anyopaque, allocator: Allocator) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        for (self.answers) |answer| {
            allocator.free(answer);
        }
        allocator.free(self.answers);
        allocator.destroy(self);
    }
}; 


pub const GameState = struct {
    opts: Options = .{},
    round: u8 = 0,
    categories: categories.Round,

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{ .categories = try categories.Round.init(allocator, .{
            .method = if (self.opts.repeat_categories) .repeat else .no_repeat,
            .num_categories = @intCast(self.opts.categories_per_round),
        }) };
        
        return self; 
    }

    pub fn deinit(ptr: *anyopaque, allocator: Allocator) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.categories.deinit();
        
        allocator.destroy(self); 
    }
};


const Updates = struct {
    fn lobby(_: Allocator, source: *Client) !?Game.Scene {
        const room = try source.room();
        if (!room.isHost(source.uid.member)) {
            return games.GameError.UnauthorizedAction; 
        }
    
        return Game.Scene{ .views = Renderers.answering };
    }

    fn answering(allocator: Allocator, source: *Client) !?Game.Scene {
        _ = allocator;
        _ = source;
    }

    fn voting(allocator: Allocator, source: *Client) !?Game.Scene {
        _ = allocator;
        _ = source; 
    }

    fn scoring(allocator: Allocator, source: *Client) !?Game.Scene {
        _ = allocator;
        _ = source;
    }
};


const Renderers = struct {
    fn lobby(allocator: Allocator, source: *Client) !Game.Render {
        _ = allocator;
        _ = source;
        return Game.Render{};
    }

    fn answering(allocator: Allocator, source: *Client) !Game.Render {
        _ = allocator;
        _ = source;
        return Game.Render{};
    }
};

pub const Commanads = struct {
    pub var map = CommandMap.initComptime(.{
        .{ "start", start },
        .{ "update", update },
    });

    fn update(allocator: Allocator, cmd: Command) !void {
        _ = allocator;
        _ = cmd;
    }

    fn start(allocator: Allocator, cmd: Command) !void {
        const lobby_template: []const u8 = @embedFile("html/lobby.html");
        
        const source_room = try cmd.source.room();
        const source_game = source_room.game orelse return server.ServerError.NoRunningGame;
        const state: *GameState = @ptrCast(@alignCast(source_game.state)); 

        const lobby = try mustache.allocRenderText(allocator, lobby_template, .{
            .is_host = false,
            .opt = .{
                .round = state.opts.rounds,
                .categories_per_round = state.opts.categories_per_round,
                .repeat_categories = state.opts.repeat_categories,
                .answering_time_limit = state.opts.answering_time_limit,
                .voting_time_limit = state.opts.voting_time_limit,
                .alliteration_points = state.opts.alliteration_points,
                .weighted_scores = state.opts.weighted_scores,
            }
        });
        
        try cmd.source.conn.write(lobby); 
    }
};
