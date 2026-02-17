const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const websocket = httpz.websocket;


// std
const Allocator = std.mem.Allocator;
const List = std.ArrayList;
const Map = std.ArrayHashMapUnmanaged;
// uuid
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;
// httpz
const Req = httpz.Request;
const Res = httpz.Response;
const Conn = websocket.Conn;


// =============================================================================
const AppError = error {
    RoomNotFound,
    MemberNotFound,
    ReachedServerMemberLimit,
    ReachedServerRoomLimit,
    ReachedServerMemberPerRoomLimit,
};


// =============================================================================
const Room = struct {

    id: Uuid,
    members: Map(Uuid, *Member),
    name: []const u8,
};


// =============================================================================
const Member = struct {

};


// =============================================================================
const App = struct {

};
