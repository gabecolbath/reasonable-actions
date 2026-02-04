const std = @import("std");
const mod = @import("reasonable_actions");
const httpz = @import("httpz");
const uuid = @import("uuid");
const websocket = httpz.websocket;
const rendering = mod.rendering;

const assert = std.debug.assert;

pub const server_port = 8802;
pub const server_room_limit = 32;
pub const server_members_per_room_limit = 8;
pub const server_member_limit = server_room_limit * server_members_per_room_limit;

// std =========================================================================
const Allocator = std.mem.Allocator;
const Uuid = uuid.Uuid;
const Map = std.AutoArrayHashMapUnmanaged;
const List = std.ArrayList;

// httpz =======================================================================
const Request = httpz.Request;
const Response = httpz.Response;

// websocket ===================================================================
const Conn = websocket.Conn;

// scatty ======================================================================
const Game = mod.games.scatty.Game;
const Player = mod.games.scatty.Player;


pub const ServerError = error {
    RoomNotFound,
    MemberNotFound,
    ReachedServerMemberLimit,
    ReachedServerRoomLimit,
    ReachedServerMembersPerRoomLimit,
    InvalidUsername,
    MissingQuery,
};

pub const GameTag = enum {
    scatty,
};

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
        errdefer ctx.app.allocator.destroy(Room);
        new_room.* = try Room.init(ctx);
        errdefer new_room.deinit();
        try new_room.afterInit();
    }

    pub fn init(ctx: *const Context) !Room {
        const members = Map(Uuid, *Member){};
        try members.ensureTotalCapacity(ctx.app.allocator, server_members_per_room_limit);
        errdefer members.deinit(ctx.app.allocator);

        const name = try ctx.app.allocator.dupe(u8, ctx.name);
        errdefer ctx.app.allocator.free(name);

        return Room {
            .app = ctx.app,
            .id = uuid.v7.new(),
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
        self.app.registerRoom(self);
    }

    pub fn close(self: *Room) !void {
        while (self.members.count() > 0) self.members.values()[0].close("Room Closed");
        self.deinit();
        self.app.allocator.destroy(self);
    }

    pub fn changeName(self: *Room, new_name: []const u8) !void {
        const old_name = self.name;
        self.name = self.app.allocator.dupe(u8, new_name);
        self.app.allocator.free(old_name);
    }

    pub fn host(self: *Room) ?*Member {
        var members_iter = self.members.iterator();
        while (members_iter.next()) |entry| {
            const member = entry.value_ptr.*;
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
            .first => {
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
    is_host: bool,

    pub const Context = struct {
        app: *App,
        room: Uuid,
        player: Player,
        name: []const u8,
    };

    pub fn init(conn: *Conn, ctx: *const Context) !Member {
        return Member{
            .conn = conn,
            .app = ctx.app,
            .id = uuid.v7.new(),
        };
    }

    pub fn deinit(self: *Member) void {
        // self.player.deinit(); TODO
        self.app.allocator.free(self.name);
    }

    pub fn afterInit(self: *Member) !void {
        errdefer self.close();
        try self.app.registerMember(self);
    }

    pub fn clientMessage(_: *Member, _: []const u8) !void {
        // TODO
    }

    pub fn clientClose(self: *Member, _: []const u8) !void {
        _ = self.app.unregisterMember(self);
        self.deinit();
    }

    pub fn close(self: *Member, reason: []const u8) void {
        _ = self.app.unregisterMember(self);
        self.deinit();
        self.conn.close(.{ .reason = reason });
    }

    pub fn changeName(self: *Member, new_name: []const u8) !void {
        const old_name = self.name;
        self.name = try self.app.allocator.dupe(u8, new_name);
        self.app.allocator.free(old_name);
    }
};

pub const App = struct {
    allocator: Allocator,
    rooms: Map(Uuid, *Room),
    members: Map(Uuid, *Member),

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
        if (member.room.count() < server_members_per_room_limit) {
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
