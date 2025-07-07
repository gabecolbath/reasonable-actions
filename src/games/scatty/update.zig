const std = @import("std");

const Allocator = std.mem.Allocator;


const games = @import("../games.zig");
const scatty = @import("scatty.zig");
const render = @import("render.zig");
const start = @import("start.zig");

const Client = games.Source.ClientSource;
const Room = games.Source.RoomSource;
const Scene = games.Game.Scene;
const Views = games.Game.View;


pub fn lobby(_: Allocator, client: Client, room: Room) !?Scene {
    client.ready();
    
    if (!room.host.waiting()) {
        return Scene{
            .start = start.answering,
            .render = render.answering,
            .update = answering,
        };
    } else return null;
}

pub fn answering(_: Allocator, client: Client, room: Room) !?Scene {
    client.ready();

    if (!room.waiting()) {
        
    } else return null;
}
