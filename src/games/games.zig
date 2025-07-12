const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const json = std.json;
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Order = std.math.Order;
const PriorityQueue = std.PriorityQueue;
const StaticStringMap = std.StaticStringMap;
const Uuid = uuid.Uuid;


const server = @import("../server.zig");
const cli = @import("../client.zig");
const conf = @import("../config.zig");
const games = struct {
    const scatty = @import("scatty/scatty.zig");
};

const Client = cli.Client;
const ClientSource = cli.ClientSource;
const RoomSource = cli.RoomSource;
const Member = server.Member;
const Room = server.Room;
const Connection = httpz.websocket.Conn;
const RenderedHtml = []const u8;
pub const EventMap = std.StaticStringMap(Event);

pub const Updater = *const fn (allocator: Allocator, client: ClientSource, room: RoomSource) anyerror!?Game.Scene;
pub const Renderer = *const fn (allocator: Allocator, view: *Game.View) anyerror!void;


pub const ParseError = error {
    InvalidJson,
    UnknownEvent,
    MissingEvent,
};


pub const GameError = error {
    InvalidSources,
};


pub const Tag = enum { 
    scatty 
};


pub const Player = struct {
    tag: Tag,
    member: *Member,
    state: *anyopaque,

    const Self = @This();
    const State = *anyopaque;

    pub const Events = struct {
        setup: fn (allocator: Allocator) struct { state: State },
    };
};


pub const Game = struct {
    tag: Tag,
    room: *Room,
    loop: Loop,
    control: Controller,
    events: EventMap,
    state: *anyopaque,
    opts: *anyopaque,

    const Self = @This();
    const Options = *anyopaque;
    const State = *anyopaque;

    pub const Setup = struct {
        opts: Options,
        state: State,
        events: EventMap,
    };

    pub const Controller = struct {
        setup: *const fn (allocator: Allocator) anyerror!Setup,
        start: *const fn (allocator: Allocator) anyerror!Scene,
        end: *const fn (allocator: Allocator, data: Setup) anyerror!void,
    };

    pub const Loop = struct {
        current: Scene,
        queued: Scene.Queued,
        waitlist: RoomSource.Map,
        repeat: usize = 0,

        pub fn next(self: *Loop) ?Scene {
            const next_scene = self.queued.removeOrNull();
            if (next_scene) |new_scene| {
                self.current = new_scene;
                return new_scene;
            } else return null;
        }

        pub fn resetWaitlist(self: *Loop, allocator: Allocator) void {
            try self.waitlist.clearRetainingCapacity(allocator);
        }
    };

    pub const Scene = struct {
        sequence: u8 = 0,
        render: Renderer,
        update: Updater,
        start: ?Updater = null,

        pub const Queued = PriorityQueue(Scene, void, order);

        fn order(_: void, a: Game.Scene, b: Game.Scene) Order {
            return std.math.order(a.sequence, b.sequence);
        }
    };

    pub const View = struct {
        map: Map = Map{},
        source: struct {
            client: ClientSource,
            room: RoomSource,
        },
        
        const Map = std.AutoArrayHashMapUnmanaged(Uuid, Html);
        const Html = []const u8;

        const Query = enum {
            client,
            host,
            all,
        };

        pub fn init(allocator: Allocator, client: ClientSource, room: RoomSource) !View {
            var map = Map{};
            try map.ensureTotalCapacity(allocator, room.all.count());
            
            return View{ 
                .map = map,
                .source = .{
                    .client = client,
                    .room = room,
                },
            };
        }

        pub fn deinit(self: *View, allocator: Allocator) void {
            self.map.deinit(allocator);
        }

        pub fn set(self: *View, query: Query, html: Html) !void {
            switch (query) {
                .client =>  self.map.putAssumeCapacity(self.source.client.uid, html),
                .host =>  self.map.putAssumeCapacity(self.source.room.host.uid, html),
                .all => for (self.source.room.all.values()) |client| {
                    self.map.putAssumeCapacity(client, html);
                },
            }
        }

        fn send(self: *View) !void {
            const all_clients = self.source.all.values();
            for (all_clients) |client| {
                const mapped = self.map.get(client.uid) orelse continue;
                client.conn.write(mapped) catch continue;
            }
        }
    };

    pub fn init(allocator: Allocator, room: *Room, tag: Tag) Self {
        const controllers = switch (tag) {
            .scatty => games.scatty.controllers,
        };

        const setup = try controllers.setup(allocator);
        const start = try controllers.start(allocator);

        const loop = Loop{
            .current = start,
            .queued = Scene.Queued.init(allocator, {}),
            .waitlist = RoomSource.Map{},
        };
        
        var game = Game{
            .tag = tag,
            .room = room,
            .loop = loop,
            .control = controllers,
            .events = setup.events,
            .opts = setup.opts,
            .state = setup.state,
        };

        const room_source = try RoomSource.init(allocator, &game);
        defer room_source.deinit(allocator);

        const initial_view = try start.render(allocator, room_source.host, room_source);
        defer initial_view.deinit(allocator);
        try initial_view.send();

        return game;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.control.end(allocator, .{ .opts = self.opts, .state = self.state });
        self.loop.queued.deinit();
        self.loop.waitlist.deinit(allocator);
    }

    pub fn update(self: *Self, allocator: Allocator, client: *Client) !void {
        const client_source = ClientSource.init(self, client);
        const room_source = try RoomSource.init(allocator, self);
        defer room_source.deinit(allocator);

        const transition: ?Scene = next_scene: {
            if (room_source.waiting()) {
                break :next_scene null;
            } else {
                if (self.loop.repeat > 0) {
                    break :next_scene self.loop.current;
                } else {
                    break :next_scene self.loop.next();
                }
            }
        };

        if (transition) |scene| {
            var view = try View.init(allocator, client_source, room_source);
            defer view.deinit(allocator);

            try scene.render(allocator, &view);
            try view.send();
            
            if (scene.start) |before_update| {
                try before_update(allocator, client_source, room_source);
            }

            self.loop.current = scene;
        }

        self.loop.current.update(allocator, client_source, room_source);
    }
};

pub const Event = struct {
    FormData: type,
    ptr: *anyopaque,
    v_table: VTable,

    const Self = @This();
    const VTable = struct {
        exec: *const fn (self: *anyopaque, allocator: Allocator, trigger: Trigger) anyerror!void,
    };

    pub const Trigger = struct {
        client: ClientSource, 
        room: RoomSource, 
        msg: []const u8,
        
        pub fn formData(self: *const Trigger, allocator: Allocator, FormData: type) !FormData {
            const parsed = try json.parseFromSlice(FormData, allocator, self.msg, .{ .ignore_unknown_fields = true });
            return parsed;
        }
    };

    pub fn init(event: anytype) Self {
        const Ptr = @TypeOf(event);
        assert(@typeInfo(Ptr) == .pointer);
        assert(@typeInfo(Ptr).pointer.size == .one);
        assert(@typeInfo(@typeInfo(Ptr).pointer.child) == .@"struct");

        const impl = struct {
            fn exec(ptr: *anyopaque, allocator: Allocator, trigger: Trigger) !void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                try self.exec(allocator, trigger);
            }
        };

        return Self{
            .ptr = event,
            .v_table = .{
                .exec = impl.exec,
            },
        };
    }

    pub fn exec(self: *Self, allocator: Allocator, trigger: Trigger) !void {
        try self.v_table.exec(self, allocator, trigger);
    }
};
