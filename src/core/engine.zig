const std = @import("std");
const Allocator = std.mem.Allocator;


const application = @import("../application.zig");
const App = application.App;


const config = @import("../config/config.zig"); 


const entities = @import("../entities/entities.zig");
const Game = entities.game.Game;
const Player = entities.player.Player;


pub const EngineError = error {
    GameNotFound,
    PlayerNotFound,
};


pub const Engine = struct {
    app: *App,
    games: Game.Map,
    players: Player.Map,

    const Self = @This();

    pub fn init(app: *App) !Self {
        var games = Game.Map{};
        var players = Player.Map{};
        
        try games.ensureTotalCapacity(app.allocator, config.engine.game_limit);
        errdefer games.deinit(app.allocator);
        try players.ensureTotalCapacity(app.allocator, config.engine.player_limit);
        errdefer players.deinit(app.allocator);
        
        return Self{
            .app = app,
            .games = games,
            .players = players,
        };
    }

    pub fn deinit(self: *Self) void {
        self.games.deinit(self.app.allocator);
        self.players.deinit(self.app.allocator);
    }
};
