const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;


const core = @import("../core/core.zig");
const Space = core.space.Space;


const entities = @import("../entities/entities.zig");
const Player = entities.player.Player;


pub const Game = struct {
    space: Space,
    players: Player.ArrayMap,

    const Self = @This();
    pub const Identifier = Space.Identifier;
    pub const Map = AutoHashMapUnmanaged(Identifier, Self);

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
