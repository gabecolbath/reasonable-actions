const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const rendering = @import("rendering.zig");
const websocket = httpz.websocket;
const json = std.json;
const games = struct {
    const scatty = @import("scatty.zig");
};

const assert = std.debug.assert;

pub const server_port = 8802;
pub const server_room_limit = 32;
pub const server_members_per_room_limit = 8;
pub const server_member_limit = server_room_limit * server_members_per_room_limit;

// std =========================================================================
const Allocator = std.mem.Allocator;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;
const Map = std.AutoArrayHashMapUnmanaged;
const List = std.ArrayList;
const StringMap = std.StaticStringMap;

// httpz =======================================================================
const Request = httpz.Request;
const Response = httpz.Response;

// websocket ===================================================================
const Conn = websocket.Conn;

// scatty ======================================================================
const Game = games.scatty.Game;
const Player = games.scatty.Player;


pub const ServerError = error {
    RoomNotFound,
    MemberNotFound,
    ReachedServerMemberLimit,
    ReachedServerRoomLimit,
    ReachedServerMembersPerRoomLimit,
    InvalidUsername,
    MissingQuery,
};

pub const EventError = error {
    UnknownEvent,
};

pub const GameTag = enum {
    scatty,
};

pub const Event = *const fn (arena: Allocator, room: *Room, member: *Member) anyerror!void;

pub const Room = struct {
    app: *App,
    id: Uuid,
    members: Map(Uuid, *Member),
    game: Game,
    name: []const u8,

    pub const Context = struct {
        app: *App,
        name: []const u8,
        game: Game,
    };

    pub fn new(ctx: *const Context) !*Room {
        const new_room = try ctx.app.allocator.create(Room);
        errdefer ctx.app.allocator.destroy(new_room);
        new_room.* = try Room.init(ctx);
        errdefer new_room.deinit();
        try new_room.afterInit();

        return new_room;
    }

    pub fn init(ctx: *const Context) !Room {
        const id = uuid.v7.new();

        var members = Map(Uuid, *Member){};
        try members.ensureTotalCapacity(ctx.app.allocator, server_members_per_room_limit);
        errdefer members.deinit(ctx.app.allocator);

        const name = try ctx.app.allocator.dupe(u8, ctx.name);
        errdefer ctx.app.allocator.free(name);

        return Room {
            .app = ctx.app,
            .id = id,
            .members = members,
            .game = ctx.game,
            .name = name,
        };
    }

    pub fn deinit(self: *Room) void {
        self.members.deinit(self.app.allocator);
        // self.game.deinit(); TODO
        self.app.allocator.free(self.name);
    }

    pub fn afterInit(self: *Room) !void {
        errdefer _ = self.app.unregisterRoom(self);
        try self.app.registerRoom(self);
    }

    pub fn close(self: *Room) void {
        while (self.members.count() > 0) self.members.values()[0].close();
        self.deinit();
        self.app.allocator.destroy(self);
    }

    pub fn urn(self: *Room) Urn {
        return uuid.urn.serialize(self.id);
    }

    pub fn changeName(self: *Room, new_name: []const u8) !void {
        const old_name = self.name;
        self.name = self.app.allocator.dupe(u8, new_name);
        self.app.allocator.free(old_name);
    }

    pub fn host(self: *Room) ?*Member {
        for (self.members.values()) |member| {
            if (member.is_host) return member;
        } else return null;
    }

    pub fn assignHostTo(self: *Room, assignment: union(enum) { first_available, choose: Uuid }) ?*Member {
        if (self.members.count() == 0) return null;

        var members_iter = self.members.iterator();
        while (members_iter.next()) |entry| {
            const member = entry.value_ptr.*;
            member.is_host = false;
        }

        switch (assignment) {
            .first_available => {
                const new_host = self.members.values()[0];
                new_host.is_host = true;
                return new_host;
            },
            .choose => |chosen| {
                const new_host = self.members.get(chosen) orelse return null;
                new_host.is_host = true;
                return new_host;
            }
        }
    }
};

