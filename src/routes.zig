const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const game = @import("game.zig");
const conf = @import("config.zig");
const app = @import("app.zig");
const html = @import("html.zig");
const server = @import("server.zig");

const Allocator = std.mem.Allocator;
const Request = httpz.Request;
const Response = httpz.Response;
const AppHandler = server.AppHandler;

const RequestError = error {
    InvalidParameter,  
    InvalidFormData, 
};

pub fn @"/"(_: *AppHandler, _: *Request, res: *Response) !void {
    res.status = 200;
    res.body = html.index;
}

pub fn @"/scatty"(_: *AppHandler, _: *Request, res: *Response) !void {
    res.status = 200;
    res.body = html.scatty_index;
}

pub fn @"/scatty/room-list"(application: *AppHandler, _: *Request, res: *Response) !void {
    res.status = 200;

    const res_writer = res.writer();
    var room_it = application.data.rooms.valueIterator();
    var count: usize = 0;

    while (room_it.next()) |room| : (count += 1) {
        if (count < conf.max_room_list_items) {
            res_writer.print(html.room_list_item, .{
                uuid.urn.serialize(room.id),
                uuid.urn.serialize(room.id),
                room.name,
                room.name,
            }) catch {
                res.body = "???";
                return;
            };
        } else break;
    } 
}

pub fn @"/scatty/join-room/:room_id"(application: *AppHandler, req: *Request, res: *Response) !void {
    res.status = 200;

    const req_room_urn = req.param("room_id") orelse {
        return RequestError.InvalidParameter;    
    };
    const req_room_id = try uuid.urn.deserialize(req_room_urn);
    const req_room = application.data.rooms.get(req_room_id) orelse {
        return app.RoomError.RoomNotFound;
    };
    
    const res_writer = res.writer();
    try res_writer.print(html.player_create_name, .{
        req_room_urn,
        req_room.name,
    });
}

pub fn @"/scatty/enter-room/:room_id"(application: *AppHandler, req: *Request, res: *Response) !void {
    res.status = 200;

    const query = try req.query();
    const req_member_name = query.get("name") orelse "???";

    const req_room_urn = req.param("room_id") orelse {
        return RequestError.InvalidParameter;
    };
    const req_room_id = try uuid.urn.deserialize(req_room_urn);
    const result = try application.controller.joinRoom(req_member_name, req_room_id);

    const res_writer = res.writer();
    try res_writer.print(html.scatty_room, .{
        req_room_urn,
        uuid.urn.serialize(result.member_id),
    });
}

pub fn @"/scatty/connect-room/:room_id/:member_id"(application: *AppHandler, req: *Request, res: *Response) !void {
    const req_room_urn = req.param("room_id") orelse {
        return RequestError.InvalidParameter;
    };
    const req_room_id = try uuid.urn.deserialize(req_room_urn);
    
    const req_member_urn = req.param("member_id") orelse {
        return RequestError.InvalidParameter;
    };
    const req_member_id = try uuid.urn.deserialize(req_member_urn);

    const ws_ctx = server.AppHandler.WebsocketContext{
        .application = application,
        .room_id = req_room_id,
        .member_id = req_member_id,
    };

    if (try httpz.upgradeWebsocket(server.AppHandler.WebsocketHandler, req, res, &ws_ctx) == false) {
        res.status = 400; 
        res.body = "Invalid Websocket Handshake";
        return;
    }
}
