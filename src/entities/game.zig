const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;


const core = @import("../core/core.zig");
const Scope = core.scope.Scope;


const entities = @import("../entities/entities.zig");
const Player = entities.player.Player;


const config = @import("../config/config.zig");


pub const Game = struct {
    allocator: Allocator,
    scope: Scope,
    players: Player.ArrayMap,

    const Self = @This();
    pub const Identifier = Scope.Identifier;
    pub const Map = AutoHashMapUnmanaged(Identifier, Game);

    pub fn init(allocator: Allocator, scope: Scope) !Self {
        var players = Player.ArrayMap{};
        try players.ensureTotalCapacity(allocator, config.engine.game_player_limit);
        
        return Self{
            .allocator = allocator,
            .scope = scope,
            .players = players,
        };
    }

    pub fn deinit(self: *Self) void {
        self.players.deinit(self.allocator);
    }

    pub fn kickPlayer(self: *Self, uuid: Player.Identifier) void {
        const player = self.players.get(uuid) orelse return;
        player.kick();
    }

    pub fn kickAll(self: *Self) void {
        for (self.players.items) |player| {
            player.kick(); 
        }
    }
};
