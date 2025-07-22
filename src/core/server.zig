const std = @import("std");
const Allocator = std.mem.Allocator;


const application = @import("../application.zig");
const App = application.App; 


const config = @import("../config/config.zig");


const entities = @import("../entities/entities.zig");
const Room = entities.room.Room;
const Member = entities.member.Member;


pub const ServerError = error {
    RoomNotFound,
    MemberNotFound,
    EmptyRoom, 
    AtRoomCapacity,
    AtMemberCapacity,
};


pub const Server = struct { 
    app: *App,
    rooms: Room.Map, 
    members: Member.Map, 

    const Self = @This(); 

    pub fn init(app: *App) !Self {
        var rooms = Room.Map{};
        var members = Member.Map{};
        
        try rooms.ensureTotalCapacity(app.allocator, config.server.room_limit);
        errdefer rooms.deinit(app.allocator);
        try members.ensureTotalCapacity(app.allocator, config.server.member_limit);
        errdefer members.deinit(app.allocator);
        
        return Self{
            .app = app,
            .rooms = rooms,
            .members = members,
        };
    }

    pub fn deinit(self: *Self) void {
        self.rooms.deinit(self.app.allocator);
        self.members.deinit(self.app.allocator); 
    }
};
