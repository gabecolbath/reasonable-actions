const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const conf = @import("config.zig");
const routes = @import("routes.zig");
const cmd = @import("command.zig");
const mustache = @import("mustache");
const game = @import("game.zig");

const websocket = httpz.websocket;

pub const ServerError = error {
    RoomNotFound,
    ClientNotFound,
    GameNotFound,
    MissingFromConnectionWaitList,
    ClientNotConnected,
    NoActiveGame,
};

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AutoHashMap = std.AutoArrayHashMap;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){}; 
const GameState = game.GameState;
const Request = httpz.Request;
const Response = httpz.Response;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

pub const Client = struct {
    uid: Uuid,
    room_id: Uuid,
    name: []const u8,
    ws_conn: ?*websocket.Conn,
};

pub const Room = struct {
    uid: Uuid,
    client_ids: *ArrayListUnmanaged(Uuid),
    name: []const u8,
};

pub const Connection = struct {
    app: *Application,
    game_state: ?*GameState,
    client: Client,
    room: Room,

    const Self = @This();

    pub const Context = struct {
        app: *Application,
        client_id: Uuid,
    };

    pub fn init(conn: *websocket.Conn, ctx: *const Context) !Connection {
        try ctx.app.connect(conn, ctx.client_id);

        const client = ctx.app.clients.get(ctx.client_id) orelse return ServerError.ClientNotFound;
        const room = ctx.app.rooms.get(client.room_id) orelse return ServerError.RoomNotFound;

        return Self{
            .app = ctx.app,
            .game_state = null,
            .client = client,
            .room = room,
        };
    }

    pub fn initAssumeEstablished(app: *Application, client: Client, room: Room) Connection {
        return Connection{
            .app = app,
            .client = client,
            .room = room,
        };
    }

    pub fn afterInit(self: *Self) !void {
        debugPrintConnectMessage(self.client, self.room);

        const content = routes.room_html;
        try cmd.respondSelf(self, content);
    }


    pub fn clientMessage(self: *Self, data: []const u8) !void {
        var arena_wrapper = ArenaAllocator.init(self.app.app_arena);
        const arena = arena_wrapper.allocator();
        defer arena_wrapper.deinit();

        cmd.handleMessageAsCommand(arena, self, data) catch |err| {
            std.debug.print("Error Handling Client Message: {}\n", .{err});
        };
    }

    pub fn close(self: *Self) void {
        debugPrintDisconnectMessage(self.client, self.room);
        self.app.disconnect(self);

        var arena_wrapper = ArenaAllocator.init(self.app.app_arena);
        const arena = arena_wrapper.allocator();
        defer arena_wrapper.deinit();
        
        cmd.updatePlayerListsLeave(arena, self, null) catch return;
    }
};

