const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const server = @import("server.zig");
const rendering = @import("rendering.zig");

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

pub fn errorMissingQuery(res: *Response, query: []const u8) !void {
    res.status = 400;
    res.body = try rendering.errorPage(res.arena, res.status, try rendering.template(res.arena, "Missing query: {s}.", .{query}));
}

pub fn errorMissingFormEntry(res: *Response, form_entry: []const u8) !void {
    res.status = 400;
    res.body = try rendering.errorPage(res.arena, res.status, try rendering.template(res.arena, "Missing form entry: {s}", .{form_entry}));
}

pub fn errorWebsocketNotConnected(res: *Response) !void {
    res.status = 400;
    res.body = try rendering.errorPage(res.arena, res.status, "Failed to establish a connection.");
}

pub const get = struct {
    pub fn @"/"(_: *App, _: *Request, res: *Response) !void {
        res.body = try rendering.index(res.arena);
    }

    pub fn @"/rooms"(app: *App, _: *Request, res: *Response) !void {
        for (app.rooms.values()) |room| {
            const card = rendering.roomCard(res.arena, room) catch continue;
            defer res.arena.free(card);

            res.writer().writeAll(card) catch continue;
        }
    }

    pub fn @"/join"(_: *App, req: *Request, res: *Response) !void {
        const query = try req.query();
        const room_urn = query.get("room") orelse return errorMissingQuery(res, "room");

        res.body = try rendering.memberForm(res.arena, room_urn);
    }

    pub fn @"/create"(_: *App, _: *Request, res: *Response) !void {
        res.body = try rendering.roomForm(res.arena);
    }

    pub fn @"/ws"(app: *App, req: *Request, res: *Response) !void {
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
};

pub const post = struct {
    pub fn @"/room"(app: *App, req: *Request, res: *Response) !void {
        const form = try req.formData();
        const name = form.get("name") orelse return errorMissingFormEntry(res, "name");

        const ctx = Room.Context{
            .app = app,
            .game = Game.init(app.allocator, .{}),
            .name = name,
        };

        const room = try Room.new(&ctx);

        try res.writer().writeAll(try rendering.roomCard(res.arena, room));
        try res.writer().writeAll(try rendering.render(res.arena, rendering.create_room_button));
    }

    pub fn @"/member"(_: *App, req: *Request, res: *Response) !void {
        const query = try req.query();
        const room_urn = query.get("room") orelse return errorMissingQuery(res, "room");

        const form = try req.formData();
        const name = form.get("name") orelse return errorMissingFormEntry(res, "name");

        res.body = try rendering.websocket(res.arena, room_urn, name);
    }
};

pub const msg = struct {
    pub fn game(arena: Allocator, source: *Member) !void {
        try source.conn.write(try rendering.game(arena, source.room, source));
    }

    pub fn memberNames(arena: Allocator, source: *Member) !void {

        const empty_list = try rendering.render(arena, rendering.empty_member_list);
        var list: List(u8) = .{};

        for (source.room.members.values()) |member| {
            list.writer(arena).writeAll(rendering.memberName(arena, member) catch continue) catch continue;
        }

        for (source.room.members.values()) |member| {
            member.conn.write(empty_list) catch continue;
            member.conn.write(list.items) catch continue;
        }
    }
};
