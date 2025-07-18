const std = @import("std");


const utils = @import("../utils/utils.zig");
const Uuid = utils.uuid.Uuid;


const core = @import("core.zig");
const Client = core.client.Client;


const application = @import("../application.zig");
const App = application.App; 


pub const Agent = struct {
    client: *Client,
    uuid: Identifier,
    name: []const u8,

    const Self = @This();
    pub const Identifier = Uuid;
};
