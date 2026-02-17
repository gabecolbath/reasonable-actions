const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const games = struct {
    const scatty = @import("scatty/game.zig");
};


// =============================================================================
pub const Instance = union(enum) {

    scatty: games.scatty.Game,

    pub fn start(self: Instance) !void {
        switch (self) {
            .scatty => |game| game.start(),
        }
    }

    pub fn end(self: Instance) !void {
        switch (self) {
            .scatty => |game| game.end(),
        }
    }
};
