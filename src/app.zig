const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const conf = @import("config.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;
const Request = httpz.Request;
const Response = httpz.Response;
const Uuid = uuid.Uuid;

const MemberError = error {
    MemberNotFound,
    AtMemberCapacity,
};

const RoomError = error {
    RoomNotFound,
    AtRoomCapacity,
    AtMemberRoomCapcity,
};

pub const Member = struct {
    conn: *httpz.websocket.Conn,
    app_data: *Instance,
    room_id: ?Uuid,
    id: Uuid,
    name: []const u8,

    const Self = @This(); 

    fn changeName(self: *Self, new_name: []const u8) !void {
        self.app_data.allocator.free(self.name); 
        self.name = try self.app_data.allocator.dupe(new_name);
    }
};

pub const Room = struct {
    app_data: *Instance,
    id: Uuid,
    name: []const u8,
    members: HashMap(Uuid, *Member),

    const Self = @This(); 

    fn changeName(self: *Self, new_name: []const u8) !void {
        self.app_data.allocator.free(self.name);
        self.name = try self.app_data.allocator.dupe(u8, new_name);
    }

    fn join(self: *Self, member: *Member) !void {
        if (self.members.count() < conf.max_members_per_room) {
            try self.members.put(member.id, member);       
        } else {
            return RoomError.AtMemberRoomCapcity;
        }
    }

    fn kick(self: *Self, member: *Member) ?*Member {
        if (self.members.fetchRemove(member.id)) |removed| {
            return removed.value;
        } else {
            return null;
        }
    }
};

pub const Instance = struct {
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
            .members = HashMap(Member).init(allocator),
            .rooms = HashMap(Room).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.rooms.deinit();
        defer self.members.deinit();

        var room_it = self.rooms.valueIterator();
        while (room_it.next()) |room| {
            self.allocator.free(room.name);
            room.members.deinit();
        }

        var member_it = self.members.valueIterator();
        while (member_it.next()) |member| {
            self.allocator.free(member.name);
        }
    }

    pub fn join(self: *Self, conn: *httpz.websocket.Conn, member_name: []const u8, room_id: Uuid) !JoinResult {
        const room_to_join = self.rooms.getPtr(room_id) orelse {
            return RoomError.RoomNotFound;
        };

        const saved_member_name = try self.allocator.dupe(member_name);
        errdefer self.allocator.free(saved_member_name);

        const joined_member = check_capacity: {
            if (self.members.count() < conf.max_total_members) {
                const generated_member_id = uuid.v7.new();
                const new_member_entry = try self.members.getOrPut(generated_member_id);
                const new_member = new_member_entry.value_ptr;
                new_member.* = Member{
                    .conn = conn,
                    .app_data = self,
                    .room_id = room_id,
                    .id = generated_member_id,
                    .name = saved_member_name,
                };

                break :check_capacity new_member;
            } else return MemberError.AtMemberCapacity;
        };
        errdefer _ = self.members.remove(joined_member.id);

        try room_to_join.join(joined_member);

        return JoinResult{
            .room = room_to_join,
            .member = joined_member,
        };
    }

    pub fn create(self: *Self, conn: *httpz.websocket.Conn, room_name: []const u8, creator_name: []const u8) !JoinResult {
    }
};
