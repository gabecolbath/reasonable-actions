const std = @import("std");
const server = @import("server.zig");
const json = std.json;

const Allocator = std.mem.Allocator;


const Exec = *const fn (Data: type, data: *const anyopaque) anyerror!Data;


const Command = struct {
    name: []const u8,
};

