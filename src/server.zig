const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const conf = @import("config.zig");
const routes = @import("routes.zig");
const command = @import("command.zig");
const mustache = @import("mustache");
const games = @import("games/games.zig");


const websocket = httpz.websocket;


pub const ServerError = error {
    RoomNotFound,
    MemberNotFound,
    ClientNotFound,
    AtRoomMemberCapacity,
    AtServerMemberCapacity,
    AtServerRoomCapacity,
};


const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AutoArrayHashMapUnmanaged = std.AutoArrayHashMapUnmanaged;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Connection = websocket.Conn;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){}; 
const Game = games.Game;
const GameTag = games.GameTag;
const Player = games.Player;
const Request = httpz.Request;
const Response = httpz.Response;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;


pub const JoinResult = struct {
    room: Room,
    member: Member,
};


pub const Member = struct {
    uid: Identifiers,
    name: []const u8,
    player: *Player,
    
    const Self = @This();
    const Identifiers = struct {
        self: Application.MemberUid,
        room: Application.RoomUid,
    };

    pub fn init(allocator: Allocator, player: *Player, name: []const u8, uid: struct {
        member: ?Uuid = null,
        room: ?Uuid = null,
    }) !Self {
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name); 

        return Self{
            .player = player,
            .name = owned_name,
            .uid = .{ .self = uid.member orelse uuid.v7.new(), .room = uid.room orelse uuid.v7.new() },
        };
    }

    pub fn deinit(self: *const Self, allocator: Allocator) void {
        allocator.free(self.name);
    }

    pub fn changeName(self: *Self, allocator: Allocator, new_name: []const u8) !void {
        const owned_name = try allocator.dupe(u8, new_name);
        allocator.free(self.name);
        self.name = owned_name;
    }
};


pub const Room = struct {
    uid : Identifiers,
    game: *Game,
    
    const Self = @This();
    const Identifiers = struct {
        self: Application.RoomUid,
        host: Application.MemberUid,
        members: *Application.MemberSet, 
    };

    pub fn init(allocator: Allocator, game: *Game, uid: struct {
        room: ?Uuid = null,
        host: ?Uuid = null,
    }) !Self {
        const owned_members = try allocator.create(Application.MemberSet);
        owned_members.* = Application.MemberSet{};
        try owned_members.ensureTotalCapacity(allocator, conf.room_members_capacity);

        return Self{
            .game = game,
            .uid = .{ .self = uid.room orelse uuid.v7.new(), .host = uid.host orelse uuid.v7.new(), .members = owned_members },
        };
    }

    pub fn deinit(self: *const Self, allocator: Allocator) void {
        defer allocator.destroy(self.uid.members);
        self.uid.members.deinit(allocator);
    }

    pub fn assignMember(self: *const Self, member_uid: Application.MemberUid) !void {
        try self.checkCapacity();
        self.uid.members.putAssumeCapacity(member_uid, {});
    }

    pub fn unassignMember(self: *const Self , member_uid: Application.MemberUid) void {
        _ = self.uid.members.swapRemove(member_uid);
    }

    pub fn isHost(self: *const Self, member_uid: Application.MemberUid) bool {
        return member_uid == self.uid.host;
    }

    pub fn newHost(self: *Self, member_uid: ?Application.MemberUid) void {
        if (member_uid) |new_host| {
            self.uid.host = new_host;
        } else {
            self.uid.host = self.uid.members.keys()[0];
        }
    }

    pub fn checkCapacity(self: *const Self) !void {
        if (self.uid.members.count() >= conf.room_members_capacity) {
            return ServerError.AtRoomMemberCapacity;
        }
    }
};


