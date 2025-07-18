const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;


const core = @import("../core/core.zig");
const Scope = core.scope.Scope;


const entities = @import("entities.zig");
const Member = entities.member.Member;


pub const Room = struct {
    allocator: Allocator,
    scope: Scope,
    members: Member.ArrayMap,

    const Self = @This();
    pub const Identifier = Scope.Identifier;
    pub const Map = AutoHashMapUnmanaged(Identifier, Room);

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
