const std = @import("std");


const core = @import("core.zig");
const Client = core.client.Client; 


const utils = @import("../utils/utils.zig");
const Uuid = utils.uuid.Uuid;


pub const Scope = struct {
    clients: Client.List, 
    uuid: Identifier,

    const Self = @This();
    pub const Identifier = Uuid;
};
