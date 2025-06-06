const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const conf = @import("config.zig");
const routes = @import("routes.zig");
const cmd = @import("command.zig");

const websocket = httpz.websocket;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList; 
const ArenaAllocator = std.heap.ArenaAllocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const Request = httpz.Request;
const Response = httpz.Response;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

pub const ConnectionError = error {
    RoomAtMemberCapacity,
    ServerAtMemberCapacity,
    ServerAtRoomCapacity,
    RoomNotFound, 
    MemberNotFound,
    FailedCreatingNewMember,
    FailedCreatingNewRoom,
    FailedConnectingMemberToRoom,
    MissingConnection,
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
    pub const WebsocketHandler = Connection;

    pub const Connection = struct {
        conn: ?*websocket.Conn = null,
        app: *Application,
        member_id: MemberId,
        room_id: RoomId,

        pub const Context = struct {
            app: *Application,
            member_id: MemberId,
        };

        pub fn init(conn: *websocket.Conn, ctx: *const Context) !Connection {
            const established_connection = ctx.app.connections.getPtr(ctx.member_id) orelse
                return ConnectionError.FailedConnectingMemberToRoom;
            if (established_connection.conn) |present_conn| try present_conn.close(.{});
            established_connection.conn = conn;
            
            return established_connection.*;
        }

        pub fn afterInit(self: *Connection) !void {
            self.printConnectionMessage();

            try cmd.onWebsocketConnect(self);    
        }

        pub fn clientMessage(self: *Connection, data: []const u8) !void {
            const allocator = self.app.allocator;
            var arena_wrapper = ArenaAllocator.init(allocator);
            defer arena_wrapper.deinit();

            const arena = arena_wrapper.allocator();
            try cmd.handleWebsocketMessage(arena, self, data);
        }

        pub fn close(self: *Connection) void {
            self.printDisconnectionMessage();
            self.app.disconnect(self.member_id);
        }

        pub fn printConnectionMessage(self: *const Connection) void {
            const member = self.app.members.get(self.member_id) orelse return;
            const room = self.app.rooms.get(self.room_id) orelse return;
            
            std.debug.print("[member : {s}] joined [room : {s}]\n", .{ member.name, room.name });
            std.debug.print("\t[{s} -> {s}]\n", .{
                uuid.urn.serialize(member.uid),
                uuid.urn.serialize(room.uid),
            });
        }

        pub fn printDisconnectionMessage(self: *const Connection) void {
            const member = self.app.members.get(self.member_id) orelse return;
            const room = self.app.rooms.get(self.room_id) orelse return;
        
            std.debug.print("[member : {s}] disconnected from [room : {s}]\n", .{ member.name, room.name });
            std.debug.print("\t[{s} X {s}]\n", .{
                uuid.urn.serialize(member.uid),
                uuid.urn.serialize(room.uid),
            });
        }
    };

    pub const Member = struct {
        uid: MemberId,
        name: []const u8,

        pub fn info(self: *const Member, allocator: Allocator) []const u8 {
            const info_fmt = "{s}\t[id : {s}]";
            return std.fmt.allocPrint(allocator, info_fmt, .{
                self.name,
                uuid.urn.serialize(self.uid),
            }) catch "???";
        }

        pub fn print(self: *const Member) void {
            var gpa = GeneralPurposeAllocator(.{}){};
            const allocator = gpa.allocator();

            const member_info = self.info(allocator);
            defer allocator.free(member_info);
            
            std.debug.print("{s}\n", .{member_info});
        }
    };

    pub const Room = struct {
        uid: RoomId,
        name: []const u8,
        member_buffer: []Member,
        member_list: *MemberList,

        const MemberList = std.ArrayListUnmanaged(Member);

        pub fn removeById(self: *Room, member_id: MemberId) void {
            for (self.member_list.items, 0..) |possible_match, index| {
                if (member_id == possible_match.uid) {
                    _ = self.member_list.swapRemove(index);
                    return;
                }
            }
        }

        pub fn info(self: *const Room, allocator: Allocator) []const u8 {
            const info_fmt = "{s}\t[id : {s}] ({d} members connected)";
            return std.fmt.allocPrint(allocator, info_fmt, .{
                self.name,
                uuid.urn.serialize(self.uid),
                self.member_list.items.len,
            }) catch "???";
        }

        pub fn print(self: *const Room) void {
            var gpa = GeneralPurposeAllocator(.{}){};
            const allocator = gpa.allocator();
            
            const room_info = self.info(allocator);
            defer allocator.free(room_info);
            
            std.debug.print("{s}\n", .{room_info});
        }

        pub fn printMembers(self: *const Room) void {
            self.print();
            for (self.member_list.items) |member| {
                std.debug.print("\t", .{});
                member.print();
            }
        }
    };


    pub fn init(allocator: Allocator) !Self {
        var self = Self{ 
            .allocator = allocator,
            .meta_data_arena = ArenaAllocator.init(allocator),
        };
        
        try self.rooms.ensureTotalCapacity(allocator, conf.num_rooms_capacity);
        try self.members.ensureTotalCapacity(allocator, conf.num_members_capacity);
        try self.connections.ensureTotalCapacity(allocator, conf.num_members_capacity);
        
        return self;
    }

    pub fn deinit(self: *Self) void {
        defer self.meta_data_arena.deinit();
        self.rooms.deinit(self.allocator);
        self.members.deinit(self.allocator);
        self.connections.deinit(self.allocator);
    }

    pub fn notFound(_: *Self, _: *Request, res: *Response) !void {
        res.status = 404;
        res.body = "Error: Not Found";
    }

    pub fn uncaughtError(_: *Self, _: *Request, res: *Response, err: anyerror) void {
        res.status = 505;
        
        const res_writer = res.writer();
        res_writer.print("Error: Internal Server Error\n{}", .{err}) catch {
            res.body = "Error: Internal Server Error\n???";
        };
    }

    pub fn newRoom(self: *Self, name: []const u8) !Room {
        if (self.rooms.count() >= conf.num_rooms_capacity)
            return ConnectionError.ServerAtRoomCapacity;

        const meta_data_allocator = self.meta_data_arena.allocator();

        const generated_uid = uuid.v7.new();
        const room_meta_data = .{
            .name = try meta_data_allocator.dupe(u8, name),
            .member_buffer = try meta_data_allocator.alloc(Member, conf.num_members_per_room_capacity),
            .member_list = try meta_data_allocator.create(Room.MemberList),
        };

        room_meta_data.member_list.* = Room.MemberList.initBuffer(room_meta_data.member_buffer);

        self.rooms.putAssumeCapacity(generated_uid, .{
            .uid = generated_uid,
            .name = room_meta_data.name,
            .member_buffer = room_meta_data.member_buffer,
            .member_list = room_meta_data.member_list,
        });
        
        const new_room = self.rooms.get(generated_uid) orelse {
            return ConnectionError.FailedCreatingNewRoom;
        };

        return new_room;
    }

    pub fn removeRoom(self: *Self, room_id: RoomId) void {
        const meta_data_allocator = self.meta_data_arena.allocator();
        const removed_room = self.rooms.fetchRemove(room_id) orelse return;
        meta_data_allocator.free(removed_room.value.name);
        meta_data_allocator.free(removed_room.value.member_buffer);
        meta_data_allocator.destroy(removed_room.value.member_list);
    }

    pub fn newMember(self: *Self, name: []const u8) !Member {
        if (self.members.count() >= conf.num_members_capacity)
            return ConnectionError.ServerAtMemberCapacity;

        const meta_data_allocator = self.meta_data_arena.allocator();

        const generated_uid = uuid.v7.new();
        const member_meta_data = .{
            .name = try meta_data_allocator.dupe(u8, name),
        };

        self.members.putAssumeCapacity(generated_uid, .{
            .uid = generated_uid,
            .name = member_meta_data.name,
        });

        const new_member = self.members.get(generated_uid) orelse {
            return ConnectionError.FailedCreatingNewMember;
        };

        return new_member; 
    }

    pub fn removeMember(self: *Self, member_id: MemberId) void {
        const meta_data_allocator = self.meta_data_arena.allocator();
        const removed_member = self.members.fetchRemove(member_id) orelse return ;
        meta_data_allocator.free(removed_member.value.name);
    }

    pub fn connect(self: *Self, member_id: MemberId, room_id: RoomId) !Connection {
        const room_to_connect = self.rooms.get(room_id) orelse 
            return ConnectionError.RoomNotFound;
        const member_to_connect = self.members.get(member_id) orelse
            return ConnectionError.MemberNotFound;

        if (room_to_connect.member_list.items.len < conf.num_members_per_room_capacity) {
            room_to_connect.member_list.appendAssumeCapacity(member_to_connect);
        } else return ConnectionError.RoomAtMemberCapacity;
        
        self.connections.putAssumeCapacity(member_id, .{
            .app = self,
            .room_id = room_id,
            .member_id = member_id,
        });

        const new_connection = self.connections.get(member_id) orelse {
            return ConnectionError.FailedConnectingMemberToRoom;
        };
        
        return new_connection;
    }

    pub fn joinRoom(self: *Self, member_name: []const u8, room_id: RoomId) !Connection {
        const room_to_join = self.rooms.getPtr(room_id) orelse
            return ConnectionError.RoomNotFound;
        if (room_to_join.member_list.items.len >= conf.num_members_per_room_capacity)
            return ConnectionError.RoomAtMemberCapacity;
        
        const new_member = try self.newMember(member_name);

        return try self.connect(new_member.uid, room_id);
    }

    pub fn createRoom(self: *Self, room_name: []const u8, host_name: []const u8) !Connection {
        const new_member = try self.newMember(host_name);
        const new_room = self.newRoom(room_name) catch |err| {
            self.removeMember(new_member.uid);
            return err;
        };

        return self.connect(new_member.uid, new_room.uid) catch |err| {
            self.removeMember(new_member.uid);
            self.removeRoom(new_room.uid);
            return err;
        };
    }

    pub fn disconnect(self: *Self, member_id: MemberId) void {
        const connection = (self.connections.fetchRemove(member_id) orelse return).value;
        const room = self.rooms.getPtr(connection.room_id) orelse return;

        room.removeById(member_id);

        self.removeMember(connection.member_id);       
        if (room.member_list.items.len == 0) {
            self.removeRoom(connection.room_id);
        }
    }

    pub fn printMembers(self: *Self, prefix: []const u8) void {
        var member_it = self.members.valueIterator();
        while (member_it.next()) |member| {
            std.debug.print("{s}", .{prefix});
            member.print();
        }
    }

    pub fn printRooms(self: *Self, prefix: []const u8) void {
        var room_it = self.rooms.valueIterator();
        while (room_it.next()) |room| {
            std.debug.print("{s}", .{prefix});
            room.print();
        }
    }

    pub fn printConnections(self: *Self, prefix: []const u8) void {
        var connection_it = self.connections.valueIterator();
        while (connection_it.next()) |connection| {
            std.debug.print("{s}", .{prefix});
            std.debug.print("{s} -> {s}\n", .{
                uuid.urn.serialize(connection.member_id),
                uuid.urn.serialize(connection.room_id),
            });
        }
    }
};


