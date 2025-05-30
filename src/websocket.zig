const std = @import("std");
const server = @import("server.zig");
const httpz = @import("httpz");
const game = @import("game.zig");
const conf = @import("config.zig");
const app = @import("app.zig");
const uuid = @import("uuid"); 
const routes = @import("routes.zig");
const html = @import("html.zig");

const websocket = httpz.websocket;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Uuid = uuid.Uuid; 

pub fn handleClientMessage(allocator: Allocator, client: *server.AppHandler.WebsocketHandler, data: []const u8) !void {
    var arena_wrapper = ArenaAllocator.init(allocator);
    defer arena_wrapper.deinit();

    const arena = arena_wrapper.allocator(); 

    const client_data = client.application.data.members.get(client.ids.member).?;
    std.debug.print("Message Recieved From {s}: {s}\n", .{
        client_data.name,
        data,
    });

    _ = arena;
}
