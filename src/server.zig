const std = @import("std");
const reasonable_actions = @import("reasonable_actions");
const httpz = @import("httpz");
const uuid = @import("uuid");
const scatty = @import("scatty.zig");

pub const server_port = 8802;
pub const server_room_limit = 32;
pub const server_member_limit = server_room_limit * 8;

const Allocator = std.mem.Allocator;
const Uuid = uuid.Uuid;
const Map = std.AutoArrayHashMapUnmanaged;
const List = std.ArrayList;

pub const GameIdentifier = union(enum) {
    scatty: *scatty.Game,
};

pub const PlayerIdentifier = union(enum) {
    scatty: *scatty.Player,
};

pub const Member = struct {
    id: Uuid,
    player: PlayerIdentifier,
};

pub const Room = struct {
    id: Uuid,
    game: GameIdentifier,
    members: List(Uuid),
};

pub const App = struct {
    allocator: Allocator,
    rooms: Map(Uuid, Room),
    members: Map(Uuid, Member),

    pub fn init(allocator: Allocator) !App {
        var rooms = Map(Uuid, Room){};
        try rooms.ensureTotalCapacity(allocator, server_room_limit);
        errdefer rooms.deinit(allocator);

        var members = Map(Uuid, Member){};
        try members.ensureTotalCapacity(allocator, server_member_limit);
        errdefer members.deinit();

        return App{
            .allocator = allocator,
            .rooms = rooms,
            .members = members,
        };
    }

    pub fn deinit(self: *App) void {
        self.rooms.deinit(self.allocator);
        self.members.deinit(self.allocator);
    }
};

pub fn start(allocator: Allocator, app: *App) !httpz.Server(*App) {
    var server = try httpz.Server(*App).init(allocator, .{
        .port = server_port,
    }, app);

    var router = try server.router(.{});
    router.get("/", index, .{});

    std.debug.print("Listening http://localhost:{d}/\n", .{server_port});

    try server.listen();
    return server;
}

pub fn index(_: *App, _: *httpz.Request, res: *httpz.Response) !void {
    res.body =
        \\<!DOCTYPE html>
        \\<head>
        \\  <h1>Hello, World!</h1>
        \\</head>
    ;
}
