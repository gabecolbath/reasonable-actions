const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoArrayHashMapUnmanaged;


const core = @import("../core/core.zig");
const Space = core.space.Space;


const entities = @import("entities.zig");
const Member = entities.member.Member;


pub const Room = struct {
    allocator: Allocator,
    space: Space,
    members: Member.ArrayMap,

    const Self = @This();
    pub const Identifier = Space.Identifier;
    pub const Map = AutoHashMapUnmanaged(Identifier, Self);

    pub fn kickMember(self: *Self, uuid: Member.Identifier) void {
        const member = self.members.get(uuid) orelse return;
        member.kick();
    }

    pub fn kickAll(self: *Self) void {
        for (self.members.values()) |member| {
            member.kick();
        }
    }
};
