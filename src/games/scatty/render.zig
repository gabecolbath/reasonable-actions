const std = @import("std");

const Allocator = std.mem.Allocator;


const game = @import("../games.zig");
const scatty = @import("scatty.zig");

const ClientSource = game.Source.ClientSource;
const RoomSource = game.Source.RoomSource;
const View = game.Game.View;


pub fn lobby(_: Allocator, view: *View) !void {
    const lobby_html = ""; //TODO

    try view.set(.all, lobby_html);
}


pub fn answering(_: Allocator, view: *View) !void {
    const answering_html = ""; //TODO

    try view.set(.all, answering_html);
}
