const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const mustache = @import("mustache");
const server = @import("server.zig");
const game = @import("game.zig");

const Action = httpz.Action;
const Application = server.Application;
const Allocator = std.mem.Allocator; 
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const Html = []const u8;
const Request = httpz.Request;
const Response = httpz.Response;
const RouteMap = std.StaticStringMap(Action(*Application));
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;
const CommandToken = []const u8;

const RequestError = error {
    InvalidParameter,
    InvalidFormData,
    InvalidMessage,
};

const RouteMapByMethod = struct {
    get: RouteMap,
    post: RouteMap,
};

pub const map = RouteMapByMethod{
    .get = RouteMap.initComptime(.{
        .{ "/", @"/" },
        .{ "/games", @"/games" },
        .{ "/games/scatty/lobby/default-options", @"/games/scatty/lobby/default-options" },
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

pub fn @"/games/scatty/lobby/default-options"(_: *Application, _: *Request, res: *Response) !void {
    const template = 
        \\<div id="options">
        \\
        \\<h3>Options</h3>
        \\
        \\<label for="rounds-option">Rounds</label>
        \\<input id="rounds-option" name="rounds" type="number" value="{{rounds}}">
        \\<br>
        \\
        \\<label for="categories-per-round-option">Categories Per Round</label> 
        \\<input id="categories-per-round-option" name="categories_per_round" type="number" value="{{categories_per_round}}">
        \\<br>
        \\
        \\<label for="repeat-categories-option">Repeat Categories</label>
        \\<input id="repeat-categories-option" name="repeat_categories" type="checkbox" {{repeat_categories}}>
        \\<br>
        \\
        \\<label for="answering-time-limit-option">Answering Time Limit</label>
        \\<input id="answering-time-limit-option" name="answering_time_limit" type="number" value="{{answering_time_limit}}">
        \\<br>
        \\
        \\<label for="enable-voting-time-limit-option">Voting Time Limit</label>
        \\<input id="enable-voting-time-limit-option" name="enable_voting_time_limit" type="checkbox" {{enable_voting_time_limit}}>
        \\<input id="voting-time-limit-option" name="voting_time_limit" type="number" value="{{voting_time_limit}}" {{hide_voting_time_limit}}>
        \\<br>
        \\
        \\<label for="special-points-option">Special Points</label>
        \\<input id="special-points-option" name="special_points" type="checkbox" {{special_points}}>
        \\
        \\</div>
        \\
        \\<script>
        \\document.getElementById('enable-voting-time-limit-option').addEventListener('change', function() {
        \\  const targetInput = document.getElementById('voting-time-limit-option');
        \\  targetInput.disabled = !this.checked;
        \\});
        \\</script>
        ;

    const default_opts = game.Options{};

    const data = .{
        .rounds = default_opts.rounds,
        .categories_per_round = default_opts.categories_per_round,
        .repeat_categories = if (default_opts.repeat_categories) "checked" else "",
        .answering_time_limit = default_opts.answering_time_limit,
        .enable_voting_time_limit = if (default_opts.voting_time_limit) |_| "checked" else "",
        .voting_time_limit = default_opts.voting_time_limit orelse 60,
        .hide_voting_time_limit = if (default_opts.voting_time_limit) |_| "" else "disabled",
        .special_points = if (default_opts.special_points) "checked" else "",
    };

    res.body = try mustache.allocRenderText(res.arena, template, data);
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
        \\      <label for="room-name-input">Room Name</label>
        \\      <input id="room-name-input" name="room-name" type="text"><br>
        \\      <label for="member-name-input">Name</label>
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
        \\      <label for="name-input">Name</label>
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
        \\      hx-swap="outerhtml"
        \\      hx-replace-url="true">
        \\      leave
        \\</button>
        \\<div id="websocket"
        \\      ws-connect="/scatty/room/connect/{{member_urn}}">
        \\      <div id="game">test game</div>
        \\      <hr>
        \\      <div id="player-list">test player list</div>
        \\      <hr>
        \\      <div id="room-info">test room info</div>
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
