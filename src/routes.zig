const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const mustache = @import("mustache");
const conf = @import("config.zig");
const server = @import("server.zig");

pub const RequestError = error {
    InvalidParameter,
    InvalidFormData,
};

const Allocator = std.mem.Allocator;
const App = server.Application;
const Html = []const u8;
const Request = httpz.Request;
const Response = httpz.Response;
const RouteMap = std.StaticStringMap(httpz.Action(*App));
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

pub const map = .{
    .get = RouteMap.initComptime(.{
        .{ "/", index },
        .{ "/games", gamesList },
        .{ "/scatty/rooms", roomsList },
        .{ "/scatty/rooms/list", roomsListItems },
        .{ "/scatty/rooms/create", roomCreateForm },
        .{ "/scatty/rooms/join/:room_urn", roomJoinForm },
        .{ "/scatty/rooms/connect/:client_urn", upgradeToWebsocket },
    }),
    .post = RouteMap.initComptime(.{
        .{ "/scatty/room/create", createRoomFromForm },
        .{ "/scatty/room/join/:room_urn", joinRoomFromForm },
    }),
};

pub const index_html: Html = @embedFile("html/index.html");
pub const room_html: Html = @embedFile("html/room.html");

pub fn index(_: *App, _: *Request, res: *Response) !void {
    res.content_type = .HTML;
    res.status = 200;
    res.body = index_html;
}

pub fn gamesList(_: *App, _: *Request, res: *Response) !void {
    const content = 
        \\<div id="page-container">
        \\<h1>Games</h1>
        \\<a href="/scatty/rooms"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#page-container"
        \\      hx-swap="innerHTML"
        \\      hx-push-url="true">
        \\      Scatty
        \\</a>
    ;

    res.content_type = .HTML;
    res.status = 200;
    res.body = content;
}

pub fn roomsList(_: *App, _: *Request, res: *Response) !void {
    const content = 
        \\<div id="page-container">
        \\<h1>Rooms</h1>
        \\<button id="create-room-button"
        \\      hx-get="/scatty/rooms/create"
        \\      hx-target="#page-container"
        \\      hx-swap="innerHTML"
        \\      hx-replace-url="/scatty/rooms/create">
        \\      Create Room
        \\</button>
        \\<div id="rooms-list-container"
        \\      hx-get="/scatty/rooms/list"
        \\      hx-trigger="load"
        \\      hx-target="#rooms-list-container"
        \\      hx-swap="innerHTML">
        \\</div>
        \\</div>
    ;

    res.content_type = .HTML;
    res.status = 200;
    res.body = content;
}

pub fn roomsListItems(app: *App, _: *Request, res: *Response) !void {
    const template = 
        \\<a href="/scatty/rooms/join/{{room_urn}}"
        \\      hx-get="/scatty/rooms/join/{{room_urn}}"
        \\      hx-target="#page-container"
        \\      hx-swap="innerHTML"
        \\      hx-replace-url="/scatty/rooms/join/{{room_name}}">
        \\      {{room_name}}
        \\</a>
        \\<br>
    ;
    
    res.content_type = .HTML;
    res.status = 200;

    const res_writer = res.writer();
    const rooms = app.rooms.values();
    for (rooms) |room| {
        const content = try mustache.allocRenderText(res.arena, template, .{
            .room_urn = uuid.urn.serialize(room.uid),
            .room_name = room.name,
        });
        
        try res_writer.writeAll(content);
    }
}

pub fn roomCreateForm(_: *App, _: *Request, res: *Response) !void {
    const content =
        \\<div id="page-container">
        \\<a href="/scatty/rooms"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#page-container"
        \\      hx-swap="innerHTML"
        \\      hx-push-url="true">
        \\      Back To List
        \\</a>
        \\<form id="room-create-form"
        \\      hx-post="/scatty/room/create"
        \\      hx-target="#page-container"
        \\      hx-swap="innerHTML">
        \\      <label for="room-name-input">Room Name</label>
        \\      <input id="room-name-input" name="room_name" type="text"><br>
        \\      <label for="member-name-input">Name</label>
        \\      <input id="member-name-input" name="client_name" type="text"><br>
        \\      <button id="join-button" type="submit">Enter</button>
        \\</form>
        \\</div>
    ;

    res.content_type = .HTML;
    res.status = 200;
    res.body = content;
}

