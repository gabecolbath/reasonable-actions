const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const mustache = @import("mustache");
const server = @import("server.zig");

const Action = httpz.Action;
const Application = server.Application;
const Allocator = std.mem.Allocator; 
const Html = []const u8;
const Request = httpz.Request;
const Response = httpz.Response;
const RouteMap = std.StaticStringMap(Action(*Application));
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

const RequestError = error {
    InvalidParameter,
    InvalidFormData,
};

const RouteMapByMethod = struct {
    get: RouteMap,
    post: RouteMap,
};

pub const map = RouteMapByMethod{
    .get = RouteMap.initComptime(.{
        .{ "/", @"/" },
        .{ "/games", @"/games" },
        .{ "/scatty/rooms", @"/scatty/rooms" },
        .{ "/scatty/rooms/list", @"/scatty/rooms/list" },
        .{ "/scatty/rooms/create", @"/scatty/rooms/create" },
        .{ "/scatty/rooms/join/:room_urn", @"/scatty/rooms/join/:room_urn" },
        .{ "/scatty/room/enter/:member_urn", @"/scatty/room/enter/:member_urn" },
        .{ "/scatty/room/connect/:member_urn", @"/scatty/room/connect/:member_urn" },
    }),
    .post = RouteMap.initComptime(.{
        .{ "/scatty/room/create", @"/scatty/room/create" },
        .{ "/scatty/room/join/:room_urn", @"/scatty/room/join/:room_urn" },
    }),
};

const index_html: Html = @embedFile("html/index.html");
const room_html: Html = @embedFile("html/room.html");

pub fn @"/"(_: *Application, _: *Request, res: *Response) !void {
    res.body = index_html;
}

pub fn @"/games"(_: *Application, _: *Request, res: *Response) !void {
    const html = 
        \\<div id="games-list">
        \\<h1>Games</h1>
        \\<a href="/scatty/rooms"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#games-list"
        \\      hx-swap="outerHTML"
        \\      hx-push-url="true">
        \\      Scatty
        \\</a>
    ;
    
    res.body = html;
}

pub fn @"/scatty/rooms"(_: *Application, _: *Request, res: *Response) !void {
    const html = 
        \\<div id="scatty-rooms">
        \\<h1>Rooms</h1>
        \\<button id="create-room-button"
        \\      hx-get="/scatty/rooms/create"
        \\      hx-target="#scatty-rooms"
        \\      hx-swap="outerHTML"
        \\      hx-replace-url="/scatty/rooms/create">
        \\      Create Room
        \\</button>
        \\<div id="scatty-rooms-list"
        \\      hx-get="/scatty/rooms/list"
        \\      hx-trigger="load"
        \\      hx-target="#scatty-rooms-list"
        \\      hx-swap="innerHTML">
        \\</div>
        \\</div>
    ;

    res.body = html;   
}

pub fn @"/scatty/rooms/list"(app: *Application, _: *Request, res: *Response) !void {
    const template: []const u8 = 
        \\<a href="/scatty/rooms/join/{{room_urn}}"
        \\      hx-get="/scatty/rooms/join/{{room_urn}}"
        \\      hx-target="#scatty-rooms"
        \\      hx-swap="outerHTML"
        \\      hx-replace-url="/scatty/rooms/join/{{room_name}}">
        \\      {{room_name}}
        \\</a>
        \\<br>
    ;

    const res_writer = res.writer();

    var room_it = app.rooms.valueIterator();
    var count: usize = 0;
    while (room_it.next()) |room| : (count += 1) {
        if (count < 50) {
            const data = .{
                .room_urn = uuid.urn.serialize(room.uid),
                .room_name = room.name,
            };
            const html = try mustache.allocRenderText(res.arena, template, data);
            try res_writer.writeAll(html);
        } else break;
    }
}

pub fn @"/scatty/rooms/create"(_: *Application, _: *Request, res: *Response) !void {
    const html =
        \\<div id="room-create">
        \\<a href="/scatty/rooms"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#room-create"
        \\      hx-swap="outerHTML"
        \\      hx-push-url="true">
        \\      Back To List
        \\</a>
        \\<form id="room-create-form"
        \\      hx-post="/scatty/room/create"
        \\      hx-target="#room-create"
        \\      hx-swap="outerHTML">
        \\      <label for="room-name">Room Name</label>
        \\      <input id="room-name-input" name="room-name" type="text"><br>
        \\      <label for="member-name">Name</label>
        \\      <input id="member-name-input" name="member-name" type="text"><br>
        \\      <button id="join-button" type="submit">Enter</button>
        \\</form>
        \\</div>
    ;

    res.body = html;
}

