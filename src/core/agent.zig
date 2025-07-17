const std = @import("std");


const utils = @import("../utils/utils.zig");
const Uuid = utils.uuid.Uuid;


const network = @import("../network/network.zig");
const Connection = network.websocket.Connection;


const application = @import("../application.zig");
const App = application.App; 


pub const Agent = struct {
    uuid: Identifier,
    name: []const u8,
    conn: *Connection,

    const Self = @This();
    pub const Identifier = Uuid;
};