pub const Application = struct {
    app_arena: Allocator,
    games_arena: Allocator,
    waiting: AutoHashMap(Uuid, Connection),
    clients: AutoHashMap(Uuid, Client),
    rooms: AutoHashMap(Uuid, Room),
    games: AutoHashMap(Uuid, *GameInstance),

    const Self = @This();
    pub const WebsocketHandler = Connection;

    pub fn init(app_arena: *ArenaAllocator, games_arena: *ArenaAllocator) !Self {
        var waiting_map = AutoHashMap(Uuid, Connection).init(app_arena.allocator());
        var client_map = AutoHashMap(Uuid, Client).init(app_arena.allocator());
        var room_map = AutoHashMap(Uuid, Room).init(app_arena.allocator());
        var game_map = AutoHashMap(Uuid, *GameInstance).init(app_arena.allocator());
        
        try waiting_map.ensureTotalCapacity(conf.num_clients_capacity);
        try client_map.ensureTotalCapacity(conf.num_clients_capacity);
        try room_map.ensureTotalCapacity(conf.num_clients_capacity);
        try game_map.ensureTotalCapacity(conf.num_rooms_capacity);

        return Self{
            .app_arena = app_arena.allocator(),
            .waiting = waiting_map,
            .clients = client_map,
            .rooms = room_map,
            .games = game_map,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.waiting.deinit();
        self.clients.deinit();
        self.rooms.deinit();
        self.games.deinit();
    }

    pub fn join(self: *Self, client_name: []const u8, room_id: Uuid) !Uuid {
        const room_joining = self.rooms.get(room_id) orelse return ServerError.RoomNotFound;

        const generated_client_uid = uuid.v7.new();
        const generated_client_name = try self.app_arena.dupe(u8, client_name);
        const new_client = Client{
            .uid = generated_client_uid,
            .room_id = room_id,
            .name = generated_client_name,
            .ws_conn = null,
        };

        self.waiting.putAssumeCapacity(new_client.uid, .{
            .app = self,
            .client = new_client,
            .room = room_joining,
        });

        debugPrintJoinMessage(new_client, room_joining);
        return new_client.uid;
    }

    pub fn create(self: *Self, client_name: []const u8, room_name: []const u8) !Uuid {
        const generated_room_uid = uuid.v7.new();
        const generated_room_name = try self.app_arena.dupe(u8, room_name);
        const generated_room_client_list = try self.app_arena.create(ArrayListUnmanaged(Uuid));

        generated_room_client_list.* = try ArrayListUnmanaged(Uuid).initCapacity(self.app_arena, conf.num_members_per_room_capacity);

        const new_room = Room{
            .uid = generated_room_uid,
            .client_ids = generated_room_client_list,
            .name = generated_room_name,
        };

        const generated_client_uid = uuid.v7.new();
        const generated_client_name = try self.app_arena.dupe(u8, client_name);
        const new_client = Client{
            .uid = generated_client_uid,
            .room_id = new_room.uid,
            .name = generated_client_name,
            .ws_conn = null,
        };

        self.waiting.putAssumeCapacity(new_client.uid, .{
            .app = self,
            .client = new_client,
            .room = new_room,
        });

        debugPrintCreateMessage(new_client, new_room); 
        return new_client.uid;
    }

    pub fn connect(self: *Self, conn: *websocket.Conn, client_id: Uuid) !void {
        var waiting_connection = self.waiting.get(client_id) orelse return ServerError.MissingFromConnectionWaitList;
        defer _ = self.waiting.swapRemove(client_id);

        waiting_connection.room.client_ids.appendAssumeCapacity(waiting_connection.client.uid);
        waiting_connection.client.ws_conn = conn;

        self.clients.putAssumeCapacity(waiting_connection.client.uid, waiting_connection.client);
        if (!self.rooms.contains(waiting_connection.room.uid)) {
            self.rooms.putAssumeCapacity(waiting_connection.room.uid, waiting_connection.room);
        }
    }
    
    pub fn disconnect(self: *Self, conn: *Connection) void {
        conn.client.ws_conn = null;
        self.app_arena.free(conn.client.name);
        
        _ = self.clients.swapRemove(conn.client.uid);
        for (conn.room.client_ids.items, 0..) |possible_removal_id, index| {
            if (conn.client.uid == possible_removal_id) {
                _ = conn.room.client_ids.swapRemove(index);       
                break;
            }
        }

        if (conn.room.client_ids.items.len == 0) {
            conn.room.client_ids.deinit(self.app_arena);
            self.app_arena.destroy(conn.room.client_ids);
            self.app_arena.free(conn.room.name);

            _ = self.rooms.swapRemove(conn.room.uid);
        }
    }

    pub fn connectionOf(self: *Self, client_id: Uuid) !*websocket.Conn {
        const client = self.clients.get(client_id) orelse return ServerError.ClientNotFound;
        return client.ws_conn orelse ServerError.ClientNotConnected;
    }

    pub fn clientName(self: *Self, client_id: Uuid) ![]const u8 {
        const client = self.clients.get(client_id) orelse return ServerError.ClientNotFound;
        return client.name;
    }

    pub fn roomName(self: *Self, room_id: Uuid) ![]const u8 {
        const room = self.rooms.get(room_id) orelse return ServerError.RoomNotFound;
        return room.name;
    }
    
    pub fn clientsFrom(self: *Self, room_id: Uuid) ![]Uuid {
        const room = self.rooms.get(room_id) orelse return ServerError.RoomNotFound;
        return room.client_ids.items;
    }

    pub fn gameFrom(self: *Self, room_id: Uuid) !*GameInstance {
        const game_instance = self.games.get(room_id) orelse ServerError.GameNotFound;
        return game_instance;
    }

    pub fn queryClientByName(self: *Self, client_name: []const u8) !Uuid {
        for (self.clients.values()) |possible_match| {
            if (std.mem.eql(u8, client_name, possible_match.name)) {
                return possible_match.uid;
            }
        } else return ServerError.ClientNotFound;
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

pub fn debugPrintConnectMessage(client: Client, room: Room) void {
    std.debug.print("[client : {s}] [name : {s}] ~~ [room : {s}] [name : {s}]\n", .{
        uuid.urn.serialize(client.uid),
        client.name,
        uuid.urn.serialize(room.uid),
        room.name,
    });
}

pub fn debugPrintDisconnectMessage(client: Client, room: Room) void {
    std.debug.print("[client : {s}] [name : {s}] X> [room : {s}] [name : {s}]\n", .{
        uuid.urn.serialize(client.uid),
        client.name,
        uuid.urn.serialize(room.uid),
        room.name,
    });
}

pub fn debugPrintJoinMessage(client: Client, room: Room) void {
    std.debug.print("[client : {s}] [name : {s}] -> [room : {s}] [name : {s}]\n", .{
        uuid.urn.serialize(client.uid),
        client.name,
        uuid.urn.serialize(room.uid),
        room.name,
    });
}

pub fn debugPrintCreateMessage(client: Client, room: Room) void {
    std.debug.print("[client : {s}] [name : {s}] *> [room : {s}] [name : {s}]\n", .{
        uuid.urn.serialize(client.uid),
        client.name,
        uuid.urn.serialize(room.uid),
        room.name,
    });
}

pub fn debugPrintClientList(app: *Application, room: Room) void {
    std.debug.print("[room : {s}] [name : {s}] Clients: \n", .{
        uuid.urn.serialize(room.uid),
        room.name,
    });
    for (room.client_ids.items, 0..) |client_id, count| {
        const client_name = app.clientName(client_id) catch "???";
        std.debug.print("\t{d}. [client : {s}] [name : {s}]\n", .{
            count,
            uuid.urn.serialize(client_id),
            client_name,
        });
    }
}
