const std = @import("std");


const games = @import("../games.zig");
const scatty = @import("scatty.zig");
const render = @import("render.zig");


const Allocator = std.mem.Allocator;


const ClientSource = games.Source.ClientSource;
const RoomSource = games.Source.RoomSource;
const Views = games.Game.View;


pub fn lobby(allocator: Allocator, _: ClientSource, room: RoomSource) !void {
    try room.host.wait(allocator);
}

pub fn answering(allocator: Allocator, _: ClientSource, room: RoomSource) !void {
    try room.wait(allocator);
}
