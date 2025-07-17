const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoArrayHashMapUnmanaged;


const core = @import("../core/core.zig");
const Space = core.space.Space;


const entities = @import("entities.zig");
const Member = entities.member.Member;


pub const Room = struct {
    space: Space,
    members: Member.List,

    const Self = @This();
    pub const Identifier = Space.Identifier;
    pub const Map = AutoHashMapUnmanaged(Identifier, Self);
};
