const std = @import("std");
const json = std.json;
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;


pub const CommandError = error {
    UnknownCommand,
};


const server = @import("server.zig");
const cli = @import("client.zig");

const Client = cli.Client;
pub const CommandMap = std.StaticStringMap(Command);

pub const Command = struct {
    ptr: *anyopaque,
    v_table: VTable,
    msg: []const u8,

    const Self = @This();

    const VTable = struct {
        exec: *const fn (self: *anyopaque, allocator: Allocator, client: *Client) anyerror!void,
    };

    pub fn init(cmd: anytype, msg: []const u8) Self {
        const Ptr = @TypeOf(cmd);
        assert(@typeInfo(Ptr) == .pointer);
        assert(@typeInfo(Ptr).pointer.size == .one);
        assert(@typeInfo(@typeInfo(Ptr).pointer.child) == .@"struct");
        
        const impl = struct {
            fn exec(ptr: *anyopaque, allocator: Allocator, client: *Client) !void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                try self.exec(allocator, client);
            }
        };
            
        return Self{
            .ptr = cmd,
            .v_table = .{
                .exec = impl.exec,
            },
            .msg = msg,
        };
    }

    pub fn exec(self: *Self, allocator: Allocator, client: *Client) !void {
        try self.v_table.exec(self, allocator, client);
    }
};
