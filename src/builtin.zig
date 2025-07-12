const std = @import("std");

const Allocator = std.mem.Allocator;


const server = @import("server.zig");
const cli = @import("client.zig");
const comm = @import("command.zig"); 

const Client = cli.Client;
const Command = comm.Command;
const CommandMap = comm.CommandMap;


pub const commands = CommandMap.initComptime(.{});