pub fn @"/scatty/rooms/join/:room_urn"(_: *Application, req: *Request, res: *Response) !void {
    const template =
        \\<div id="room-join">
        \\<a href="/scatty/rooms"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#room-join"
        \\      hx-swap="outerHTML"
        \\      hx-push-url="true">
        \\      Back To List
        \\</a>
        \\<form id="room-join-form"
        \\      hx-post="/scatty/room/join/{{room_urn}}"
        \\      hx-target="#room-join"
        \\      hx-swap="outerHTML">
        \\      <label for="name">Name</label>
        \\      <input id="name-input" name="name" type="text"><br>
        \\      <button id="join-button" type="submit">Enter</button>
        \\</form>
        \\</div>
    ;
    
    const req_room_urn = req.param("room_urn") orelse
        return RequestError.InvalidParameter;

    const data = .{
        .room_urn = req_room_urn,
    };
    
    res.body = try mustache.allocRenderText(res.arena, template, data);
}

pub fn @"/scatty/room/create"(app: *Application, req: *Request, res: *Response) !void {
    const template = 
        \\<div id="room-enter"
        \\      hx-get="/scatty/room/enter/{{member_urn}}"
        \\      hx-trigger="load"
        \\      hx-target="#room-enter"
        \\      hx-swap="outerHTML"
        \\      hx-replace-url="/scatty/room/{{room_name}}">
        \\</div>
    ;

    const form_data = try req.formData();
    const req_member_name = form_data.get("member-name") orelse return RequestError.InvalidFormData;
    const req_room_name = form_data.get("room-name") orelse return RequestError.InvalidFormData;
    
    const connection_result = try app.createRoom(req_room_name, req_member_name);
    
    const data = .{
        .member_urn = uuid.urn.serialize(connection_result.member_id),
        .room_name = req_room_name,
    };

    res.body = try mustache.allocRenderText(res.arena, template, data);
}

pub fn @"/scatty/room/join/:room_urn"(app: *Application, req: *Request, res: *Response) !void {
    const template = 
        \\<div id="room-enter"
        \\      hx-get="/scatty/room/enter/{{member_urn}}"
        \\      hx-trigger="load"
        \\      hx-target="#room-enter"
        \\      hx-swap="outerHTML"
        \\      hx-replace-url="/scatty/room/{{room_name}}">
        \\</div>
    ;

    const form_data = try req.formData();
    const req_member_name = form_data.get("name") orelse return RequestError.InvalidFormData;
    
    const req_room_urn = req.param("room_urn") orelse return RequestError.InvalidParameter;
    const req_room_id = try uuid.urn.deserialize(req_room_urn);
    const req_room = app.rooms.get(req_room_id) orelse return server.ConnectionError.RoomNotFound;
    
    const connection_result = try app.joinRoom(req_member_name, req_room_id);
    
    const data = .{
        .member_urn = uuid.urn.serialize(connection_result.member_id),
        .room_name = req_room.name,
    };

    res.body = try mustache.allocRenderText(res.arena, template, data);
}

pub fn @"/scatty/room/enter/:member_urn"(_: *Application, req: *Request, res: *Response) !void {
    const template = 
        \\<div id="room" hx-ext="ws">
        \\<button id="leave-button"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#room"
        \\      hx-swap="outerHTML"
        \\      hx-replace-url="true">
        \\      Leave
        \\</button>
        \\<div id="websocket"
        \\      ws-connect="/scatty/room/connect/{{member_urn}}">
        \\      <div id="game">Test Game</div>
        \\      <hr>
        \\      <div id="player-list">Test Player List</div>
        \\      <hr>
        \\      <div id="room-info">Test Room Info</div>
        \\      <hr>
        \\</div>
    ;

    const req_member_urn = req.param("member_urn") orelse return RequestError.InvalidParameter;

    const data = .{
        .member_urn = req_member_urn,
    };

    res.body = try mustache.allocRenderText(res.arena, template, data);
}

pub fn @"/scatty/room/connect/:member_urn"(app: *Application, req: *Request, res: *Response) !void {
    const req_member_urn = req.param("member_urn") orelse
        return RequestError.InvalidParameter;
    const req_member_id = try uuid.urn.deserialize(req_member_urn);
    
    const ctx = server.Application.Connection.Context{
        .app = app,
        .member_id = req_member_id,
    };

    if (try httpz.upgradeWebsocket(Application.Connection, req, res, &ctx) == false) {
        res.status = 500;
        res.body = "Invalid Websocket Connection.";
    }
}

pub fn onWebsocketConnect(client: *server.Application.Connection) !void {
    if (client.conn) |conn| {
        try conn.write(room_html);
    } else return server.ConnectionError.MissingConnection;
}

pub fn handleWebsocketMessage(client: *server.Application.Connection, data: []const u8) !void {
    if (client.conn) |conn| {
        try conn.write(data);
    } else return server.ConnectionError.MissingConnection;
}
