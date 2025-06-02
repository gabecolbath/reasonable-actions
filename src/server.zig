const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const conf = @import("config.zig");

const websocket = httpz.websocket;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

const ConnectionError = error {
    RoomAtMemberCapacity,
    ServerAtMemberCapacity,
    ServerAtRoomCapacity,
    RoomNotFound, 
    MemberNotFound,
};

pub const Application = struct {
    allocator: Allocator,
    meta_data_arena: ArenaAllocator,
    rooms: RoomMap = RoomMap.empty,
    members: MemberMap = MemberMap.empty,
    connections: ConnectionMap = ConnectionMap.empty,

    const Self = @This();
    const RoomMap = std.AutoHashMapUnmanaged(RoomId, Room);
    const MemberMap = std.AutoHashMapUnmanaged(MemberId, Member);
    const ConnectionMap = std.AutoHashMapUnmanaged(MemberId, Application.Connection);
    const MemberId = Uuid;
    const RoomId = Uuid;

    const Connection = struct {
        conn: *websocket.Conn,
        app: *Application,
        member_id: MemberId,
        room_id: RoomId,
    };

    pub const Member = struct {
        uid: MemberId,
        name: []const u8,
    };

    pub const Room = struct {
        uid: RoomId,
        name: []const u8,
        member_buffer: []Member,
        member_list: MemberList,

        const MemberList = std.ArrayListUnmanaged(Member);
    };


    pub fn init(allocator: Allocator) !Self {
        const self = &Self{ 
            .allocator = allocator,
            .meta_data_arena = ArenaAllocator.init(allocator),
        };
        
        try self.rooms.ensureTotalCapacity(allocator, conf.num_rooms_capacity);
        try self.members.ensureTotalCapacity(allocator, conf.num_members_capacity);
        try self.connections.ensureTotalCapacity(allocator, conf.num_members_capacity);
        
        return self.*;
    }

    pub fn deinit(self: *Self) void {
        self.rooms.deinit(self.allocator);
        self.members.deinit(self.allocator);
    }

    pub fn newRoom(self: *Self, name: []const u8) !*Room {
        if (self.rooms.count() >= conf.num_rooms_capacity)
            return ConnectionError.ServerAtRoomCapacity;

        const meta_data_allocator = self.meta_data_arena.allocator();

        const generated_uid = uuid.v7.new();
        const room_meta_data = .{
            .name = try meta_data_allocator.dupe(name),
            .member_buffer = try meta_data_allocator.alloc(Member, conf.num_members_per_room_capacity),
        };

        const result = self.rooms.getOrPutAssumeCapacity(generated_uid);
        result.value_ptr.* = .{
            .name = room_meta_data.name,
            .member_buffer = room_meta_data.member_buffer,
            .member_list = Room.MemberList.initBuffer(room_meta_data.member_buffer),
            .uid = generated_uid,
        };

        return result.value_ptr;
    }

    pub fn newMember(self: *Self, name: []const u8) !*Member {
        if (self.members.count() >= conf.num_members_capacity)
            return ConnectionError.ServerAtMemberCapacity;

        const meta_data_allocator = self.meta_data_arena.allocator();

        const generated_uid = uuid.v7.new();
        const member_meta_data = .{
            .name = try meta_data_allocator.dupe(name),
        };

        const result = self.members.getOrPutAssumeCapacity(generated_uid);
        result.value_ptr.* = .{
            .name = member_meta_data.name,
            .uid = generated_uid,
        };

        return result.value_ptr; 
    }

    pub fn joinRoom(self: *Self, conn: *websocket.Conn, member_name: []const u8, room_id: RoomId) !*Connection {
        const room_to_join = self.rooms.getPtr(room_id) orelse
            ConnectionError.RoomNotFound;
        if (room_to_join.member_list.items.len >= conf.num_members_per_room_capacity)
            ConnectionError.RoomAtMemberCapacity;
        
        const new_member = try self.newMember(member_name);
        room_to_join.member_list.appendAssumeCapacity(new_member.*);

        const result = self.connections.getOrPutAssumeCapacity(new_member.uid);
        result.value_ptr.* = .{
            .conn = conn,
            .app = self,
            .member_id = new_member.uid,
            .room_id = room_id,
        };

        return result;
    }

    pub fn createRoom(self: *Self, conn: *websocket.Conn, host_name: []const u8, room_name: []const u8) !*Connection {
        const new_room = try self.newRoom(room_name);
        const new_member = try self.newMember(host_name);
        new_room.member_list.appendAssumeCapacity(new_member.*);

        const result = self.connections.getOrPutAssumeCapacity(new_member.uid);
        result.value_ptr.* = .{
            .conn = conn,
            .app = self,
            .member_id = new_member.uid,
            .room_id = new_room.uid,
        };

        return result;
    }
};


pub fn start() !void {
    
}
