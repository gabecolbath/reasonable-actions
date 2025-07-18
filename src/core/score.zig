const std = @import("std");


const utils = @import("../utils/utils.zig");
const Uuid = utils.uuid.Uuid;


pub const Scope = struct {
    uuid: Identifier,

    const Self = @This();
    pub const Identifier = Uuid;
};
