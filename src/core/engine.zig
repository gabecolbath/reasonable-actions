const std = @import("std");


const application = @import("../application.zig");
const App = application.App;


const entities = @import("../entities/entities.zig");
const Game = entities.game.Game;
const Player = entities.player.Player;


pub const EngineError = error {
    GameNotFound,
    PlayerNotFound,
    NoSyncedMember, 
};


pub const Engine = struct {
    app: *App,
    games: Game.Map,
    players: Player.Map,
};
