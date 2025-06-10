const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz"); 
const mustache = @import("mustache");
const conf = @import("config.zig");
const server = @import("server.zig");

const websocket = httpz.websocket;
const json = std.json;

const CommandError = error {
    InvalidJson,
    InvalidParameters,
    UnknownCmd,
    UnknownParameter,
    MissingCmd,
    MissingParameters,
    MissingParametersType,
};

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const App = server.Application;
const Connection = server.Connection;
const CommandMap = std.StaticStringMap(Command);
const ParameterMap = std.StaticStringMap(type);
const Room = server.Room;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;
const Game = {}; //TODO

const Command = *const fn (arena: Allocator, conn: *Connection, parameters: ?json.Value) anyerror!void;

const cmd_map = CommandMap.initComptime(.{
    .{ "updatePlayerListsJoined", updatePlayerListsJoined },
    .{ "updateRoomInfo", updateRoomInfo },
});

pub fn handleMessageAsCommand(arena: Allocator, conn: *Connection, msg: []const u8) !void {
    const is_valid = try json.validate(arena, msg);
    if (is_valid) {
        const parsed_cmd = try json.parseFromSlice(json.Value, arena, msg, .{});
        
        const cmd_json_val = parsed_cmd.value.object.get("cmd") orelse return CommandError.MissingCmd;
        const parameters_json_val = parsed_cmd.value.object.get("parameters");
        
        const cmd: Command = cmd_map.get(cmd_json_val.string) orelse return CommandError.UnknownCmd;
        try cmd(arena, conn, parameters_json_val);
    } else return CommandError.InvalidJson;
}

pub fn respondSelf(conn: *const Connection, res: []const u8) !void {
    if (conn.client.ws_conn) |ws| {
        try ws.write(res);
    } else return server.ServerError.ClientNotConnected;
}

pub fn respondAllInclusive(conn: *const Connection, res: []const u8) void {
    for (conn.room.client_ids.items) |client_id| {
        const client = conn.app.clients.get(client_id) orelse continue;
        const est_conn = Connection.initAssumeEstablished(conn.app, client, conn.room);
        respondSelf(&est_conn, res) catch continue;
    }
}

pub fn respondAllExclusive(conn: *const Connection, res: []const u8) void {
    const exclude_id = conn.client.uid;
    for (conn.room.client_ids.items) |client_id| {
        if (client_id == exclude_id) continue;
        const client = conn.app.clients.get(client_id) orelse continue;
        const est_conn = Connection.initAssumeEstablished(conn.app, client, conn.room);
        respondSelf(&est_conn, res) catch continue;
    }
}

pub fn updatePlayerListsJoined(arena: Allocator, conn: *Connection, _: ?json.Value) !void {
    const template = 
        \\<div id="player-list-item"
        \\      hx-swap-oob="beforeend:#player-info-container">
        \\      {{client_name}}
        \\</div>
    ;

    for (conn.room.client_ids.items) |client_id| {
        const client_name = try conn.app.clientName(client_id);
        const content = try mustache.allocRenderText(arena, template, .{
            .client_name = client_name,  
        });
        try respondSelf(conn, content);
    }

    const content = try mustache.allocRenderText(arena, template, .{
        .client_name = conn.client.name,
    });
    respondAllExclusive(conn, content);
}

pub fn updatePlayerListsLeave(arena: Allocator, conn: *Connection, _: ?json.Value) !void {
    const erased_list_content = 
        \\<div id="player-list-container"
        \\      hx-swap-oob="outerHTML:#player-info-container">
        \\</div>
    ;
    respondAllInclusive(conn, erased_list_content);
    
    const template = 
        \\<div id="player-list-item"
        \\      hx-swap-oob="beforeend:#player-info-container">
        \\      {{client_name}}
        \\</div>
    ;

    for (conn.room.client_ids.items) |client_id| {
        const client_name = try conn.app.clientName(client_id);
        const content = try mustache.allocRenderText(arena, template, .{
            .client_name = client_name,
        });
        respondAllInclusive(conn, content);
    }
}

pub fn updateRoomInfo(arena: Allocator, conn: *Connection, _: ?json.Value) !void {
    const template = 
        \\<div id="room-info-container"
        \\      hx-swap-oob="outerHTML:#room-info-container">
        \\      {{room_name}} : {{room_urn}}
        \\</div>
    ;

    const content = try mustache.allocRenderText(arena, template, .{
        .room_name = conn.room.name,
        .room_urn = uuid.urn.serialize(conn.room.uid),
    });
    
    try respondSelf(conn, content); 
}
