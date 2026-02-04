const std = @import("std");
const reasonable_actions = @import("reasonable_actions");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const uuid = @import("uuid");
const scatty = @import("scatty.zig");
const rendering = @import("rendering.zig");

pub const server_port = 8802;
pub const server_room_limit = 32;
pub const server_member_limit = server_room_limit * 8;

const index_template = @embedFile("html/index.html");

const Allocator = std.mem.Allocator;
const Uuid = uuid.Uuid;
const Map = std.AutoArrayHashMapUnmanaged;
const List = std.ArrayList;

pub const ServerError = error {
    RoomNotFound,
    MemberNotFound,
    ReachedServerMemberLimit,
    ReachedServerRoomLimit,
    InvalidUsername,
    MissingQuery,
};

pub const GameTag = enum {
    scatty,
};

pub const GameIdentifier = union(GameTag) {
    scatty: *scatty.Game,
};

pub const Room = struct {
    id: Uuid,
    clients: List(Uuid),
    game: scatty.Game,
};

pub const App = struct {
    allocator: Allocator,
    members: Map(Uuid, *Member),
    rooms: Map(Uuid, *Room),
    members: Map(Uuid, *Member),

    pub const WebsocketHandler = Client;

    pub fn init(allocator: Allocator) !App {
        var clients = Map(Uuid, Client){};
        try clients.ensureTotalCapacity(allocator, server_member_limit);
        errdefer clients.deinit(allocator);

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

    pub fn deinit(_: *App) void {
        // TODO
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

pub const Member = struct {
    conn: *websocket.Conn,
    app: *App,
    id: Uuid,
    member_id: Uuid,
    room_id: Uuid,
    username: []const u8,

    pub const Context = struct {
        app: *App,
        room: Uuid,
        username: []const u8,
    };

    pub fn init(conn: *websocket.Conn, ctx: *const Context) !Client {
        return Client{
            .conn = conn,
            .app = ctx.app,
            .id = uuid.v7.new(),
            .member_id = uuid.v7.new(),
            .room_id = ctx.room,
            .username = try ctx.app.allocator.dupe(u8, ctx.username),
        };
    }

    pub fn afterInit(self: *Client) !void {
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();
        try rendering.msgGame(self, arena.allocator());
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

    pub fn room(self: *Client) *Room {
        return self.app.rooms.get(self.room_id);
    }

    pub fn member(self: *Client) *Member {
        return self.app.members.get(self.member_id);
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
        .request = .{ .max_form_count = 8 },
    }, app);

    var router = try server.router(.{});
    // Get Requests
    router.get("/", rendering.getIndex, .{});
    router.get("/rooms", rendering.getRooms, .{});
    router.get("/join", rendering.getJoin, .{});
    router.get("/ws", rendering.getWebsocket, .{});
    // Post Requests
    router.post("/join", rendering.postJoin, .{});

    std.debug.print("Listening http://localhost:{d}/\n", .{server_port});

    try server.listen();
    return server;
}
