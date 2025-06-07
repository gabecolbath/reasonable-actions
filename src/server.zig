const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const conf = @import("config.zig");
const routes = @import("routes.zig");
const control = @import("control.zig");

const websocket = httpz.websocket;

pub const ServerError = error {
    RoomNotFound,
    ClientNotFound,
    MissingFromConnectionWaitList,
    ClientNotConnected,
};

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AutoHashMap = std.AutoArrayHashMap;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){}; 
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
    client_ids: ArrayListUnmanaged(Uuid),
    name: []const u8,
};

pub const Connection = struct {
    app: *Application,
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
            .client = client,
            .room = room,
        };
    }

    pub fn afterInit(self: *Self) !void {
        debugPrintConnectMessage(self.client, self.room);
        try self.client.ws_conn.?.write(control.room_html);
    }

    pub fn clientMessage(self: *Self, data: []const u8) !void {
        control.handleMessage(self.app.arena, self, data) catch |err| {
            std.debug.print("Error Handling Client Message: {}\n", .{err});
        };
    }

    pub fn close(self: *Self) void {
        debugPrintDisconnectMessage(self.client, self.room);
        self.app.disconnect(self);
    }
};

pub const Application = struct {
    arena: Allocator,
    waiting: AutoHashMap(Uuid, Connection),
    clients: AutoHashMap(Uuid, Client),
    rooms: AutoHashMap(Uuid, Room),

    const Self = @This();
    pub const WebsocketHandler = Connection;

    pub fn init(arena: *ArenaAllocator) !Self {
        var waiting_map = AutoHashMap(Uuid, Connection).init(arena.allocator());
        var client_map = AutoHashMap(Uuid, Client).init(arena.allocator());
        var room_map = AutoHashMap(Uuid, Room).init(arena.allocator());
        
        try waiting_map.ensureTotalCapacity(conf.num_clients_capacity);
        try client_map.ensureTotalCapacity(conf.num_clients_capacity);
        try room_map.ensureTotalCapacity(conf.num_clients_capacity);

        return Self{
            .arena = arena.allocator(),
            .waiting = waiting_map,
            .clients = client_map,
            .rooms = room_map,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.waiting.deinit();
        self.clients.deinit();
        self.rooms.deinit();
    }

    pub fn join(self: *Self, client_name: []const u8, room_id: Uuid) !Uuid {
        const room_joining = self.rooms.get(room_id) orelse return ServerError.RoomNotFound;

        const generated_client_uid = uuid.v7.new();
        const generated_client_name = try self.arena.dupe(u8, client_name);
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
        const generated_room_name = try self.arena.dupe(u8, room_name);
        const generated_room_client_buffer = try self.arena.alloc(Uuid, conf.num_members_per_room_capacity);
        const new_room = Room{
            .uid = generated_room_uid,
            .client_ids = ArrayListUnmanaged(Uuid).initBuffer(generated_room_client_buffer),
            .name = generated_room_name,
        };

        const generated_client_uid = uuid.v7.new();
        const generated_client_name = try self.arena.dupe(u8, client_name);
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
        const waiting_entry = self.waiting.fetchSwapRemove(client_id) orelse return ServerError.MissingFromConnectionWaitList;
        var connecting_room = waiting_entry.value.room;
        var connecting_client = waiting_entry.value.client;   
        
        connecting_client.ws_conn = conn;
        self.clients.putAssumeCapacity(connecting_client.uid, connecting_client);
        connecting_room.client_ids.appendAssumeCapacity(connecting_client.uid);
        
        if (!self.rooms.contains(connecting_room.uid)) {
            self.rooms.putAssumeCapacity(connecting_room.uid, connecting_room);
        }
    }
    
    pub fn disconnect(self: *Self, conn: *Connection) void {
        conn.client.ws_conn = null;
        self.arena.free(conn.client.name);
        
        _ = self.clients.swapRemove(conn.client.uid);
        for (conn.room.client_ids.items, 0..) |possible_removal_id, index| {
            if (conn.client.uid == possible_removal_id) {
                _ = conn.room.client_ids.swapRemove(index);       
                break;
            }
        }

        if (conn.room.client_ids.items.len == 0) {
            self.arena.free(conn.room.name);
            conn.room.client_ids.deinit(self.arena);

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
