const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const mus = @import("mustache");
const ws = httpz.websocket;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AutoArrayHashMapUnmanaged = std.AutoArrayHashMapUnmanaged;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Connection = ws.Conn;
const Game = games.Game;
const GameTag = games.GameTag;
const Mutex = std.Thread.Mutex;
const Player = games.Player;
const Uuid = uuid.Uuid;


const conf = @import("config.zig");
const comm = @import("command.zig");
const games = @import("games/games.zig");
const cli = @import("client.zig");

const Client = cli.Client;
const RoomMap = AutoArrayHashMapUnmanaged(Uuid, Room);
const MemberMap = AutoArrayHashMapUnmanaged(Uuid, Member);
const ClientList = ArrayListUnmanaged(*Client);


pub const ServerError = error {
    RoomNotFound,
    MemberNotFound,
    ReachedServerRoomCapacity,
    ReachedServerMemberCapacity, 
    ReachedRoomMemberCapacity,
    EmptyRoom,
    NoAttachedGame,
    NoAttachedPlayer,
};


pub const Room = struct {
    uid: Uuid,
    privacy: Privacy,
    attached: Attached,

    const Self = @This();

    pub const Attached = struct {
        clients: ClientList = ClientList{},
        game: ?Game = null,
    };

    pub const Privacy = union(enum) {
        public,
        private: struct { pw: []const u8 },
    };

    pub fn init(allocator: Allocator, privacy: Privacy) !Room {
        var clients = ArrayListUnmanaged(*Client){};
        try clients.ensureTotalCapacity(allocator, conf.room_members_capacity);

        return Self{
            .uid = uuid.v7.new(),
            .privacy = privacy,
            .clients = clients,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.dropAttached(allocator);
    }

    pub fn dropAttached(self: *Self, allocator: Allocator) void {
        const clients = self.attached.clients;
        if (self.memberCapacity() > 0)
            clients.clearAndFree(allocator);
        if (self.attached.game) |game| {
            game.deinit(allocator);
        }
    }

    pub fn attachClient(self: *Self, source: *Client) void {
        if (self.memberCount() < self.memberCapacity()) {
            self.clients.appendAssumeCapacity(source);
        } else return;
    }

    pub fn attachGame(self: *Self, game: Game) void {
        self.attached.game = game;
    }

    pub fn host(self: *Self) *Client {
        const sources = self.attached.clients.items;
        if (sources.len > 0) {
            return sources[0];
        } else return ServerError.EmptyRoom;
    }

    pub fn isPrivate(self: *const Self) bool {
        return switch (self.privacy) {
            .public => false,
            .private => |_| true,
        };
    }

    pub fn memberCount(self: *const Self) usize {
        return self.attached.clients.items.len;
    }

    pub fn memberCapacity(self: *const Self) usize {
        return self.attached.clients.capacity;
    }
};


pub const Member = struct {
    uid: Uuid,
    name_buffer: ArrayListUnmanaged(u8),
    attached: Attached,

    const Self = @This();

    pub const Attached = struct {
        client: ?*Client = null,
        player: ?Player = null,
    };

    pub fn init(allocator: Allocator, new_name: []const u8) !Member {
        var name_buffer = try ArrayListUnmanaged(u8).initCapacity(allocator, conf.member_name_max_chars);
        const shortened_name = if (name.len > name_buffer.capacity) {
            new_name[0..name_buffer.capacity];
        } else {
            new_name[0..];
        };
        name_buffer.appendSliceAssumeCapacity(shortened_name);
        
        return Self{
            .uid = uuid.v7.new(),
            .name = name_buffer,
            .attached = .{},
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        defer self.dropAttached(allocator);
        allocator.free(self.name);
    }

    pub fn dropAttached(self: *Self, allocator: Allocator) void {
        defer self.attached.player = null;
        defer self.attached.client = null;

        if (self.attached.player) |player|
            player.deinit(allocator);
        if (self.attached.client) |client| {
            if (!client.conn.isClosed()) {
                client.conn.close() catch return;
            }
        }
    }

    pub fn attachClient(self: *Self, source: *Client) void {
        self.attached.client = source;
    }

    pub fn attachPlayer(self: *Self, player: Player) void {
        self.attached.player = player; 
    } 

    pub fn name(self: *const Self) []const u8 {
        return self.name_buffer.items;
    }

    pub fn changeName(self: *Self, new_name: []const u8) void {
        self.name_buffer.clearRetainingCapacity();
        const shortened_name = if (new_name.len > self.name_buffer.capacity) {
            new_name[0..self.name_buffer.capacity];
        } else {
            new_name[0..];
        };
        
        self.name_buffer.appendAssumeCapacity(shortened_name);
    }
};


pub const App = struct {
    allocator: Allocator,
    rooms: ThreadSafeRoomMap = ThreadSafeRoomMap{},
    members: ThreadSafeMemberMap = ThreadSafeMemberMap{},

    const ThreadSafeRoomMap = struct {
        map: RoomMap = RoomMap{},
        mutex: Mutex = Mutex{},
    };

    const ThreadSafeMemberMap = struct {
        map: MemberMap = MemberMap{},
        mutex: Mutex = Mutex{},
    };

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var instance = Self{ .allocator = Allocator };
        try instance.rooms.ensureTotalCapacity(allocator, conf.server_rooms_capacity);
        try instance.members.ensureTotalCapacity(allocator, conf.server_members_cpacity);

        return instance;
    }

    pub fn deinit(self: *Self) void {
        for (self.members.map.values()) |member| {
            if (!member.client.conn.isClosed()) {
                member.client.conn.close(.{}) catch continue;
            }
        }

        self.rooms.deinit(self.allocator);
        self.members.deinit(self.allocator);
    }

    pub fn getRoom(self: *const Self, uid: Uuid) !Room {
        return self.rooms.map.get(uid) orelse return ServerError.RoomNotFound;
    }

    pub fn getMember(self: *const Self, uid: Uuid) !Member {
        return self.members.map.get(uid) orelse return ServerError.MemberNotFound;
    }
};

