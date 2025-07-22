const std = @import("std");
const Allocator = std.mem.Allocator;
const StaticStringMap = std.StaticStringMap;


const network = @import("../network/network.zig");


pub const RouteMap = StaticStringMap(network.httpz.Action(void)); 


pub const Mapped = struct {
    get: RouteMap,
    post: RouteMap,
};


pub const mapped = Mapped{
    .get = .initComptime(.{

    }),
    .post = .initComptime(.{

    }),
};
