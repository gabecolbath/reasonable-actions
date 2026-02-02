const std = @import("std");
const reasonable_actions = @import("reasonable_actions");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const uuid = @import("uuid");
const scatty = @import("scatty.zig");

pub const server_port = 8802;
pub const server_room_limit = 32;
pub const server_member_limit = server_room_limit * 8;

const index_html = @embedFile("html/index.html");

const Allocator = std.mem.Allocator;
const Uuid = uuid.Uuid;
const Map = std.AutoArrayHashMapUnmanaged;
const List = std.ArrayList;

pub const ServerError = error {
    RoomNotFound,
    MemberNotFound,
    ReachedServerMemberLimit,
    ReachedServerRoomLimit,
};

pub const GameTag = enum {
    scatty,
};

pub const GameIdentifier = union(GameTag) {
    scatty: *scatty.Game,
};

pub const Member = struct {
    id: Uuid,
    seat: u8,
};

pub const Room = struct {
    id: Uuid,
    game: *scatty.Game,
};

pub const App = struct {
    allocator: Allocator,
    rooms: Map(Uuid, Room),
    members: Map(Uuid, Member),

    pub const WebsocketHandler = Client;

    pub fn init(allocator: Allocator) !App {
        var rooms = Map(Uuid, Room){};
        try rooms.ensureTotalCapacity(allocator, server_room_limit);
        errdefer rooms.deinit(allocator);

        var members = Map(Uuid, Member){};
        try members.ensureTotalCapacity(allocator, server_member_limit);
        errdefer members.deinit();

        return App{
            .allocator = allocator,
            .rooms = rooms,
            .members = members,
        };
    }

    pub fn deinit(self: *App) void {
        self.rooms.deinit(self.allocator);
        self.members.deinit(self.allocator);
    }

    pub fn registerMember(self: *App, game: *scatty.Game, player: *scatty.Player) !Member {
        const seat = game.table.join(player.*);
        errdefer game.table.kick(seat);
        const member = Member{
            .id = uuid.v7.new(),
            .seat = seat
        };

        if (self.members.count() < server_member_limit) {
            self.members.putAssumeCapacity(member.id, member);
        } else return ServerError.ReachedServerMemberLimit;

        return member;
    }

    pub fn registerRoom(self: *App, game: *scatty.Game) !Room {
        const room = Room{
            .id = uuid.v7.new(),
            .game = game,
        };

        if (self.rooms.count() < server_room_limit) {
            self.members.putAssumeCapacity(room.id, room);
        } else return ServerError.ReachedServerRoomLimit;

        return room;
    }

    pub fn printRooms(self: *App) void {
        std.debug.print("\n", .{});
        std.debug.print("\t------------------------------------------------------\n", .{});
        std.debug.print("\tRooms:\n", .{});
        std.debug.print("\t------------------------------------------------------\n", .{});

        var iter = self.rooms.iterator();
        while (iter.next()) |entry| {
            const room = entry.value_ptr;
            std.debug.print("\t{s}\n", .{ uuid.urn.serialize(room.id) });
        } else std.debug.print("\n", .{});
    }

    pub fn printMembers(self: *App) void {
        std.debug.print("\n", .{});
        std.debug.print("\t------------------------------------------------------\n", .{});
        std.debug.print("\tMembers:\n", .{});
        std.debug.print("\t------------------------------------------------------\n", .{});

        var iter = self.members.iterator();
        while (iter.next()) |entry| {
            const room = entry.value_ptr;
            std.debug.print("\t{s}\n", .{ uuid.urn.serialize(room.id) });
        } else std.debug.print("\n", .{});
    }
};