pub const Client = struct {
    uid: Identifiers,
    app: *Application,
    conn: *Connection,

    const Self = @This();

    pub const Context = struct {
        app: *Application,
        game: GameTag,
        uid: Identifiers,
    };

    const Identifiers = struct {
        member: Application.MemberUid,
        room: Application.RoomUid,
    };

    pub fn init(conn: *Connection, ctx: *const Context) !Client {
        if (!ctx.app.rooms.contains(ctx.uid.room)) return ServerError.RoomNotFound;
        if (!ctx.app.members.contains(ctx.uid.member)) return ServerError.MemberNotFound;

        return Self{
            .uid = ctx.uid,
            .app = ctx.app,
            .conn = conn,
        };
    }

    pub fn afterInit(self: *Self) !void {
        self.app.clients.putAssumeCapacity(self.uid.member, self);

        var arena = ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();

        const fetch_game = 
            \\<div id="game"
            \\      hx-trigger="load once"
            \\      hx-vals='{ "cmd": "start" }'
            \\      ws-send>
            \\</div>
        ;
        
        try self.conn.write(fetch_game);
    }

    pub fn clientMessage(self: *Self, data: []const u8) !void {
        var cmd_arena = ArenaAllocator.init(self.app.allocator);
        defer cmd_arena.deinit();

        const source_game = try self.game();
        const cmd = try source_game.cmd.parseCommand(cmd_arena.allocator(), data, self);

        try source_game.cmd.exec(cmd_arena.allocator(), cmd);
    }

    pub fn close(self: *Self) void {
        _ = self.app.clients.swapRemove(self.uid.member);

        const close_member = self.member() catch return;
        defer close_member.deinit(self.app.allocator);
        _ = self.app.members.swapRemove(close_member.uid.self);

        var closed_member_room = self.room() catch return;
        closed_member_room.unassignMember(self.uid.member);
        if (closed_member_room.uid.members.count() == 0) {
            defer _ = self.app.rooms.swapRemove(closed_member_room.uid.self); 
            closed_member_room.deinit(self.app.allocator);
        } else if (self.uid.member == closed_member_room.uid.host) {
            closed_member_room.newHost(null);
            self.app.rooms.putAssumeCapacity(closed_member_room.uid.self, closed_member_room);
        }
    }

    pub fn room(self: *Self) !Room {
        return try self.app.room(self.uid.room);
    }

    pub fn member(self: *Self) !Member {
        return try self.app.member(self.uid.member);
    }

    pub fn host(self: *Self) !Member {
        return try self.app.host(self.uid.room);
    }

    pub fn game(self: *Self) !*Game {
        const source_room = try self.room();
        return source_room.game; 
    }

    pub fn player(self: *Self) !*Player {
        const source_member = try self.member();
        return source_member.player;
    }

    pub fn clientsInRoom(self: *Self, allocator: Allocator) ![]*Client {
        const source_room = try self.room();
        const room_members = source_room.uid.members.keys();
        
        var result = try ArrayListUnmanaged(*Client).initCapacity(allocator, room_members.len);
        errdefer result.deinit(allocator);

        for (room_members) |member_uid| {
            const room_client = self.app.client(member_uid) catch continue;
            result.appendAssumeCapacity(room_client);
        }

        return try result.toOwnedSlice(allocator);
    }
};


