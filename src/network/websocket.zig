const std = @import("std");

const core = @import("../core/core.zig");
const Client = core.client.Client;


const network = @import("network.zig");
pub const Connection = network.httpz.websocket.Conn;


pub const WebsocketHandler = Client;
