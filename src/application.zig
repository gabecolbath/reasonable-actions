const std = @import("std");
const Allocator = std.mem.Allocator;


const core = @import("core/core.zig");
const Server = core.server.Server;
const Engine = core.engine.Engine;


pub const App = struct {
    allocator: Allocator,
    server: Server, 
    engine: Engine,
};