pub fn start() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    const server_allocator = gpa.allocator();

    var app = try Application.init(server_allocator);
    
    var server = try httpz.Server(*Application).init(server_allocator, .{
        .port = conf.port,
        .request = .{ 
            .max_form_count = 20,
        },
    }, &app);
    defer server.deinit();
    defer server.stop();
    
    var router = try server.router(.{});
    for (routes.map.get.keys(), routes.map.get.values()) |path, action| 
        router.get(path, action, .{});
    for (routes.map.post.keys(), routes.map.post.values()) |path, action| 
        router.post(path, action, .{}); 

    try createDummyRooms(&app);

    try server.listen();
}

fn createDummyRooms(app: *Application) !void {
    _ = try app.newRoom("PeggyRoom");
    _ = try app.newRoom("KittyRoom");
}

fn printTestTitle(name: []const u8, index: usize) void {
    std.debug.print("\n\nTest {d} - {s} -----------------------\n", .{ index, name });
}

test "Create App Instance" {
    printTestTitle("Create App Instance", 1);
    
    const allocator = std.testing.allocator;
    var app = try Application.init(allocator);
    defer app.deinit();
}

test "Create New Member" {
    printTestTitle("Create New Member", 2);

    const allocator = std.testing.allocator;
    var app = try Application.init(allocator);
    defer app.deinit();
    
    const new_member = try app.newMember("Gabe");
    new_member.print();
}

