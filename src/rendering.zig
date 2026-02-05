const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const server = @import("server.zig");

const games = struct {
    const scatty = @import("scatty.zig");
};

const ServerError = server.ServerError;

const Allocator = std.mem.Allocator;
const App = server.App;
const Member = server.Member;
const Room = server.Room;
const Game = games.scatty.Game;
const Player = games.scatty.Player;
const Request = httpz.Request;
const Response = httpz.Response;

pub fn errorMissingQuery(res: *Response, query: []const u8) void {
    const error_body_template = "Error: Missing query - '{s}'";
    const error_body = std.fmt.allocPrint(res.arena, error_body_template, .{query})
        catch "Error: Missing query [unable to provide query]";

    res.status = 400;
    res.body = error_body;
}

pub fn errorMissingFormEntry(res: *Response, form_entry: []const u8) void {
    const error_body_template = "Error: Missing form entry - '{s}'";
    const error_body = std.fmt.allocPrint(res.arena, error_body_template, .{form_entry})
        catch "Error: Missing query [unable to provide form entry]";

    res.status = 400;
    res.body = error_body;
}

pub fn errorWebsocketNotConnected(res: *Response) void {
    res.status = 400;
    res.body = "Error: Unable to connect.";
}

pub fn getIndex(_: *App, _: *Request, res: *Response) !void {
    const index_html = @embedFile("html/index.html");
    res.body = index_html;
}

pub fn getRooms(app: *App, _: *Request, res: *Response) !void {
    const room_card_template = @embedFile("html/room-card.html");

    for (app.rooms.values()) |room| {
        const room_urn = uuid.urn.serialize(room.id);
        res.writer().print(room_card_template, .{
            room_urn,
            room.name,
        }) catch continue;
    }
}

pub fn getJoin(_: *App, req: *Request, res: *Response) !void {
    const query = try req.query();
    const room_urn = query.get("room") orelse return errorMissingQuery(res, "room");

    const join_form_template = @embedFile("html/join-form.html");
    const join_form_html = try std.fmt.allocPrint(res.arena, join_form_template, .{
        room_urn,
    });

    res.body = join_form_html;
}

pub fn getWebsocket(app: *App, req: *Request, res: *Response) !void {
    const query = try req.query();
    const room_urn = query.get("room") orelse return errorMissingQuery(res, "room");
    const name = query.get("name") orelse return errorMissingQuery(res, "name");

    const room_id = try uuid.urn.deserialize(room_urn);
    const room = app.rooms.get(room_id) orelse return ServerError.RoomNotFound;

    const ctx = Member.Context{
        .app = app,
        .room = room,
        .player = try Player.init(&room.game, name),
        .name = name,
    };

    const connected = try httpz.upgradeWebsocket(Member, req, res, &ctx);
    if (!connected) return errorWebsocketNotConnected(res);
}

pub fn postJoin(_: *App, req: *Request, res: *Response) !void {
    const query = try req.query();
    const room_urn = query.get("room") orelse return errorMissingQuery(res, "room");

    const form = try req.formData();
    const name = form.get("name") orelse return errorMissingFormEntry(res, "name");

    const websocket_template = @embedFile("html/websocket.html");
    const websocket_html = try std.fmt.allocPrint(res.arena, websocket_template, .{
        room_urn,
        name,
    });

    res.body = websocket_html;
}

pub fn msgGame(room: *Room, member: *Member, arena: Allocator) !void {
    const game_template = @embedFile("html/game.html");
    const game_host_template = @embedFile("html/game-host.html");
    const game_html = if (member.is_host) render_for_host: {
        break :render_for_host try std.fmt.allocPrint(arena, game_host_template, .{
            room.name,
            room.urn(),
        });
    } else render_for_member: {
        break :render_for_member try std.fmt.allocPrint(arena, game_template, .{
            room.name,
            room.urn(),
        });
    };

    try member.conn.write(game_html);
}
