const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const ws = httpz.websocket;

pub const RoomId = uuid.Uuid;
pub const ClientId = uuid.Uuid;
pub const RoomMap = std.AutoHashMap(RoomId, *Room);
pub const ClientMap = std.AutoHashMap(ClientId, *Client);

pub const AppOptions = struct {
    room: RoomOptions,
    client: ClientOptions,
};

pub const RoomOptions = struct {
    room_client_capacity: usize = 8,
};

pub const ClientOptions = struct {};

pub const App = struct {
    opts: AppOptions,
    arena: std.heap.ArenaAllocator,
    rooms: RoomMap,
    clients: ClientMap,

    pub fn init(allocator: std.mem.Allocator, opts: AppOptions) App {
        return App{
            .opts = opts,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .rooms = RoomMap.init(allocator),
            .clients = ClientMap.init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.arena.deinit();
    }

    pub fn newRoom(self: *App, name: ?[]const u8) !*Room {
        const allocator = self.arena.allocator();
        const new_room = try allocator.create(Room);
        new_room.* = try Room.init(allocator, self, name, self.opts.room);

        try self.rooms.put(new_room.id, new_room);
        return new_room;
    }

    pub fn removeRoom(self: *App, room_id: RoomId) bool {
        const allocator = self.arena.allocator();
        if (self.rooms.get(room_id)) |room_to_remove| {
            allocator.destroy(room_to_remove);
        }

        return self.rooms.remove(room_id);
    }
};

pub const Room = struct {
    opts: RoomOptions,
    arena: std.heap.ArenaAllocator,
    app: *App,
    clients: []?*Client,
    num_clients: usize = 0,
    name: []const u8,
    id: RoomId,

    const RoomError = error{
        AtClientCapacity,
    };

    pub fn init(allocator: std.mem.Allocator, app: *App, name: ?[]const u8, opts: RoomOptions) !Room {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const room_allocator = arena.allocator();
        const set_name_or_default = name orelse genDefaultRoomName(room_allocator);

        return Room{
            .opts = opts,
            .arena = arena,
            .app = app,
            .clients = try room_allocator.alloc(?*Client, opts.room_client_capacity),
            .name = set_name_or_default,
            .id = uuid.v7.new(),
        };
    }

    pub fn deinit(self: *Room) void {
        self.arena.deinit();
    }

    pub fn isAtCapacity(self: *Room) bool {
        return self.num_clients >= self.opts.room_client_capacity;
    }

    pub fn newClient(self: *Room, name: ?[]const u8) !*Client {
        if (!self.isAtCapacity()) {
            const allocator = self.arena.allocator();
            const set_name_or_default = name orelse genDefaultClientName(allocator);
            const new_client = try allocator.create(Client);
            new_client.* = Client{
                .opts = self.app.opts.client,
                .room = self,
                .name = set_name_or_default,
                .id = uuid.v7.new(),
                .conn = null,
            };

            try self.app.clients.put(new_client);
            self.clients[self.num_clients] = new_client;
            self.num_clients += 1;
        } else return RoomError.AtClientCapacity;
    }

    pub fn removeClient(self: *Room, client_id: ClientId) bool {
        const allocator = self.arena.allocator();
        if (self.num_clients > 0) {
            for (0..self.clients.len) |seat| {
                if (self.clients[seat]) |client| {
                    if (client.id == client_id) {
                        allocator.destroy(client);
                        self.clients[seat] = null;
                        self.num_clients -= 1;
                    }
                }
            }
        }

        return self.app.clients.remove(client_id);
    }
};

pub const Client = struct {
    opts: ClientOptions,
    room: *Room,
    name: []const u8,
    id: ClientId,
    conn: ?*ws.Conn,

    pub fn disconnect(self: *Client, opts: anytype) !bool {
        if (self.conn) |connection| {
            try connection.close(opts);
            return true;
        } else return false;
    }

    pub fn connect(self: *Client, conn: *ws.Conn) ?*ws.Conn {
        const old_conn = self.conn;
        self.conn = conn;

        return old_conn;
    }
};

pub fn genDefaultRoomName(allocator: std.mem.Allocator) []const u8 {
    var room_name = std.ArrayList(u8).init(allocator);
    const writer = room_name.writer();

    writer.write("room_") catch return "anonymous_room";
    for (0..4) |_| {
        writer.writeByte(std.crypto.random.intRangeAtMost(u8, 'a', 'z')) catch return "anonymous_room";
    }

    return room_name.toOwnedSlice();
}

pub fn genDefaultClientName(allocator: std.mem.Allocator) []const u8 {
    var client_name = std.ArrayList(u8).init(allocator);
    const writer = client_name.writer();

    writer.write("player_") catch return "anonymous_player";
    for (0..4) |_| {
        writer.writeByte(std.crypto.random.intRangeAtMost(u8, 'a', 'z')) catch return "anonymous_player";
    }

    return client_name.toOwnedSlice();
}
