const std = @import("std");
const uuid = @import("uuid");

const server = @import("server.zig");
const print = std.debug.print;

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}){};
    defer _ = dba.deinit();

    var app = try server.App.init(dba.allocator());
    defer app.deinit();

    var host = try server.start(dba.allocator(), &app);
    defer host.deinit();
}
