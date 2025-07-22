const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;


const core = @import("../core/core.zig");
const Agent = core.agent.Agent;
const Scope = core.scope.Scope;


const entities = @import("entities.zig");
const Member = entities.member.Member;


const config = @import("../config/config.zig");


pub const RoomError = error {
    AtMemberCapacity,
};


pub const Room = struct {
    allocator: Allocator,
    scope: Scope,
    members: Member.ArrayMap,

    const Self = @This();
    pub const Identifier = Scope.Identifier;
    pub const Map = AutoHashMapUnmanaged(Identifier, Room);

    pub fn init(allocator: Allocator, scope: Scope) !Self {
        var members = Member.ArrayMap{};
        try members.ensureTotalCapacity(allocator, config.server.room_member_limit);
        
        return Self{
            .allocator = allocator,
            .scope = scope,
            .members = members,
        };
    }

    pub fn deinit(self: *Self) void {
        self.members.deinit(self.allocator);
    }

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
