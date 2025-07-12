const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const mus = @import("mustache");
const ws = httpz.websocket;
const json = std.json;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Uuid = uuid.Uuid;


const server = @import("server.zig");
const games = @import("games/games.zig");
const comm = @import("command.zig");
const builtin = @import("builtin.zig");

const App = server.App;
const Member = server.Member;
const Room = server.Room;
const Command = comm.Command;
const CommandMap = comm.CommandMap;
const Event = games.Event;
const EventMap = games.EventMap;
const Game = games.Game;
const Player = games.Player;
const GameTag = games.Tag;

const ServerError = server.ServerError;


pub const Client = struct {
    app: *App,
    conn: *ws.Conn,
    member: *Member,
    room: *Room,   

    const Self = @This();

    pub const Context = struct {
        app: *App,
        room: Room,
        member: Member, 
        game_tag: GameTag, 
    };

    pub fn init(conn: *ws.Conn, ctx: *const Context) !Client {
        const app = ctx.app;
        const allocator = app.allocator;

        errdefer ctx.room.deinit(allocator);
        errdefer ctx.member.deinit(ctx.app.allocator);

        const new_room = try allocator.create(Room);
        errdefer allocator.destroy(new_room);
        const new_game = try Game.init(allocator, ctx.game_tag);
        errdefer new_game.deinit(allocator);

        const new_member = try allocator.create(Member);
        errdefer allocator.destroy(new_member);
        const new_player = try Game.init(allocator, ctx.game_tag);
        errdefer new_player.deinit(allocator); 

        new_room.* = ctx.room;
        new_member.* = ctx.member;

        try new_room.attachGame(new_game);
        try new_member.attachPlayer(new_player);

        return Self{
            .app = app,
            .conn = conn,
            .member = new_member,
            .room = new_room,
        };
    }

    pub fn afterInit(self: *Self) !void {
        try self.room.attachClient(self);
        errdefer self.room.deinit(self.app.allocator);
        self.member.attachClient(self); 
        errdefer self.member.deinit(self.app.allocator);

        self.app.members.mutex.lock();
        self.app.rooms.mutex.lock();
        self.push();
    }

    pub fn clientMessage(self: *Self, data: []const u8) !void {
        var arena = ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();
        
        try self.pull();
        defer self.push(); 

        const Parsed = struct {
            cmd: ?[]const u8 = null,
            event: ?[]const u8 = null,
        };

        const parsed = try json.parseFromSlice(Parsed, arena.allocator(), data, .{
            .ignore_unknown_fields = true,
        });
        
        if (parsed.value.cmd) |name| {
            const cmd = builtin.commands.get(name) orelse return comm.CommandError.UnknownCommand;
            try cmd.exec(arena.allocator(), self);
        }

        if (parsed.value.event) |trigger| {
            const event: Event = if (self.room.attached.game) |game| {
                game.events.get(trigger) orelse return games.GameError.UnknownEvent;
            } else return ServerError.NoAttachedGame;
            try event.exec(arena.allocator(), .{
                .client = try ClientSource.init(self),
                .room = try RoomSource.init(arena.allocator(), &self.room.attached.game),
                .msg = data,
            });
        }
    }
    
    pub fn close(self: *Self) void {
        self.pull() catch return; 
        defer self.app.members.mutex.unlock();
        defer self.app.rooms.mutex.unlock();
        
        defer self.member.deinit(self.app.allocator);
        _ = self.app.members.map.swapRemove(self.member.uid);

        if (self.room.clients.items.len == 0) {
            defer self.room.deinit(self.app.allocator);
            _ = self.app.rooms.map.swapRemove(self.room.uid);
        }
    }

    pub fn pull(self: *Client) !void {
        self.app.members.mutex.lock();
        self.app.rooms.mutex.lock();

        const member = self.app.members.get(self.member.uid) orelse return ServerError.MemberNotFound;
        const room = self.app.rooms.get(self.room.uid) orelse return ServerError.RoomNotFound;

        self.member.* = member;
        self.room.* = room;
    }

    pub fn push(self: *Client) void {
        self.app.members.map.putAssumeCapacity(self.member.uid, self.member.*);
        self.app.rooms.map.putAssumeCapacity(self.room.uid, self.room.*);

        self.app.members.mutex.unlock();
        self.app.rooms.mutex.unlock();
    }
};


pub const ClientSource = struct {
    uid: Uuid,
    conn: *ws.Conn,
    player: struct {
        state: *anyopaque,
    },
    game: struct {
        loop: *Game.Loop,
        opts: *anyopaque, 
        state: *anyopaque,
    },

    const Self = @This();

    pub fn init(client: *Client) !Self {
        const game = client.room.attached.game orelse return server.ServerError.NoAttachedGame;
        const player = client.member.attached.player orelse return server.ServerError.NoAttachedPlayer;

        return Self{
            .uid = client.member.uid,
            .conn = client.conn,
            .player = .{
                .state = player.state,
            },
            .game = .{
                .loop = &game.loop,
                .opts = game.opts,
                .state = game.state,
            }
        };
    }

    pub fn wait(self: *Self, allocator: Allocator) !void {
        self.game.loop.waitlist.put(allocator, self.uid, self.*);
    }

    pub fn ready(self: *Self) void {
        _ = self.game.loop.waitlist.orderedRemove(self.uid);
    }

    pub fn waiting(self: *const Self) bool {
        return self.game.loop.waitlist.contains(self.uid);
    }
};

pub const RoomSource = struct {
    host: ClientSource,
    all: Map,
    game: struct {
        loop: *Game.Loop,
        opts: *anyopaque,
        state: *anyopaque,
    },

    const Self = @This(); 
    pub const Map = std.AutoArrayHashMapUnmanaged(Uuid, ClientSource);

    pub fn init(allocator: Allocator, game: *Game) !RoomSource {
        var all = Map{};
        try all.ensureTotalCapacity(allocator, game.room.memberCount());
        errdefer all.deinit(allocator);

        const host_source = try ClientSource.init(game.room.host());

        for (game.room.attached.clients.items) |client| {
            const client_source = ClientSource.init(client);
            all.putAssumeCapacity(client.member.uid, client_source);
        }

        return RoomSource{
            .host = host_source,
            .all = all,
            .loop = host_source.loop,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.all.deinit(allocator);
    }

    pub fn wait(self: *Self, allocator: Allocator) !void {
        try self.game.loop.waitlist.ensureTotalCapacity(allocator, self.all.count());
        for (self.all.values()) |source| {
            source.wait(allocator) catch continue;
        }
    }

    pub fn waiting(self: *const Self) bool {
        return self.game.loop.count() > 0;
    }
};


