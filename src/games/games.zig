const std = @import("std");
const uuid = @import("uuid");
const server = @import("../server.zig");
const conf = @import("../config.zig");
const command = @import("../command.zig");
const games = struct {
    const scatty = @import("scatty/scatty.zig"); 
};


pub const UpdateError = struct {
    
};


pub const RenderError = error {
    
};


pub const GameTag = enum {
    scatty,
};


const Client = server.Client;
const Command = command.Command;
const CommandMap = command.StaticCommandMap;
const CommandHandler = command.Handler;
const Order = std.math.Order;
const RenderedHtml = []const u8;
const Uuid = uuid.Uuid;


pub const Updater = *const fn (allocator: Allocator, source: *Client) UpdateError!?Game.Scene;
pub const Renderer = *const fn (allocator: Allocator, source: *Client) RenderError!Game.Render;


const Allocator = std.mem.Allocator;


pub const Player = struct {
    allocator: Allocator,
    game: *Game,
    state: *anyopaque,
    
    const Self =  @This();

    pub fn init(allocator: Allocator, game: *Game) !Player {
        const init_state = switch (game.tag) {
            .scatty => games.scatty.PlayerState.init,
        };
        const state = try init_state(allocator);

        return Player{
            .allocator = allocator,
            .game = game,
            .state = state,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        const deinit_state = switch (self.game.tag) {
            .scatty => games.scatty.PlayerState.deinit,      
        };
        deinit_state(self.state, allocator);
    } 

    pub fn new(allocator: Allocator, game: *Game) !*Player {
        const new_player = try allocator.create(Player);
        new_player.* = try init(allocator, game);

        return new_player;
    }

};


pub const Game = struct {
    allocator: Allocator,
    tag: GameTag,
    loop: GameLoop,
    players: PlayerActivityMap,
    waitlist: PlayerSet,
    cmd: CommandHandler,
    state: *anyopaque, 
    
    const Self = @This();
    const GameLoop = std.PriorityQueue(Scene, void, orderScene);
    const PlayerMap = std.AutoArrayHashMapUnmanaged(Uuid, Player);
    const PlayerSet = std.AutoArrayHashMapUnmanaged(Uuid, void);
    pub const Render = std.AutoArrayHashMapUnmanaged(Uuid, RenderedHtml);

    pub const Scene = struct {
        sequence: u8 = 0,
        views: Renderer,
    };

    const PlayerActivityMap = struct {
        active: PlayerMap = PlayerMap{},
        inactive: PlayerMap = PlayerMap{},
    };

    pub fn init(allocator: Allocator, tag: GameTag) !Game {
        const init_state = switch (tag) {
            .scatty => games.scatty.GameState.init,
        }; 
        const state = try init_state(allocator);

        const cmd = switch (tag) {
            .scatty => CommandHandler{ .map = games.scatty.Commanads.map },
        };

        return Game{
            .allocator = allocator,
            .tag = tag,
            .loop = GameLoop.init(allocator, {}),
            .players = PlayerActivityMap{},
            .waitlist = PlayerSet{},
            .cmd = cmd,
            .state = state,
        };
    }

    pub fn deinit(self: *Self) void {
        const deinit_state = switch (self.tag) {
            .scatty => games.scatty.GameState.deinit,
        };
        deinit_state(self.state, self.allocator);

        self.loop.deinit();
        self.players.active.deinit(self.allocator);
        self.players.inactive.deinit(self.allocator);
        self.waitlist.deinit(self.allocator);
    }

    pub fn new(allocator: Allocator, tag: GameTag) !*Game {
        const new_game = try allocator.create(Game);
        new_game.* = try init(allocator, tag);
        return new_game;
    }
};


fn orderScene(_: void, a: Game.Scene, b: Game.Scene) Order {
    return std.math.order(a.sequence, b.sequence);
}
