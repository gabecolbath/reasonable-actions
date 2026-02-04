const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const server = @import("server.zig");

const Allocator = std.mem.Allocator;
const App = server.App;
const Request = httpz.Request;
const Response = httpz.Response;

pub fn getIndex(_: *App, _: *Request, res: *Response) !void {
    const index_html = @embedFile("html/index.html");
    res.body = index_html;
}

pub fn getRooms(app: *App, _: *Request, res: *Response) !void {
    const room_card_template = @embedFile("html/room-card.html");

    var room_iter = app.rooms.iterator();
    const res_writer = res.writer();
    while (room_iter.next()) |entry| {
        const room_urn = uuid.urn.serialize(entry.key_ptr.*);
        res_writer.print(room_card_template, .{
            room_urn,
            room_urn,
        }) catch continue;
    }
}

pub fn getJoin(_: *App, req: *Request, res: *Response) !void {
    const query = try req.query();
    const room_urn = query.get("room") orelse {
        res.status = 400;
        res.body = "Missing Room";
        return;
    };

    const join_form_template = @embedFile("html/join-form.html");
    const join_form_html = try std.fmt.allocPrint(res.arena, join_form_template, .{
        room_urn,
    });

    res.body = join_form_html;
}

pub fn getWebsocket(app: *App, req: *Request, res: *Response) !void {
    const query = try req.query();
    const room_urn = query.get("room") orelse {
        res.status = 400;
        res.body = "Missing Room";
        return;
    };
    const username = query.get("username") orelse {
        res.status = 400;
        res.body = "Missing Username";
        return;
    };

    const ctx = server.Client.Context{
        .app = app,
        .room = try uuid.urn.deserialize(room_urn),
        .username = username,
        .game_tag = .scatty,
    };

    const connected = try httpz.upgradeWebsocket(server.Client, req, res, &ctx);
    if (!connected) {
        res.status = 400;
        res.body = "Connection Failed";
    }
}

pub fn postJoin(_: *App, req: *Request, res: *Response) !void {
    const query = try req.query();
    const room_urn = query.get("room") orelse {
        res.status = 400;
        res.body = "Missing Room";
        return;
    };

    const form = try req.formData();
    const username = form.get("username") orelse {
        res.status = 400;
        res.body = "Missing Username";
        return;
    };

    const websocket_template = @embedFile("html/websocket.html");
    const websocket_html = try std.fmt.allocPrint(res.arena, websocket_template, .{
        room_urn,
        username,
    });

    res.body = websocket_html;
}

pub fn msgGame(client: *server.Client, arena: Allocator) !void {
    const player = client.fetchPlayer() orelse return;

    const game_template = @embedFile("html/game.html");
    const game_html = try std.fmt.allocPrint(arena, game_template, .{
        player.username,
    });

    try client.conn.write(game_html);
}
