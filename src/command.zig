const std = @import("std");
const game = @import("game.zig");
const server = @import("server.zig"); 

const Allocator = std.mem.Allocator;
const Command = fn (client: *server.Application.Connection) void;
const CommandMap = std.StaticStringMap(Command);
const Html = []const u8;

const CommandError = error {
    UnknownCommand,
};

const room_html: Html = @embedFile("html/room.html");
const map = CommandMap.initComptime(.{});

pub fn onWebsocketConnect(client: *server.Application.Connection) !void {
    if (client.conn) |conn| {
        try conn.write(room_html);
    } else return server.ConnectionError.MissingConnection;
}

pub fn handleWebsocketMessage(arena: Allocator, client: *server.Application.Connection, data: []const u8) !void {
    std.debug.print("Message Recieved: {s}\n", .{data});
    _ = client;
    _ = arena;
}

