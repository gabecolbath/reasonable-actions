const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const mustache = @import("mustache");
const conf = @import("config.zig");
const server = @import("server.zig");

const websocket = httpz.websocket;

const CmdError = error {
    InvalidJson,
    UnknownCmd,
    MissingCmd,
};

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const App = server.Application;
const Connection = server.Connection;
const CmdMap = std.StaticStringMap(Action);
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

const Action = *const fn (arena: Allocator, conn: *server.Connection, parameters: ?[][]const u8) void;

const Message = struct {
    HEADERS: ?[]const u8 = null,
    cmd: []const u8,
    parameters: ?[][]const u8 = null, 
};

const cmd_map = CmdMap.initComptime(.{
    .{ "gameLobby", gameLobby },
    .{ "playerList", playerList },
    .{ "roomInfo", roomInfo },
    .{ "gameOptions", gameOptions },
});

pub const room_html = @embedFile("html/room.html");

pub fn handleMessage(allocator: Allocator, conn: *server.Connection, msg: []const u8) !void {
    var arena_wrapper = ArenaAllocator.init(allocator); 
    defer arena_wrapper.deinit();
    const arena = arena_wrapper.allocator();

    if (try std.json.validate(arena, msg)) {
        const parsed = try std.json.parseFromSlice(std.json.Value, arena, msg, .{});
        defer parsed.deinit();
        
        const cmd = parsed.value.object.get("cmd") orelse return CmdError.MissingCmd;
        std.debug.print("Command Recieved: {s}\n", .{cmd.string}); 
        
        const action = cmd_map.get(cmd.string) orelse return CmdError.UnknownCmd;
        action(arena, conn, null);
    } else return CmdError.InvalidJson;
}

pub fn gameLobby(_: Allocator, conn: *server.Connection, _: ?[][]const u8 ) void {
    const content = 
        \\<div id="lobby-container"
        \\      hx-target="#lobby-container"
        \\      hx-swap-oob="outerHTML">
        \\      Lobby Testies!!!
        \\</div>
    ;

    if (conn.client.ws_conn) |ws_conn| {
        ws_conn.write(content) catch {
            std.debug.print("Failed to Respond.\n", .{});
        }; 
    } else {
        std.debug.print("Client Not Connected.\n", .{});
    }
}

pub fn playerList(arena: Allocator, conn: *server.Connection, _: ?[][]const u8) void {
    const template = 
        \\<div id="player-list-item"
        \\      hx-target="#player-list-item"
        \\      hx-swap-oob="afterend">
        \\      {{client_name}}
        \\</div>
    ;

    if (conn.client.ws_conn) |ws_conn| {
        const client_list = conn.app.clientsFrom(conn.room.uid) catch return;
        for (client_list) |client_id| {
            const client_name = conn.app.clientName(client_id) catch return;
            const content = mustache.allocRenderText(arena, template, .{
                .client_name = client_name,
            }) catch return;

            ws_conn.write(content) catch {
                std.debug.print("Failed to Respond.\n", .{});
            }; 
        }
    } else {
        std.debug.print("Client Not Connected.\n", .{});
    }
}

pub fn roomInfo(arena: Allocator, conn: *server.Connection, _: ?[][]const u8) void {
    _ = arena;
    _ = conn;
}

pub fn gameOptions(arena: Allocator, conn: *server.Connection, _: ?[][]const u8) void {
    _ = arena;
    _ = conn;
}

