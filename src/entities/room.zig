const std = @import("std");
const Allocator = std.mem.Allocator;


const entities = @import("entities.zig");
const Member = entities.member.Member;


pub const Room = struct {
    members: []Member,
};
