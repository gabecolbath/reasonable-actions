const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const conf = @import("config.zig");
const routes = @import("routes.zig");
const command = @import("command.zig");
const mustache = @import("mustache");

const websocket = httpz.websocket;

pub const ServerError = error {
    RoomNotFound,
    MemberNotFound,
    MemberNotConnected,
    MissingFromWaitlist,
};

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AutoHashMap = std.AutoArrayHashMap;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Connection = websocket.Conn;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){}; 
const Request = httpz.Request;
const Response = httpz.Response;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

pub const Member = struct {
    uid: Uuid,
    name: []const u8,
    client: ?*Client,
};

pub const Room = struct {
    uid: Uuid,
    name: []const u8,
    member_list: *ArrayListUnmanaged(Uuid),
};

pub const Client = struct {
    app: *Application,
    member: Member,
    room: Room,
    conn: ?*Connection = null,

    const Self = @This();

    pub const Context = struct {
        app: *Application,
        member_id: Uuid,
        room_id: Uuid,
    };

    pub fn init(conn: *Connection, ctx: *const Context) !Client {
        try ctx.app.clientConnect(conn, ctx.client_id);

        const member = ctx.app.members.get(ctx.member_id) orelse return ServerError.MemberNotFound;
        const room = ctx.app.rooms.get(ctx.room_id) orelse return ServerError.RoomNotFound;

        return Self{
            .app = ctx.app,
            .member = member,
            .room = room,
            .conn = conn,
        };
    }

    pub fn afterInit(self: *Self) !void {
        debugPrintClientConnect(self);
    }

    pub fn clientMessage(self: *Self, data: []const u8) !void {
        var arena = ArenaAllocator.init(self.app.allocator);
        const cmd = self.app.cmd.parseCommand(&arena, data, self) catch |err| {
            std.debug.print("Error Handling Client Message: {}\n", .{err});
            return err;
        };
        try self.app.cmd.exec(&arena, cmd);
    }

    pub fn close(self: *Self) void {
        debugPrintClientDisconnect(self);
    }
};