pub const Application = struct {
    allocator: Allocator,
    members: MemberMap,
    rooms: RoomMap,
    clients: ClientMap, 

    const Self = @This();
    const MemberMap = AutoArrayHashMapUnmanaged(MemberUid, Member);
    const RoomMap = AutoArrayHashMapUnmanaged(RoomUid, Room);
    const ClientMap = AutoArrayHashMapUnmanaged(MemberUid, *Client);
    const MemberSet = AutoArrayHashMapUnmanaged(MemberUid, void);
    pub const MemberUid = Uuid; 
    pub const RoomUid = Uuid;
    pub const WebsocketHandler = Client;
    
    pub fn init(arena: *ArenaAllocator) !Self {
        var members = MemberMap{};
        var rooms = RoomMap{};
        var clients = ClientMap{};
        
        try members.ensureTotalCapacity(arena.allocator(), conf.server_members_cpacity);
        try rooms.ensureTotalCapacity(arena.allocator(), conf.server_members_cpacity);
        try clients.ensureTotalCapacity(arena.allocator(), conf.server_members_cpacity); 

        
        return Self{
            .allocator = arena.allocator(),
            .members = members,
            .rooms = rooms,
            .clients = clients,
        };
    }

    pub fn deinit(self: *Self) void {
        var client_it = self.clients.iterator();
        while (client_it.next()) |entry| {
            const closing_client = entry.value_ptr.*;
            closing_client.close(); 
        }

        self.members.deinit(self.allocator);
        self.rooms.deinit(self.allocator);
    }

    pub fn member(self: *Self, uid: MemberUid) !Member {
        return self.members.get(uid) orelse return ServerError.MemberNotFound;
    }

    pub fn room(self: *Self, uid: RoomUid) !Room {
        return self.rooms.get(uid) orelse return ServerError.RoomNotFound;
    }

    pub fn client(self: *Self, uid: MemberUid) !*Client {
        return self.clients.get(uid) orelse return ServerError.ClientNotFound;
    }

    pub fn createRoom(self: *Self, game_choice: GameTag, host_name: []const u8) !JoinResult {
        try self.checkRoomCapacity();
        try self.checkMemberCapacity();
        
        const new_game = try Game.new(self.allocator, game_choice);
        errdefer {
            new_game.deinit();
            self.allocator.destroy(new_game);
        }
        const new_player = try Player.new(self.allocator, new_game);
        errdefer {
            new_player.deinit(self.allocator);
            self.allocator.destroy(new_player);
        }

        var new_member = try Member.init(self.allocator, new_player, host_name, .{});
        errdefer new_member.deinit(self.allocator);

        var new_room = try Room.init(self.allocator, new_game, .{
            .room = new_member.uid.room,
            .host = new_member.uid.self,
        });
        errdefer new_room.deinit(self.allocator);
        try new_room.assignMember(new_member.uid.self);

        self.members.putAssumeCapacity(new_member.uid.self, new_member);
        self.rooms.putAssumeCapacity(new_room.uid.self, new_room);

        return JoinResult{
            .room = new_room,
            .member = new_member,
        };
    }

    pub fn joinRoom(self: *Self, member_name: []const u8, uid: struct { room: RoomUid }) !JoinResult {
        try self.checkMemberCapacity();

        const room_joining = try self.room(uid.room);
        
        const new_player = try Player.new(self.allocator, room_joining.game);
        errdefer {
            new_player.deinit(self.allocator);
            self.allocator.destroy(new_player);
        }

        const new_member = try Member.init(self.allocator, new_player, member_name, .{
            .room = uid.room,
        });
        errdefer new_member.deinit(self.allocator);
        try room_joining.assignMember(new_member.uid.self);

        self.members.putAssumeCapacity(new_member.uid.self, new_member);

        return JoinResult{
            .room = room_joining,
            .member = new_member,
        };
    }

    pub fn host(self: *Self, uid: RoomUid) !Member {
        const host_room = try self.room(uid);
        const host_uid = host_room.uid.host; 
        const found = try self.member(host_uid);
        
        return found; 
    }

    pub fn checkRoomCapacity(self: *Self) !void {
        if (self.rooms.count() >= conf.server_rooms_capacity) {
            return ServerError.AtServerRoomCapacity;
        }
    }

    pub fn checkMemberCapacity(self: *Self) !void {
        if (self.members.count() >= conf.server_members_cpacity) {
            return ServerError.AtServerMemberCapacity;
        }
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

    const kitty_room_result = try app.createRoom(.scatty, "Kitty");
    const peggy_room_result = try app.createRoom(.scatty, "Peggy");
    
    const kitty = try app.host(kitty_room_result.room.uid.self);
    const peggy = try app.host(peggy_room_result.room.uid.self);

    std.debug.print("{s}'s Room Created\n", .{ kitty.name });
    std.debug.print("{s}'s Room Created\n", .{ peggy.name });
    
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