test "Create New Room" {
    printTestTitle("Create New Room", 3);

    const allocator = std.testing.allocator;
    var app = try Application.init(allocator);
    defer app.deinit();
    
    const new_room = try app.newRoom("Gabe's Room");
    new_room.print();
}

test "Member Creates a Room" {
    printTestTitle("Member Creates a Room", 4);

    const allocator = std.testing.allocator;
    var app = try Application.init(allocator);
    defer app.deinit();

    _ = try app.createRoom("Gabe", "Gabe's Room");
    std.debug.print("Connections: \n", .{});
    app.printConnections("\t");
}

test "Member Joins a Created Room" {
    printTestTitle("Member Joins a Created Room", 5);

    const allocator = std.testing.allocator;
    var app = try Application.init(allocator);
    defer app.deinit();
    
    const new_room_connection = try app.createRoom("Gabe", "Gabe's Room");
    var new_room = app.rooms.get(new_room_connection.room_id).?;

    std.debug.print("New Room Created: ", .{});
    new_room.print();

    _ = try app.joinRoom("Kade", new_room.uid);
    _ = try app.joinRoom("Michael", new_room.uid);
    _ = try app.joinRoom("Daniel", new_room.uid);
    _ = try app.joinRoom("Sara", new_room.uid);

    std.debug.print("Rooms: \n", .{});
    app.printRooms("\t");
    
    std.debug.print("Members: \n", .{});
    app.printMembers("\t");

    std.debug.print("Connections: \n", .{});
    app.printConnections("\t");
}

