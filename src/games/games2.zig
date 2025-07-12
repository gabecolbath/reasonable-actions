const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Order = std.math.Order;
const Uuid = uuid.Uuid;


const cli = @import("../client.zig");
const server = @import("../server.zig");

const Client = cli.Client;
const Member = server.Member;
const Room = server.Room;

const GameMap = std.EnumMap(GameIdentifier, type);
const SceneQueue = std.PriorityQueue(GameScene, void, Order);
const SourceMap = std.AutoArrayHashMapUnmanaged(Uuid, Source);
const ViewMap = std.AutoArrayHashMapUnmanaged(Uuid, []const u8);
const Waitlist = std.AutoArrayHashMapUnmanaged(Uuid, void);


const available_games = GameMap.init(.{
    .scatty = @import("scatty/scatty.zig"),
});


const GameIdentifier = enum {
    scatty,  
};


const GameView = struct {
    map: ViewMap,
    source: *Source,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, source: *Source) !Self {
        var map = ViewMap{};
        try map.ensureTotalCapacity(allocator, source.room.members.count());
        
        return ViewMap{
            .map = map,
            .source = source,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.map.deinit(allocator);
    }
};


const GameScene = struct {
    ptr: *anyopaque,
    v_table: VTable,
    
    const Self = @This();
    
    const VTable = struct {
        render: fn (any: *anyopaque, allocator: Allocator, control: Controllers) anyerror!GameView,
        update: fn (any: *anyopaque, allocator: Allocator, control: Controllers) anyerror!?GameScene, 
    };

    pub fn init(scene: anytype) Self {
        const Ptr = @TypeOf(scene);
        assert(@typeInfo(Ptr) == .pointer);
        assert(@typeInfo(Ptr).pointer.size == .one);
        assert(@typeInfo(@typeInfo(Ptr).pointer.child) == .@"struct");
        
        const impl = struct {
            fn render(any: *anyopaque, allocator: Allocator, control: Controllers) !GameView {
                const self: Ptr = @ptrCast(@alignCast(any));
                try self.render(allocator, control);
            }  

            fn update(any: *anyopaque, allocator: Allocator, control: Controllers) !?GameScene {
                const self: Ptr = @ptrCast(@alignCast(any)); 
                try self.update(allocator, control);
            }
        };

        return Self{
            .ptr = scene,
            .v_table = .{
                .render = impl.render,
                .update = impl.update,
            }
        };
    }

    pub fn render(self: *Self, allocator: Allocator, control: Controllers) !GameView {
        return try self.v_table.render(self, allocator, control);      
    }

    pub fn update(self: *Self, allocator: Allocator, control: Controllers) !?GameScene {
        return try self.v_table.update(self, allocator, control);
    }
};


const GameLoop = struct {
    scene: GameScene,
    queued: SceneQueue,
    waitlist: Waitlist,
    repeat: u8 = 0,

    const Self = @This();

    pub fn init(allocator: Allocator, start: GameScene) !Self {
        const waitlist = Waitlist{};
        
        return Self{
            .current = start,
            .scenes = SceneQueue.init(allocator, {}),
            .waitlist = waitlist,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.scenes.deinit();
        self.waitlist.deinit(allocator);
    }
};


const State = struct {
    ptr: *anyopaque,

    const Self = @This();
    
    pub fn init(StateType: type, allocator: Allocator) !Self {
        const new_state = try allocator.create(StateType);
        new_state.* = StateType.init(allocator);
        
        return Self{
            .ptr = new_state,
        };
    }
    
    pub fn as(self: *const Self, StateType: type) *StateType {
        return @ptrCast(@alignCast(self.ptr));
    }
};


const Controllers = struct {
    player: Player.Controller,
    game: Game.Controller,
}; 


const Player = struct {
    allocator: Allocator,
    tag: GameIdentifier,
    member: *Member,
    state: State,
    controller: Controller,

    const Self = @This();

    const Controller = struct {
        state: *State,       

        pub fn init(client: *Client) !Controller {
            const player = client.member.attached.player orelse return server.ServerError.NoAttachedPlayer;
            
            return Controller{
                .state = player.state,
            };
        }
    };
};


const Game = struct {
    mem: Memory,
    tag: GameIdentifier,
    room: *Room,
    state: State,
    loop: GameLoop,
    controller: Controllers,
    
    const Self = @This();
    
    const Controller = struct {
        state: *State,
        loop: *GameLoop,

        pub fn init(client: *Client) !Controller {
            const game = client.room.attached.game orelse return server.ServerError.NoAttachedGame;
            
            return Controller{
                .state = game.state,
            };
        }
    };

    const Memory = struct {
        fba: FixedBufferAllocator,
        buffer: []u8,
    };

    pub fn init(instance: anytype, host: *Client) !Self {
        
    }
};
