const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const conf = @import("config.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const HashMap = std.AutoHashMap;
const Request = httpz.Request;
const Response = httpz.Response;
const Uuid = uuid.Uuid;

pub const MemberError = error {
    MemberNotFound,
    AtMemberCapacity,
};

pub const RoomError = error {
    RoomNotFound,
    AtRoomCapacity,
    AtMemberRoomCapcity,
    MemberAttemptedToJoinMoreThanOnce,
    
};

pub const Member = struct {
    app_data: *Data,
    room_id: Uuid,
    id: Uuid,
    name: []const u8,

    const Self = @This(); 

    pub fn changeName(self: *Self, new_name: []const u8) !void {
        self.app_data.allocator.free(self.name); 
        self.name = try self.app_data.allocator.dupe(new_name);
    }

    pub fn print(self: *const Self) void {
        std.debug.print("{s}\t[id : {s}] [room : {s}]\n", .{
            self.name,
            uuid.urn.serialize(self.id),
            uuid.urn.serialize(self.room_id),
        });
    }

    pub fn info(self: *const Self, allocator: Allocator) ![]const u8 {
        var str = ArrayList(u8).init(allocator);
        const writer = str.writer();
        
        try writer.print("{s}\t[id : {s}] [room : {s}]\n", .{
            self.name,
            uuid.urn.serialize(self.id),
            uuid.urn.serialize(self.room_id),
        });

        return try str.toOwnedSlice();
    }
};

pub const Room = struct {
    app_data: *Data,
    id: Uuid,
    name: []const u8,
    member_ids: ArrayListUnmanaged(Uuid),

    const Self = @This(); 

    pub fn changeName(self: *Self, new_name: []const u8) !void {
        self.app_data.allocator.free(self.name);
        self.name = try self.app_data.allocator.dupe(u8, new_name);
    }

    pub fn join(self: *Self, member_id: Uuid) !void {
        if (self.member_ids.items.len < conf.max_members_per_room) {
            for (self.member_ids.items) |possible_duplicate_id| {
                if (member_id == possible_duplicate_id) {
                    return RoomError.MemberAttemptedToJoinMoreThanOnce;
                }
            } else {
                self.member_ids.appendAssumeCapacity(member_id);
            }
        } else {
            return RoomError.AtMemberRoomCapcity;
        }
    }

    pub fn kick(self: *Self, member_id: Uuid) !void {
        for (self.member_ids.items, 0..) |possible_match, index| {
            if (member_id == possible_match) {
                _ = self.member_ids.swapRemove(index);
                return;
            }
        } else {
            return MemberError.MemberNotFound;
        }
    }

    pub fn print(self: *const Self) void {
        std.debug.print("{s}\t[id : {s}]\n", .{
            self.name,
            uuid.urn.serialize(self.id),
        });

        for (self.member_ids.items) |id| {
            const urn = uuid.urn.serialize(id);
            const member = self.app_data.members.get(id) orelse {
                std.debug.print("\t??? [id : {s}]\n", .{urn});
                continue;
            };

            std.debug.print("\t", .{});
            member.print();
        }
    }

    pub fn info(self: *const Self, allocator: Allocator) ![]const u8 {
        var str = ArrayList(u8).init(allocator);
        const writer = str.writer();
        
        try writer.print("{s}\t[id : {s}]\n", .{
            self.name,
            uuid.urn.serialize(self.id),
        });

        return try str.toOwnedSlice();
    }
};

pub const Data = struct {
    allocator: Allocator,
    members: HashMap(Uuid, Member),
    rooms: HashMap(Uuid, Room),

    const Self = @This();
    const JoinResult = struct {
        room: *Room,
        member: *Member,
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .members = HashMap(Uuid, Member).init(allocator),
            .rooms = HashMap(Uuid, Room).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.rooms.deinit();
        defer self.members.deinit();

        var room_it = self.rooms.valueIterator();
        while (room_it.next()) |room| {
            self.allocator.free(room.name);
            room.member_ids.deinit(self.allocator);
        }

        var member_it = self.members.valueIterator();
        while (member_it.next()) |member| {
            self.allocator.free(member.name);
        }
    }

    fn findMemberIdByName(self: *Self, query: struct { name: []const u8, room_id: ?Uuid }) !Uuid {
        if (query.room_id) |resolved_room_id| {
            const room = self.rooms.get(resolved_room_id) orelse {
                return RoomError.RoomNotFound;
            };
            
            for (room.member_ids.items) |member_id| {
                const member = self.members.get(member_id) orelse continue;
                if (std.mem.eql(u8, member.name, query.name)) {
                    return member_id;
                }
            } else {
                return MemberError.MemberNotFound;
            }
        } else {
            var member_it = self.members.valueIterator();
            while (member_it.next()) |member| {
                if (std.mem.eql(u8, member.name, query.name)) {
                    return member.id;
                }
            } else {
                return MemberError.MemberNotFound;
            }
        }
    }
};

pub const Control = struct {
    app_data: *Data,

    const Self = @This();
    const JoinResult = struct {
        room_id: Uuid,
        member_id: Uuid,
    };

    pub fn joinRoom(self: *const Self, member_name: []const u8, room_id: Uuid) !JoinResult {
        const room_to_join = self.app_data.rooms.getPtr(room_id) orelse {
            return RoomError.RoomNotFound;
        };

        const saved_member_name = try self.app_data.allocator.dupe(u8, member_name);
        errdefer self.app_data.allocator.free(saved_member_name);

        const joined_member = check_capacity: {
            if (self.app_data.members.count() < conf.max_total_members) {
                const generated_member_id = uuid.v7.new();
                const new_member_entry = try self.app_data.members.getOrPut(generated_member_id);
                const new_member = new_member_entry.value_ptr;
                new_member.* = Member{
                    .app_data = self.app_data,
                    .room_id = room_id,
                    .id = generated_member_id,
                    .name = saved_member_name,
                };

                break :check_capacity new_member;
            } else return MemberError.AtMemberCapacity;
        };
        errdefer _ = self.app_data.members.remove(joined_member.id);

        try room_to_join.join(joined_member.id);
        
        return JoinResult{
            .room_id = room_id,
            .member_id = joined_member.id,
        };
    }

    pub fn createRoom(self: *const Self, room_name: []const u8, creator_name: []const u8) !JoinResult {
        const saved_room_name = try self.app_data.allocator.dupe(u8, room_name);
        errdefer self.app_data.allocator.free(saved_room_name);
        
        const created_room = check_capacity: {
            if (self.app_data.rooms.count() < conf.max_total_rooms) {
                const generated_room_id = uuid.v7.new();
                const new_room_entry = try self.app_data.rooms.getOrPut(generated_room_id);
                const new_room = new_room_entry.value_ptr;
                new_room.* = Room{
                    .app_data = self.app_data,
                    .id = generated_room_id,
                    .name = saved_room_name,
                    .member_ids = try ArrayListUnmanaged(Uuid)
                        .initCapacity(self.app_data.allocator, conf.max_members_per_room),
                };

                break :check_capacity new_room;
            } else return RoomError.AtRoomCapacity;
        };
        errdefer created_room.member_ids.deinit(self.app_data.allocator);
        errdefer _ = self.app_data.rooms.remove(created_room.id);

        return try self.joinRoom(creator_name, created_room.id);
    }

    pub fn closeRoom(self: *const Self, room_id: Uuid) !void {
        const room_to_close = self.app_data.rooms.getPtr(room_id) orelse {
            return RoomError.RoomNotFound;
        };
        room_to_close.member_ids.deinit(self.app_data.allocator);
        self.app_data.allocator.free(room_to_close.name);
        
        _ = self.app_data.rooms.remove(room_id);
    }

    pub fn leaveRoom(self: *const Self, room_id: Uuid, member_id: Uuid) !void {
        const room = self.app_data.rooms.getPtr(room_id) orelse {
            return RoomError.RoomNotFound;
        };
        
        try room.kick(member_id);
        
        const member = self.app_data.members.getPtr(member_id) orelse {
            return MemberError.MemberNotFound;
        };
        self.app_data.allocator.free(member.name);
        _ = self.app_data.members.remove(member_id);
    }
};

test "Create A Room" {
    std.debug.print("Test 1 - Create a Room ------------------------------------\n", .{});
    defer std.debug.print("\n", .{});

    var app_data = Data.init(std.testing.allocator);
    const app_control = Control{ .app_data = &app_data };
    defer app_data.deinit();

    const new_room_id = try app_control.createRoom("Test Room", "Gabe");
    try app_control.joinRoom("Michael", new_room_id);
    try app_control.joinRoom("Kade", new_room_id);
    try app_control.joinRoom("Daniel", new_room_id);
    try app_control.joinRoom("Reese", new_room_id);
    try app_control.joinRoom("Bobby", new_room_id);
    try app_control.joinRoom("Sara", new_room_id);

    const room = app_data.rooms.get(new_room_id).?;
    room.print();
}

test "Kick Players From a Room" {
    std.debug.print("Test 2 - Kick Players From a Room -------------------------\n", .{});
    defer std.debug.print("\n", .{});

    var app_data = Data.init(std.testing.allocator);
    const app_control = Control{ .app_data = &app_data };
    defer app_data.deinit();
    
    const new_room_id = try app_control.createRoom("Test Room", "Gabe");
    try app_control.joinRoom("Michael", new_room_id);
    try app_control.joinRoom("Kade", new_room_id);
    try app_control.joinRoom("Daniel", new_room_id);
    try app_control.joinRoom("Reese", new_room_id);
    try app_control.joinRoom("Bobby", new_room_id);
    try app_control.joinRoom("Sara", new_room_id);

    const room = app_data.rooms.getPtr(new_room_id).?;
    room.print();

    const member_to_kick_id = try app_data.findMemberIdByName(.{
        .name = "Kade",
        .room_id = room.id,
    });
    try room.kick(member_to_kick_id);

    std.debug.print("After Kick:\n", .{});
    room.print();
}

test "Close An Open Room" {
    std.debug.print("Test 3 - Close An Open Room -------------------------------\n", .{});
    defer std.debug.print("\n", .{});

    var app_data = Data.init(std.testing.allocator);
    const app_control = Control{ .app_data = &app_data };
    defer app_data.deinit();

    const new_room_id = try app_control.createRoom("Test Room", "Gabe");
    try app_control.joinRoom("Michael", new_room_id);
    try app_control.joinRoom("Kade", new_room_id);
    try app_control.joinRoom("Daniel", new_room_id);
    try app_control.joinRoom("Reese", new_room_id);
    try app_control.joinRoom("Bobby", new_room_id);
    try app_control.joinRoom("Sara", new_room_id);

    const room = app_data.rooms.get(new_room_id).?;
    room.print();

    try app_control.closeRoom(new_room_id);
    
    const deleted_room = app_data.rooms.get(new_room_id);
    try std.testing.expectEqual(null, deleted_room);
}

test "Create Multiple Rooms" {
    std.debug.print("Test 3 - Create Multiple Rooms ----------------------------\n", .{});
    defer std.debug.print("\n", .{});

    var app_data = Data.init(std.testing.allocator);
    const app_control = Control{ .app_data = &app_data };
    defer app_data.deinit();

    const new_room_id_1 = try app_control.createRoom("Gabe Room", "Gabe");
    const new_room_id_2 = try app_control.createRoom("Sara Room", "Sara");
    
    const new_room_1 = app_data.rooms.get(new_room_id_1).?;
    const new_room_2 = app_data.rooms.get(new_room_id_2).?;

    new_room_1.print();
    new_room_2.print();
}
