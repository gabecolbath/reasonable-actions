const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const mustache = @import("mustache");
const conf = @import("config.zig");
const server = @import("server.zig");
const elements = @import("rendering/elements.zig");
const attributes = @import("rendering//attributes.zig");
const game = @import("game.zig");

pub const RequestError = error {
    InvalidParameter,
    InvalidFormData,
};

const Allocator = std.mem.Allocator;
const App = server.Application;
const Html = []const u8;
const Elem = elements.Element;
const Request = httpz.Request;
const Response = httpz.Response;
const RouteMap = std.StaticStringMap(httpz.Action(*App));
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

pub const map = .{
    .get = RouteMap.initComptime(.{
        .{ "/", Get.index },
        .{ "/rooms", Get.rooms },
        .{ "/rooms/list", Get.roomsList },
    }),
    .post = RouteMap.initComptime(.{
        .{ "/rooms/create", Post.createRoom },
        .{ "/rooms/enter", Post.enterRoom },
    }),
};

pub const Get = struct {
    pub fn index(_: *App, _: *Request, res: *Response) !void {
        const content = @embedFile("content/index.html");

        res.content_type = .HTML;
        res.status = 200;
        res.body = content;
    }

    pub fn rooms(_: *App, _: *Request, res: *Response) !void {
        const content = @embedFile("content/rooms.html");

        res.content_type = .HTML;
        res.status = 200;
        res.body = content;
    }

    pub fn roomsList(app: *App, _: *Request, res: *Response) !void {
        const template = @embedFile("content/rooms-list-item.html");

        if (app.rooms.count() == 0) {
            res.content_type = .HTML;
            res.status = 200;
            res.body = "No Rooms :(";
        } else {
            res.content_type = .HTML;
            res.status = 200;
            const output = res.writer();
            for (app.rooms.values()) |room| {
                const content = try mustache.allocRenderText(res.arena, template, .{
                    .room_urn = uuid.urn.serialize(room.uid),
                    .room_name = room.name,
                });
                try output.writeAll(content);
            }
        }
    }
};

pub const Post = struct {
    pub fn createRoom(app: *App, req: *Request, res: *Response) !void {
        const template = @embedFile("content/enter-room.html");

        const form_data = try req.formData();
        const room_name = form_data.get("room-name") orelse "???";

        const new_room = try app.openRoom(room_name);
        errdefer app.closeRoom(new_room.uid);
        
        const content = try mustache.allocRenderText(res.arena, template, .{
            .room_urn = uuid.urn.serialize(new_room.uid),
        });
        
        res.content_type = .HTML;
        res.status = 200;
        res.body = content;
    }

    pub fn enterRoom(app: *App, req: *Request, res: *Response) !void {
        const template = @embedFile("content/room.html");

        const form_data = try req.formData();
        const room_urn = form_data.get("room-urn") orelse return RequestError.InvalidFormData;
        const memeber_name = form_data.get("member-name") orelse "???";

        const room_uid = try uuid.urn.deserialize(room_urn);
        const room = app.rooms.get(room_uid) orelse return server.ServerError.RoomNotFound;
        
        errdefer app.closeRoom(room_uid);
        const new_member = try app.newMember(memeber_name);
        app.waiting.putAssumeCapacity(new_member.uid, .{
            .app = app,
            .member = new_member,
            .room = room,
        });
        
        const content = try mustache.allocRenderText(res.arena, template, .{
            .room_name =room.name,
            .room_urn = room_urn,
        });
        
        res.content_type = .HTML;
        res.status = 200;
        res.body = content;
    }
};