pub const Member = struct {
    conn: *Conn,
    app: *App,
    id: Uuid,
    room: *Room,
    player: Player,
    name: []const u8,
    is_host: bool = false,
    closed: bool = false,

    pub const Context = struct {
        app: *App,
        room: *Room,
        player: Player,
        name: []const u8,
    };

    pub fn init(conn: *Conn, ctx: *const Context) !Member {
        const id = uuid.v7.new();

        const name = try ctx.app.allocator.dupe(u8, ctx.name);
        errdefer ctx.app.allocator.free(name);

        const is_host = ctx.room.members.count() == 0;

        return Member{
            .conn = conn,
            .app = ctx.app,
            .id = id,
            .room = ctx.room,
            .player = ctx.player,
            .name = name,
            .is_host = is_host,
        };
    }

    pub fn deinit(self: *Member) void {
        // self.player.deinit(); TODO
        self.app.allocator.free(self.name);
    }

    pub fn afterInit(self: *Member) !void {
        errdefer self.close();
        try self.app.registerMember(self);

        try self.onJoinedEvent();
    }

    pub fn clientMessage(self: *Member, msg: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();

        const root: json.Value = (try std.json.parseFromSlice(json.Value, arena.allocator(), msg, .{})).value;
        const obj = if (root == .object) root.object else return;
        const val = obj.get("event") orelse return;
        const path = if (val == .string) val.string else null;

        if (path) |p| {
            std.debug.print("Received event: {s}.\n", .{p});

            var tok = std.mem.tokenizeAny(u8, p, "/");
            const level = tok.next() orelse return;
            if (std.mem.eql(u8, level, "game")) {
                const event = tok.next() orelse return;
                switch (self.room.game.tag) {
                    .scatty => try games.scatty.events.trigger(arena.allocator(), self, event),
                }
            } else return;
        }
    }

    pub fn clientClose(self: *Member, _: []const u8) !void {
        if (!self.closed) {
            defer self.closed = true;
            self.app.unregisterMember(self);
            self.deinit();

            try self.onLeftEvent();
        }
    }

    pub fn close(self: *Member) void {
        if (!self.closed) {
            defer self.closed = true;
            self.app.unregisterMember(self);
            self.deinit();
            self.conn.close(.{}) catch {};

            self.onLeftEvent() catch {};
        }
    }

    pub fn onJoinedEvent(self: *Member) !void {
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();

        switch (self.room.game.tag) {
            .scatty => try games.scatty.events.trigger(arena.allocator(), self, "player-joined"),
        }
    }

    pub fn onLeftEvent(self: *Member) !void {
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();

        if (self.is_host) {
            self.is_host = false;
            const new_host = self.room.assignHostTo(.first_available);
            if (new_host) |host| rendering.msgGame(self.room, host, arena.allocator()) catch {};
        }

        switch (self.room.game.tag) {
            .scatty => try games.scatty.events.trigger(arena.allocator(), self, "player-left"),
        }
    }

    pub fn urn(self: *Member) Urn {
        return uuid.urn.serialize(self.id);
    }

    pub fn changeName(self: *Member, new_name: []const u8) !void {
        const old_name = self.name;
        self.name = try self.app.allocator.dupe(u8, new_name);
        self.app.allocator.free(old_name);
    }
};

pub const EventHandler = struct {
    events: StringMap(Event),

    pub const Source = *Member;

    pub fn init(comptime entries: anytype) EventHandler {
        return EventHandler{
            .events = StringMap(Event).initComptime(entries),
        };
    }

    pub fn trigger(self: *const EventHandler, arena: Allocator, source: Source, event: []const u8) !void {
        const respond = self.events.get(event) orelse return EventError.UnknownEvent;
        try respond(arena, source.room, source);
    }
};

pub const App = struct {
    allocator: Allocator,
    rooms: Map(Uuid, *Room),
    members: Map(Uuid, *Member),

    pub const WebsocketHandler = Member;

    pub fn init(allocator: Allocator) !App {
        var rooms = Map(Uuid, *Room){};
        try rooms.ensureTotalCapacity(allocator, server_room_limit);
        errdefer rooms.deinit(allocator);

        var members = Map(Uuid, *Member){};
        try members.ensureTotalCapacity(allocator, server_member_limit);
        errdefer members.deinit(allocator);

        return App{
            .allocator = allocator,
            .rooms = rooms,
            .members = members,
        };
    }

    pub fn deinit(self: *App) void {
        for (self.rooms.values()) |room| room.close();
        for (self.members.values()) |member| member.close();
        self.rooms.deinit(self.allocator);
        self.members.deinit(self.allocator);
    }

    pub fn registerRoom(self: *App, room: *Room) !void {
        errdefer self.unregisterRoom(room);
        if (self.rooms.count() < server_room_limit) {
            self.rooms.putAssumeCapacity(room.id, room);
        } else return ServerError.ReachedServerRoomLimit;
    }

    pub fn unregisterRoom(self: *App, room: *Room) void {
        _ = self.rooms.swapRemove(room.id);
    }

    pub fn registerMember(self: *App, member: *Member) !void {
        errdefer self.unregisterMember(member);
        if (self.members.count() < server_member_limit) {
            self.members.putAssumeCapacity(member.id, member);
        } else return ServerError.ReachedServerMemberLimit;
        if (member.room.members.count() < server_members_per_room_limit) {
            member.room.members.putAssumeCapacity(member.id, member);
        } else return ServerError.ReachedServerMembersPerRoomLimit;
    }

    pub fn unregisterMember(self: *App, member: *Member) void {
        _ = self.members.swapRemove(member.id);
        _ = member.room.members.swapRemove(member.id);
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
