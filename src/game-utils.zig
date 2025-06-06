const std = @import("std");
const mustache = @import("mustache");
const game = @import("game.zig");

const Allocator = std.mem.Allocator;
const Html = []const u8;
