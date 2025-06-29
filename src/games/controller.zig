const std = @import("std");
const server = @import("../server.zig"); 
const httpz = @import("httpz"); 
const uuid = @import("uuid");
const games = @import("game.zig");
const conf = @import("../config.zig");
const available_games = struct {
    const scatty = @import("scatty/scatty.zig");
};

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const App = server.Application;
const Connection = httpz.websocket.Conn;
const GameMap = std.AutoArrayHashMapUnmanaged(GameUid, *Game);
const GameUid = App.RoomUid;
const Uuid = uuid.Uuid;

const GameTag = enum {
    scatty,
};

const Game = union(GameTag) {
    scatty: available_games.scatty.Game,
}; 


pub const Controller = struct {
    arena: ArenaAllocator,
    app: *App, 
    running: GameMap,

    const Self = @This();
    
    pub fn init(allocator: Allocator, app: *App) !Self {
        var games_map = GameMap{};
        try games_map.ensureTotalCapacity(allocator, conf.server_rooms_capacity);

        return Self{
            .arena = ArenaAllocator.init(allocator),
            .app = app,
            .running = games_map,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.running.values()) |running| {
            switch (running.*) {
                .scatty => |game| game.deinit(), 
            }
        }
        self.arena.deinit(); 
    }

    pub fn newGame(self: *Self, game: GameTag, uid: struct { room: Uuid }) !void {
        const allocator = self.arena.allocator();
        const new_game = try allocator.create(Game);
        switch (game) {
            .scatty => new_game.* = .{ .scatty = available_games.scatty.start(allocator) },
        }

        self.running.putAssumeCapacity(uid.room, new_game); 
    }

    pub fn endGame(self: *Self, uid: GameUid) void {
        const running_game = self.running.get(uid) orelse return;
        switch (running_game.*) {
            .scatty => |game| game.deinit(),
        }
        
        const allocator = self.arena.allocator();
        allocator.destroy(running_game);
        
        _ = self.running.swapRemove(uid);
    }
};