pub const Client = struct {
    app: *App,
    member: Uuid,
    room: Uuid,
    conn: *websocket.Conn,

    const Context = struct {
        app: *App,
        username: []const u8,
        game_tag: GameTag,
        room: ?Uuid = null,
    };

    pub fn init(conn: *websocket.Conn, ctx: *const Context) !Client {
        if (ctx.room) |id| {
            const room = ctx.app.rooms.get(id) orelse return ServerError.RoomNotFound;
            const game = room.game;

            const player = try scatty.Player.init(game, ctx.username);
            const seat = try game.table.join(player);
            errdefer game.table.kick(seat);

            const member = Member{ .id = uuid.v7.new(), .seat = seat };
            ctx.app.members.putAssumeCapacity(member.id, member);
            errdefer _ = ctx.app.members.swapRemove(member.id);

            return Client{
                .app = ctx.app,
                .member = member.id,
                .room = room.id,
                .conn = conn,
            };
        } else {
            const game = try ctx.app.allocator.create(scatty.Game);
            errdefer ctx.app.allocator.destroy(game);
            game.* = try scatty.Game.init(ctx.app.allocator, .{});
            errdefer game.deinit();

            const room = Room{ .id = uuid.v7.new(), .game = game };
            ctx.app.rooms.putAssumeCapacity(room.id, room);
            errdefer _ = ctx.app.rooms.swapRemove(room.id);

            const player = try scatty.Player.init(game, ctx.username);
            const seat = try game.table.join(player);
            errdefer game.table.kick(seat);

            const member = Member{ .id = uuid.v7.new(), .seat = seat };
            ctx.app.members.putAssumeCapacity(member.id, member);
            errdefer _ = ctx.app.members.swapRemove(member.id);

            return Client{
                .app = ctx.app,
                .member = member.id,
                .room = room.id,
                .conn = conn,
            };
        }
    }

    pub fn afterInit(self: *Client) !void {
        const room = self.app.rooms.get(self.room) orelse return;
        const member = self.app.members.get(self.member) orelse return;

        const game = room.game;
        const player = game.table.player(member.seat) orelse return;

        var buffer: [256]u8 = undefined;
        const username: []const u8 = std.mem.sliceTo(&player.username, 0);
        const msg = try std.fmt.bufPrint(&buffer, "<div id=\"game\" hx-swap-oob=\"outerHTML\">User .. {s} .. joined!</div>", .{username});

        std.debug.print("[member : {s} :: player : {s}] joined [room : {s}]\n", .{
            uuid.urn.serialize(member.id),
            username,
            uuid.urn.serialize(room.id),
        });

        self.app.printRooms();
        self.app.printMembers();

        try self.conn.write(msg);
    }

    pub fn clientMessage(_: *Client, _: []const u8) !void {
        // TODO
    }

    pub fn clientClose(self: *Client, _: []const u8) !void {
        std.debug.print("[member : {s} :: player : {s}] left [room : {s}]\n", .{
            uuid.urn.serialize(self.member),
            self.fetchPlayer().?.username,
            uuid.urn.serialize(self.room)
        });

        defer {
            _ = self.app.members.swapRemove(self.member);
            self.app.printRooms();
            self.app.printMembers();
        }

        const player = self.fetchPlayer() orelse return;
        const game = self.fetchGame() orelse return;
        game.table.kick(player.id);

    }

    pub fn fetchGame(self: *Client) ?*scatty.Game {
        const room = self.app.rooms.get(self.room) orelse return null;
        return room.game;
    }

    pub fn fetchPlayer(self: *Client) ?*scatty.Player {
        const game = self.fetchGame() orelse return null;
        const member = self.app.members.get(self.member) orelse return null;
        return game.table.player(member.seat);
    }
};

pub fn start(allocator: Allocator, app: *App) !httpz.Server(*App) {
    var server = try httpz.Server(*App).init(allocator, .{
        .port = server_port,
    }, app);

    var router = try server.router(.{});
    router.get("/", indexPage, .{});
    router.get("/game", gamePage, .{});
    router.post("/join", joinPage, .{});

    std.debug.print("Listening http://localhost:{d}/\n", .{server_port});

    try server.listen();
    return server;
}

pub fn indexPage(_: *App, _: *httpz.Request, res: *httpz.Response) !void {
    res.body = index_html;
}

pub fn gamePage(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const ctx = Client.Context{
        .app = app,
        .username = "test_username",
        .game_tag = .scatty,
    };

    if (try httpz.upgradeWebsocket(Client, req, res, &ctx) == false) {
        res.status = 500;
        res.body = "Invalid Websocket";
    }
}

pub fn joinPage(_: *App, _: *httpz.Request, res: *httpz.Response) !void {
    const html = @embedFile("html/join.html");
    res.body = html;
}
