const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const mustache = @import("mustache");
const conf = @import("config.zig");
const server = @import("server-2.zig");

const websocket = httpz.websocket;

const CmdError = error {
    InvalidJson,
    UnknownCmd,
};

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const App = server.Application;
const Connection = server.Connection;
const CmdMap = std.StaticStringMap(Action);
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

const Action = fn (arena: Allocator, conn: *server.Connection, parameters: [][]const u8) void;

const Message = struct {
    cmd: []const u8,
    parameters: [][]const u8, 
};

const cmd_map = CmdMap.initComptime(.{
    .{ "lobbyView", lobbyView },
    .{ "gameOptions", gameOptions },
    .{ "playerList", playerList },
});

pub fn handleMessage(allocator: Allocator, conn: *server.Connection, msg: []const u8) void {
    std.debug.print("Message Recieved: {s}\n", .{msg});

    var arena_wrapper = ArenaAllocator.init(allocator); 
    defer arena_wrapper.deinit();
    const arena = arena_wrapper.allocator();

    if (std.json.validate(arena, msg)) {
        const parsed = try std.json.parseFromSlice(Message, arena, msg, .{ 
            .ignore_unknown_fields = true 
        });
        defer parsed.deinit();
        
        const parsed_message = parsed.value;
        const cmd = parsed_message.cmd;
        const parameters = parsed_message.parameters;
        
        const action = cmd_map.get(cmd) orelse return CmdError.UnknownCmd;
        action(arena, conn, parameters);
    } else return CmdError.InvalidJson;
}

pub fn lobbyView(arena: Allocator, conn: *server.Connection, _: [][]const u8 ) void {
    _ = arena;
    _ = conn;   
}

pub fn gameOptions(arena: Allocator, conn: *server.Connection, _:[][]const u8) void {
    _ = arena;
    _ = conn;
}

pub fn playerList(arena: Allocator, conn: *server.Connection, _:[][]const u8) void {
    _ = arena;
    _ = conn;
}