test "Members Disconnect From A Room" {
    printTestTitle("Members Disconnect From A Room", 6);

    const allocator = std.testing.allocator;
    var app = try Application.init(allocator);
    defer app.deinit();
    
    const new_room_connection = try app.createRoom("Gabe", "Gabe's Room");
    var new_room = app.rooms.get(new_room_connection.room_id).?;

    std.debug.print("New Room Created: ", .{});
    new_room.print();

    var connected: [4]*Application.Connection = undefined;
    connected[0] = try app.joinRoom("Kade", new_room.uid);
    connected[1] = try app.joinRoom("Michael", new_room.uid);
    connected[2] = try app.joinRoom("Daniel", new_room.uid);
    connected[3] = try app.joinRoom("Sara", new_room.uid);

    std.debug.print("Rooms: \n", .{});
    app.printRooms("\t");
    
    std.debug.print("Members: \n", .{});
    app.printMembers("\t");

    std.debug.print("Connections: \n", .{});
    app.printConnections("\t");

    try app.disconnect(connected[0].member_id);
    try app.disconnect(connected[3].member_id);
    
    std.debug.print("After Disconnections\n", .{});
    std.debug.print("\tRooms\n", .{});
    app.printRooms("\t\t");
    std.debug.print("\tConnections\n", .{});
    app.printConnections("\t\t");
    std.debug.print("\tMembers\n", .{});
    app.printMembers("\t\t");
}
