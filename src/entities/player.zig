const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const ArrayListUnmanaged = std.ArrayListUnmanaged;


const core = @import("../core/core.zig");
const Agent = core.agent.Agent;


const entities = @import("entities.zig");
const Game = entities.game.Game;


pub const Player = struct {
    agent: Agent,
    game: *Game, 

    const Self = @This();
    pub const Identifier = Agent.Identifier;
    pub const Map = AutoHashMapUnmanaged(Identifier, Self);
    pub const List = ArrayListUnmanaged(Self);
};
