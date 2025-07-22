const std = @import("std");


const network = @import("network/network.zig");


const application = @import("application.zig");
const App = application.App;


const route = @import("route/route.zig");


const core = @import("core/core.zig");
const Server = core.server.Server;
const Engine = core.engine.Engine;


const config = @import("config/config.zig");


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = App{
        .allocator = allocator,
        .server = undefined,
        .engine = undefined,
    };

    app.server = try Server.init(&app);
    app.engine = try Engine.init(&app);

    var server = try network.httpz.Server(*App).init(allocator, .{ .port = config.port });
    var router = try server.router(.{});

    var routes = route.mapped;
    for (routes.get.keys()) |path| {
        router.get(path, routes.get.get(path) orelse continue, .{});
    }
    for (routes.post.keys()) |path| {
        router.post(path, routes.post.get(path) orelse continue, .{});
    }

    try server.listen();
}
