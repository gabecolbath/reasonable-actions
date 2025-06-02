const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const mustache = @import("mustache");
const server = @import("server.zig");

const Application = server.Application;
const Allocator = std.mem.Allocator; 
const Html = []const u8;
const Request = httpz.Request;
const Response = httpz.Response;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

const RequestError = error {
    InvalidParameter,
};

pub fn @"/"(_: *Application, _: *Request, res: *Response) !void {
    const html = 
        \\<div id="game-list">
        \\<h1>Games</h1>
        \\<a href="/scatty/rooms"
        \\      hx-get="/scatty/rooms"
        \\      hx-target="#game-list"
        \\      hx-swap="innerHTML"
        \\      hx-push-url="true">
        \\      Scatty
        \\</a>
    ;
    
    res.body = html;
}

pub fn @"/scatty/rooms"(_: *Application, _: *Request, res: *Response) !void {
    const html = 
        \\<div id="scatty-rooms">
        \\<h1>Rooms</h1>
        \\<div id="scatty-rooms-list"
        \\      hx-get="/scatty/rooms/list"
        \\      hx-trigger="load"
        \\      hx-target="#scatty-room-list"
        \\      hx-swap="innerHTML">
        \\</div>
        \\</div>
    ;

    res.body = html;   
}

pub fn @"/scatty/rooms/list"(app: *Application, _: *Request, res: *Response) !void {
    const template = 
        \\<a href="/scatty/rooms/{{room_urn}}/join"
        \\      hx-get="/scatty/rooms/{{room_urn}}/join"
        \\      hx-target="#scatty-rooms"
        \\      hx-swap="outerHTML"
        \\      hx-replace-url="/scatty/rooms/{{room_name}}/join">
        \\      {{room_name}}
        \\</a>
    ;

    const res_writer = res.writer();

    var room_it = app.rooms.valueIterator();
    var count: usize = 0;
    while (room_it.next()) |room| : (count += 1) {
        if (count < 50) {
            const data = .{
                .room_urn = uuid.urn.serialize(room.uid),
                .room_name = room.name,
            };
            const html = try mustache.allocRender(res.arena, template, data);
            try res_writer.writeAll(html);
        } else break;
    }
}
