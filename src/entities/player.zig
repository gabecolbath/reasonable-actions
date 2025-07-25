const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const AutoArrayHashMapUnmanaged = std.AutoArrayHashMapUnmanaged;


const core = @import("../core/core.zig");
const Agent = core.agent.Agent;


const entities = @import("entities.zig");
const Game = entities.game.Game;


pub const Player = struct {
    agent: Agent,
    game: *Game, 

    const Self = @This();
    pub const Identifier = Agent.Identifier;
    pub const Map = AutoHashMapUnmanaged(Identifier, Player);
    pub const ArrayMap = AutoArrayHashMapUnmanaged(Identifier, Player); 

    pub fn init(game: *Game, agent: Agent) Self {
        return Self{
            .agent = agent,
            .game = game,
        };
    }

    pub fn kick(self: *Self) void {
        self.agent.client.conn.close(.{}) catch return; 
    }
};
