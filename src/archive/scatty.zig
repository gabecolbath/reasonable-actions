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
const Room = server.Room;
const Member = server.Member;


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
        const lobby_html: []const u8 = @embedFile("html/lobby.html");

        const room_clients = try source.clientsInRoom(allocator);
        var render = Game.Render{};
        try render.ensureTotalCapacity(allocator, room_clients.len);
        
        for (room_clients) |client| {
            render.putAssumeCapacity(client.uid.member, lobby_html);
        }

        return render;
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

    fn start(_: Allocator, cmd: Command) !void {
        const source_game = try cmd.source.game();
        try source_game.start(cmd.source);
    }
};


pub const init_scene = Game.Scene{
    .sequence = 0,
    .views = Renderers.lobby,
};
