const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const game = @import("game.zig");
const conf = @import("config.zig");
const app = @import("app.zig");
const html = @import("html.zig");
const server = @import("server.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList; 
const Request = httpz.Request;
const Response = httpz.Response;
const AppHandler = server.AppHandler;

const RequestError = error {
    InvalidParameter,  
    InvalidFormData, 
};

const ResponseError = error {
    TemplateError,
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

pub fn @"/scatty/game/base-options/:room_id"(_: *AppHandler, req: *Request, res: *Response) !void {
    const req_room_urn = req.param("room_id") orelse {
        return RequestError.InvalidParameter;
    };
    const base_opts = game.Options{};

    var list_names_buffer = ArrayList(u8).init(res.arena);
    for (base_opts.general.list_names) |name| {
        try list_names_buffer.appendSlice(name);
        try list_names_buffer.appendSlice(", ");
    }
    const list_names = try list_names_buffer.toOwnedSlice();

    const template = html.scatty_base_options;
    const res_writer = res.writer();
    res_writer.print(template, .{
        req_room_urn,
        base_opts.general.num_categories,
        base_opts.general.num_rounds,
        if (base_opts.general.same_categories_per_round) "checked" else "",
        list_names,
        base_opts.answering.answering_time_limit,
        if (base_opts.answering.bonus_time_for_last_answer != null) "checked" else "",
        base_opts.answering.bonus_time_for_last_answer orelse 0,
        if (base_opts.voting.vote_time_limit != null) "checked" else "",
        base_opts.voting.vote_time_limit orelse 0,
        if (base_opts.voting.show_names_in_vote) "checked" else "",
        if (base_opts.scoring.score_weighted_by_vote) "checked" else "",
    }) catch {
        return ResponseError.TemplateError;
    };
}

pub fn @"/scatty/game/apply-options/:room_id"(application: *AppHandler, req: *Request, res: *Response) !void {
    _ = application;
    
    std.debug.print("Recieved: \n", .{});
    const form_data = try req.formData();
    var form_it = form_data.iterator();
    while (form_it.next()) |kv| {
        std.debug.print("\t{s} : {s}\n", .{kv.key, kv.value});
    }

    res.status = 200;
}
