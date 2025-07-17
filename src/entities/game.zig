const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;


const core = @import("../core/core.zig");
const Space = core.space.Space;


const entities = @import("../entities/entities.zig");
const Player = entities.player.Player;


pub const Game = struct {
    space: Space,
    players: Player.List,

    const Self = @This();
    pub const Identifier = Space.Identifier;
    pub const Map = AutoHashMapUnmanaged(Identifier, Self);
};
