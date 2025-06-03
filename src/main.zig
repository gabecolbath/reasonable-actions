const std = @import("std");
const server = @import("server.zig");

pub fn main() !void {
    try server.start();
}

