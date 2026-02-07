const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const server = @import("server.zig");

const games = struct {
    const scatty = @import("scatty.zig");
};

const ServerError = server.ServerError;

const Allocator = std.mem.Allocator;
const List = std.ArrayList;
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

pub fn getCreate(_: *App, _: *Request, res: *Response) !void {
    const room_form_html = @embedFile("html/room-form.html");

    res.body = room_form_html;
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
        .player = Player.init(app.allocator, &room.game),
        .name = name,
    };

    const connected = try httpz.upgradeWebsocket(Member, req, res, &ctx);
    if (!connected) return errorWebsocketNotConnected(res);
}

pub fn postMember(_: *App, req: *Request, res: *Response) !void {
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

pub fn postRoom(app: *App, req: *Request, res: *Response) !void {
    const form = try req.formData();
    const name =form.get("name") orelse return errorMissingFormEntry(res, "name");

    const ctx = Room.Context{
        .app = app,
        .game = Game.init(app.allocator, .{}),
        .name = name,
    };

    const room = try Room.new(&ctx);

    const room_card_template = @embedFile("html/room-card.html");
    const create_button_html = "<button hx-get='/create' hx-swap='outerHTML' hx-swap-oob='outerHTML:#room-form'>Create</button>";
    const room_card_html = try std.fmt.allocPrint(res.arena, room_card_template, .{
        room.urn(),
        room.name,
    });

    const res_writer = res.writer();
    try res_writer.writeAll(room_card_html);
    try res_writer.writeAll(create_button_html);
}

pub fn msgGame(room: *Room, member: *Member, arena: Allocator) !void {
    const game_template = @embedFile("html/game.html");
    const game_host_template = @embedFile("html/game-host.html");
    const game_html = if (member.is_host) render_for_host: {
        break :render_for_host try std.fmt.allocPrint(arena, game_host_template, .{
            room.name,
            member.name,
            room.urn(),
        });
    } else render_for_member: {
        break :render_for_member try std.fmt.allocPrint(arena, game_template, .{
            room.name,
            member.name,
            room.urn(),
        });
    };

    try member.conn.write(game_html);
}

pub fn msgMemberNames(room: *Room, _: *Member, arena: Allocator) !void {
    const member_name_template = @embedFile("html/member-name.html");
    var member_name_html_buf: [128]u8 = undefined;
    var member_name_html_data = List(u8){};

    for (room.members.values()) |m| {
        m.conn.write("<div id='member-list' hx-swap-oob='outerHTML:#member-list'></div>") catch {};

        const member_name_html = std.fmt.bufPrint(&member_name_html_buf, member_name_template, .{m.name}) catch continue;
        member_name_html_data.appendSlice(arena, member_name_html) catch continue;
    }

    for (room.members.values()) |m| {
        m.conn.write(member_name_html_data.items) catch continue;
    }
}

// pub fn msgMemberNamesWithExclusion(room: *Room, member: *Member, arena: Allocator) !void {
//     const member_name_template = @embedFile("html/member-name.html");
//     var member_name_html_buf: [128]u8 = undefined;
//     var member_name_html_data = List(u8){};
//
//     for (room.members.values()) |m| {
//         if (m == member) continue;
//         m.conn.write("<div id='member-list' hx-swap-oob='outerHTML:#member-list'></div>") catch {};
//         const member_name_html = std.fmt.bufPrint(&member_name_html_buf, member_name_template, .{m.name}) catch continue;
//         member_name_html_data.appendSlice(arena, member_name_html) catch continue;
//     }
//
//     for (room.members.values()) |m| {
//         if (m == member) continue;
//         m.conn.write(member_name_html_data.items) catch continue;
//     }
// }