pub const Application = struct {
    allocator: Allocator,
    cmd: command.Handler,
    waiting: AutoHashMap(Uuid, Client),
    members: AutoHashMap(Uuid, Member),
    rooms: AutoHashMap(Uuid, Room),

    const Self = @This();
    pub const WebsocketHandler = Client;

    pub fn init(arena: *ArenaAllocator) !Self {
        var waiting_map = AutoHashMap(Uuid, Client).init(arena.allocator());
        var member_map = AutoHashMap(Uuid, Member).init(arena.allocator());
        var room_map = AutoHashMap(Uuid, Room).init(arena.allocator());
        
        try waiting_map.ensureTotalCapacity(conf.server_members_cpacity);
        try member_map.ensureTotalCapacity(conf.server_members_cpacity);
        try room_map.ensureTotalCapacity(conf.server_members_cpacity);

        return Self{
            .allocator = arena.allocator(),
            .cmd = command.Handler{ .map = &command.builtin_cmd_map },
            .waiting = waiting_map,
            .members = member_map,
            .rooms = room_map,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.waiting.deinit();
        self.members.deinit();
        self.rooms.deinit();
    }

    pub fn openRoom(self: *Self, name: []const u8) !Room {
        const generated_room_id = uuid.v7.new();
        const generated_room_name = try self.allocator.dupe(u8, name);
        const generated_member_list = try self.allocator.create(ArrayListUnmanaged(Uuid));
        const new_room = Room{
            .uid = generated_room_id,
            .name = generated_room_name,
            .member_list = generated_member_list,
        };

        self.rooms.putAssumeCapacity(new_room.uid, new_room);
        return new_room;
    }

    pub fn closeRoom(self: *Self, uid: Uuid) void {
        const closing_room = self.rooms.get(uid) orelse return;
        for (closing_room.member_list.items) |member_uid| {
            const room_member = self.members.get(member_uid) orelse continue;
            const room_client = room_member.client orelse continue;
            const room_conn = room_client.conn orelse continue;
            room_conn.close(.{}) catch continue;
        }

        const room_still_exists = self.rooms.get(uid);
        if (room_still_exists) |room| {
            room.member_list.deinit(self.allocator);
            self.allocator.destroy(room.member_list);
            self.allocator.free(room.name);

            _ = self.rooms.swapRemove(uid);
        }
    }

    pub fn newMember(self: *Self, name: []const u8) !Member {
        const generated_member_id = uuid.v7.new();
        const generated_member_name = try self.allocator.dupe(u8, name);
        const new_member = Member{
            .uid = generated_member_id,
            .name = generated_member_name,
            .client = null,
        };

        self.members.putAssumeCapacity(new_member.uid, new_member);
        return new_member;
    }

    pub fn nameOfMember(self: *Self, member_id: Uuid) ![]const u8 {
        const member = self.members.get(member_id) orelse return ServerError.MemberNotFound;
        return member.name;
    }

    pub fn nameOfRoom(self: *Self, room_id: Uuid) ![]const u8 {
        const room = self.rooms.get(room_id) orelse return ServerError.RoomNotFound;
        return room.name;
    }
    
    pub fn roomMembersOf(self: *Self, room_id: Uuid) ![]Uuid {
        const room = self.rooms.get(room_id) orelse return ServerError.RoomNotFound;
        return room.client_ids.items;
    }

    pub fn queryMemberByName(self: *Self, member_name: []const u8) !Uuid {
        for (self.members.values()) |possible_match| {
            if (std.mem.eql(u8, member_name, possible_match.name)) {
                return possible_match.uid;
            }
        } else return ServerError.MemberNotFound;
    }

    pub fn queryRoomByName(self: *Self, room_name: []const u8) !Uuid {
        for (self.rooms.values()) |possible_match| {
            if (std.mem.eql(u8, room_name, possible_match.name)) {
                return possible_match.uid;
            }
        } else return ServerError.RoomNotFound;
    }
};

pub fn start() !void {
    var server_arena = ArenaAllocator.init(std.heap.page_allocator);
    defer server_arena.deinit();
    
    var app = try Application.init(&server_arena);
    defer app.deinit();
    
    var server = try httpz.Server(*Application).init(server_arena.allocator(), .{
        .port = conf.port,
        .request = .{
            .max_form_count = 20,
        }
    }, &app);
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});
    for (routes.map.get.keys(), routes.map.get.values()) |path, action|
        router.get(path, action, .{});
    for (routes.map.post.keys(), routes.map.post.values()) |path, action|
        router.post(path, action, .{});

    try server.listen();
}

pub fn debugPrintClientConnect(client: *Client) void {
    std.debug.print("[client : {s}] [name : {s}] ~~ [room : {s}] [name : {s}]\n", .{
        uuid.urn.serialize(client.member.uid),
        client.member.name,
        uuid.urn.serialize(client.room.uid),
        client.room.name,
    });
}

pub fn debugPrintClientDisconnect(client: *Client) void {
    std.debug.print("[client : {s}] [name : {s}] X> [room : {s}] [name : {s}]\n", .{
        uuid.urn.serialize(client.member.uid),
        client.member.name,
        uuid.urn.serialize(client.room.uid),
        client.room.name,
    });
}

pub fn debugPrintMemberJoin(client: Member, room: Room) void {
    std.debug.print("[client : {s}] [name : {s}] -> [room : {s}] [name : {s}]\n", .{
        uuid.urn.serialize(client.uid),
        client.name,
        uuid.urn.serialize(room.uid),
        room.name,
    });
}

pub fn debugPrintMemberCreate(client: Member, room: Room) void {
    std.debug.print("[client : {s}] [name : {s}] *> [room : {s}] [name : {s}]\n", .{
        uuid.urn.serialize(client.uid),
        client.name,
        uuid.urn.serialize(room.uid),
        room.name,
    });
}

pub fn debugPrintMemberList(app: *Application, room: Room) void {
    std.debug.print("[room : {s}] [name : {s}] Clients: \n", .{
        uuid.urn.serialize(room.uid),
        room.name,
    });
    for (room.member_list.items, 0..) |client_id, count| {
        const client_name = app.nameOfMember(client_id) catch "???";
        std.debug.print("\t{d}. [client : {s}] [name : {s}]\n", .{
            count,
            uuid.urn.serialize(client_id),
            client_name,
        });
    }
}
