const std = @import("std");
const server = @import("server.zig");

const json = std.json;

pub const ParseError = error {
    InvalidJson, 
    MissingCommand,
};

pub const ExecError = error {
    UnknownCommand,
};

pub const CommandMap = std.StaticStringMap(Action);
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const ParameterMap = std.StringArrayHashMapUnmanaged([]const u8);
const Client = server.Client;

pub const Action = *const fn (allocator: Allocator, cmd: Command) anyerror!void;

pub const Command = struct {
    name: []const u8,
    params: ParameterMap,
    source: *Client,
    data: ?[]const u8 = null,
};

pub const Handler = struct {
    map: CommandMap = CommandMap{},

    const Self = @This();

    const ParsedCommand = struct {
        cmd: ?[]const u8 = null,
        params: ?[]ParsedParameter = null,
    };

    const ParsedParameter = struct {
        param: []const u8,
        value: []const u8,
    };

    const ResponseOption = enum {
        member,
        room_all,
        room_exc,
    };

    pub fn parseCommand(_: *Self, allocator: Allocator, msg: []const u8, source: *Client) !Command {
        if (try json.validate(allocator, msg)) {
            const parsed = try json.parseFromSlice(ParsedCommand, allocator, msg, .{.ignore_unknown_fields = true});
            const parsed_cmd = parsed.value.cmd orelse return ParseError.MissingCommand;
            const parsed_params = map_params: {
                if (parsed.value.params) |params| {
                    var map = ParameterMap{};
                    for (params) |p| {
                        try map.put(allocator, p.param, p.value);
                    } else break :map_params map;
                } else break :map_params ParameterMap{};
            };

            return Command{
                .name = parsed_cmd,
                .params = parsed_params,
                .source = source,
                .data = msg,
            };
        } else return ParseError.InvalidJson;
    }

    pub fn parseFormData(_: *Self, ParseType: type, allocator: Allocator, msg: []const u8) !ParseType {
        if (try json.validate(allocator, msg)) {
            const parsed = try json.parseFromSlice(ParseType, allocator, msg, .{}); 
            return parsed.value;
        } else return ParseError.InvalidJson;
    }

    pub fn respond(opt: ResponseOption, client: *Client, res: []const u8) !void {
        switch (opt) {
            .member => {
                if (client.member.conn) |conn| {
                    try conn.write(res);
                } else return server.ServerError.MemberNotConnected;
            },
            .room_all => {
                for (client.room.member_list) |member_id| {
                    const member = client.app.members.get(member_id) orelse continue;
                    const est_client= server.Client.initAssumeEstablished(client.app, member, client.room);
                    respond(.member, &est_client, res) catch continue;
                }
            },
            .room_exc => {
                const exclude_id = client.member.uid;
                for (client.room.member_list) |member_id| {
                    if (member_id == exclude_id) continue;
                    const member = client.app.members.get(member_id) orelse continue;
                    const est_client= server.Client.initAssumeEstablished(client.app, member, client.room);
                    respond(.member, &est_client, res) catch continue;
                }
            }
        }
    }

    pub fn exec(self: *Self, allocator: Allocator, cmd: Command) !void {
        const action = self.map.get(cmd.name) orelse return ExecError.UnknownCommand;
        try action(allocator, cmd);
    }
};

pub fn asJson(allocator: Allocator, cmd: []const u8, params: anytype) ![]const u8 {
    var output = ArrayList(u8).init(allocator);
    std.json.stringify(.{
        .cmd = cmd,
        .params = params,
    }, .{}, output.writer());
    
    return try output.toOwnedSlice();
}
