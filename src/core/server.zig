const std = @import("std");
const Allocator = std.mem.Allocator;


const application = @import("../application.zig");
const App = application.App; 


const entities = @import("../entities/entities.zig");
const Room = entities.room.Room;
const Member = entities.member.Member;


pub const ServerError = error {
    RoomNotFound,
    MemberNotFound,
    NoSyncedPlayer,
};


pub const Server = struct { 
    app: *App, 
    rooms: Room.Map, 
    members: Member.Map, 
};