pub fn roomJoinForm(_: *App, req: *Request, res: *Response) !void {
    const template =
        \\<div id="page-container">
        \\<a href="/scatty/rooms"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#page-container"
        \\      hx-swap="innerHTML"
        \\      hx-push-url="true">
        \\      Back To List
        \\</a>
        \\<form id="room-join-form"
        \\      hx-post="/scatty/room/join/{{room_urn}}"
        \\      hx-target="#page-container"
        \\      hx-swap="innerHTML">
        \\      <label for="name-input">Name</label>
        \\      <input id="name-input" name="client_name" type="text"><br>
        \\      <button id="join-button" type="submit">Enter</button>
        \\</form>
        \\</div>
    ;

    const req_room_urn = req.param("room_urn") orelse return RequestError.InvalidParameter;
    
    res.content_type = .HTML;
    res.status = 200;
    res.body = try mustache.allocRenderText(res.arena, template, .{
        .room_urn = req_room_urn,
    });
}

pub fn createRoomFromForm(app: *App, req: *Request, res: *Response) !void {
    const template = 
        \\<div id="page-container" hx-ext="ws">
        \\<button id="leave-button"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#page-container"
        \\      hx-swap="outerhtml"
        \\      hx-replace-url="true">
        \\      leave
        \\</button>
        \\<div id="websocket-container"
        \\      ws-connect="/scatty/rooms/connect/{{client_urn}}">
        \\      <div id="game-container"></div>
        \\      <hr>
        \\      <div id="player-info-section-container"></div>
        \\      <hr>
        \\      <div id="room-info-section-container"></div>
        \\      <hr>
        \\</div>
    ;

    const form_data = try req.formData();
    const req_client_name = form_data.get("client_name") orelse return RequestError.InvalidFormData;
    const req_room_name = form_data.get("room_name") orelse return RequestError.InvalidFormData;

    const new_client_id = try app.create(req_client_name, req_room_name);
    
    res.content_type = .HTML;
    res.status = 200;
    res.body = try mustache.allocRenderText(res.arena, template, .{
        .client_urn  = uuid.urn.serialize(new_client_id),
    });
}

pub fn joinRoomFromForm(app: *App, req: *Request, res: *Response) !void {
    const template = 
        \\<div id="page-container" hx-ext="ws">
        \\<button id="leave-button"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#page-container"
        \\      hx-swap="innerHTML"
        \\      hx-replace-url="true">
        \\      leave
        \\</button>
        \\<div id="websocket-container"
        \\      ws-connect="/scatty/rooms/connect/{{client_urn}}">
        \\      <div id="game-container"></div>
        \\      <hr>
        \\      <div id="player-info-section-container"></div>
        \\      <hr>
        \\      <div id="room-info-section-container"></div>
        \\</div>
    ;
    
    const form_data = try req.formData();
    const req_client_name = form_data.get("client_name") orelse return RequestError.InvalidFormData;
    
    const req_room_urn = req.param("room_urn") orelse return RequestError.InvalidParameter;
    const req_room_id = try uuid.urn.deserialize(req_room_urn);

    const new_client_id = try app.join(req_client_name, req_room_id);
    
    res.content_type = .HTML;
    res.status = 200;
    res.body = try mustache.allocRenderText(res.arena, template, .{
        .client_urn = uuid.urn.serialize(new_client_id),
    });
}

pub fn upgradeToWebsocket(app: *App, req: *Request, res: *Response) !void {
    const failed_content = 
        \\<h1
        \\      hx-swap-oob="#page-container">
        \\Failed to Connect :(
        \\</h1>
    ; 

    const req_client_urn = req.param("client_urn") orelse return RequestError.InvalidParameter; 
    const req_client_id = try uuid.urn.deserialize(req_client_urn);
    
    const ctx = server.Connection.Context{
        .app = app,
        .client_id = req_client_id,
    };

    const is_successfully_connected = try httpz.upgradeWebsocket(server.Connection, req, res, &ctx);

    if (!is_successfully_connected) {
        res.status = 500;
        res.body = failed_content;
    }
}
