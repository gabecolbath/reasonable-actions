const std = @import("std");
const uuid = @import("uuid");
const server = @import("../server.zig");
const conf = @import("../config.zig");
const command = @import("../command.zig");
const games = struct {
    const scatty = @import("scatty/scatty.zig"); 
};


pub const GameError = error {
    InvalidTagString,
};


pub const UpdateError = struct {
    
};


pub const RenderError = error {
    
};


pub const GameTag = enum {
    scatty,
};


const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Client = server.Client;
const Command = command.Command;
const CommandMap = command.StaticCommandMap;
const CommandHandler = command.Handler;
const Order = std.math.Order;
const RenderedHtml = []const u8;
const Uuid = uuid.Uuid;


pub const Updater = *const fn (allocator: Allocator, source: *Client) anyerror!?Game.Scene;
pub const Renderer = *const fn (allocator: Allocator, source: *Client) anyerror!Game.Render;


pub const Player = struct {
    allocator: Allocator,
    state: *anyopaque,
    game_tag: GameTag, 
    client: ?*Client = null,
    
    const Self =  @This();

    pub fn init(allocator: Allocator, tag: GameTag) !Player {
        const init_state = switch (tag) {
            .scatty => games.scatty.PlayerState.init,
        };
        const state = try init_state(allocator);

        return Player{
            .allocator = allocator,
            .state = state,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        const deinit_state = switch (self.game.tag) {
            .scatty => games.scatty.PlayerState.deinit,      
        };
        deinit_state(self.state, allocator);
    } 

    pub fn new(allocator: Allocator, game: *Game) !*Player {
        const new_player = try allocator.create(Player);
        new_player.* = try init(allocator, game);

        return new_player;
    }

};


pub const Game = struct {
    tag: GameTag,
    loop: GameLoop,
    players: PlayerActivityMap,
    waitlist: PlayerSet,
    cmd: CommandHandler,
    current: Scene,
    join: JoinStatus,
    state: *anyopaque, 
    
    const Self = @This();
    const GameLoop = std.PriorityQueue(Scene, void, orderScene);
    const PlayerMap = std.AutoArrayHashMapUnmanaged(Uuid, Player);
    const PlayerSet = std.AutoArrayHashMapUnmanaged(Uuid, void);
    pub const Render = std.AutoArrayHashMapUnmanaged(Uuid, RenderedHtml);

    pub const Scene = struct {
        sequence: u8 = 0,
        views: Renderer,
    };

    pub const JoinStatus = enum {
        locked, unlocked, wait,
    };

    const PlayerActivityMap = struct {
        active: PlayerMap = PlayerMap{},
        inactive: PlayerMap = PlayerMap{},
    };

    pub fn init(allocator: Allocator, tag: GameTag) !Game {
        const init_state = switch (tag) {
            .scatty => games.scatty.GameState.init,
        }; 
        const state = try init_state(allocator);


        const init_scene = switch (tag) {
            .scatty => games.scatty.init_scene, 
        };

        const cmd = switch (tag) {
            .scatty => CommandHandler{ .map = games.scatty.Commanads.map },
        };

        return Game{
            .tag = tag,
            .loop = GameLoop.init(allocator, {}),
            .players = PlayerActivityMap{},
            .waitlist = PlayerSet{},
            .cmd = cmd,
            .current = init_scene,
            .join = .unlocked,
            .state = state,
        };
    }

    pub fn start(self: *Self, source: *Client) !void {
        var arena = ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        
        const views = try self.current.views(arena.allocator(), source);
        try sendToClients(source, views);
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        const deinit_state = switch (self.tag) {
            .scatty => games.scatty.GameState.deinit,
        };
        deinit_state(self.state, allocator);

        self.loop.deinit();
        self.players.active.deinit(allocator);
        self.players.inactive.deinit(allocator);
        self.waitlist.deinit(allocator);
    }

    pub fn new(allocator: Allocator, tag: GameTag) !*Game {
        const new_game = try allocator.create(Game);
        new_game.* = try init(allocator, tag);
        return new_game;
    }
};


fn orderScene(_: void, a: Game.Scene, b: Game.Scene) Order {
    return std.math.order(a.sequence, b.sequence);
}


pub fn toGameTag(str: []const u8) !GameTag {
    const eql = std.ascii.eqlIgnoreCase;
    
    if (eql(str, @tagName(GameTag.scatty))) {
        return GameTag.scatty;
    } else return GameError.InvalidTagString;
}


fn sendToClients(source: *Client, rendered: Game.Render) !void {
    var rendered_it = rendered.iterator();
    while (rendered_it.next()) |view| {
        const targeted_client = source.app.client(view.key_ptr.*) catch continue;
        targeted_client.conn.write(view.value_ptr.*) catch continue;
    }
}
