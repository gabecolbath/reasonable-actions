const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const mus = @import("mustache");

const Action = httpz.Action;
const Allocator = std.mem.Allocator;
const Request = httpz.Request;
const Response = httpz.Response; 
const StaticStringMap = std.StaticStringMap;
const Uuid = uuid.Uuid;


const server = @import("server.zig");
const games = @import("games/games.zig");
const conf = @import("config.zig");

const App = server.App;
const Member = server.Member;
const Room = server.Room;
const Client = server.Client; 
const Game = games.Game;
const Player = games.Player;
const RouteMap = StaticStringMap(Action(*App));


pub const RequestError = error {
    InvalidQuery,
    InvalidParamter,
    InvalidFormData,
};


pub const map = .{
    .get = RouteMap.initComptime(.{
        .{ "/", Get.@"/" }, 
        .{ "/rooms", Get.@"/rooms" },
        .{ "/rooms/join/card", Get.@"rooms/join/card" },
        .{ "/rooms/join/card/form", Get.@"rooms/join/card/form" },
        .{ "/rooms/create/card", Get.@"rooms/create/card" }, 
        .{ "/rooms/create/card/form", Get.@"rooms/create/card/form" },
    }),
    .post = RouteMap.initComptime(.{
        .{ "/rooms/join", Post.@"/rooms/join" },
        .{ "/rooms/create", Post.@"/rooms/create" },
    }),
};


const Get = struct {
    fn @"/"(_: *App, _: *Request, res: *Response) !void {
        const new_page_template_html = @embedFile("html/dev/new-page-template.html");
        const rooms_page_html = @embedFile("html/dev/rooms-page.html");
        
        const new_page_html = try mus.allocRenderText(res.arena, new_page_template_html, .{
            .page = rooms_page_html,
        });

        res.content_type = .HTML;
        res.status = 200;
        res.body = new_page_html;
    }

    fn @"/rooms"(app: *App, _: *Request, res: *Response) !void {
        const rooms_card_template_html = @embedFile("html/dev/room-card-template.html");
        const rooms_join_card_content_html = ""; //TODO
        const rooms_create_card_content_html = ""; //TODO

        const rooms_create_card_html = try mus.allocRenderText(res.arena, rooms_card_template_html, .{
            .content = rooms_create_card_content_html,
        });
        
        const rooms_join_card_template_html = try mus.allocRenderText(res.arena, rooms_card_template_html, .{
            .content = rooms_join_card_content_html,
        });
        const rooms_join_card_template = try mus.parseText(res.arena, rooms_join_card_template_html, .{});

        
        const rooms = app.rooms.map.values();
        
        res.content_type = .HTML;
        res.status = 200;
        const resout = res.writer();

        try resout.writeAll(rooms_create_card_html);
        
        for (rooms) |room| {
            const room_card_join_html = try mus.allocRender(res.arena, rooms_join_card_template, .{
                .room_urn = uuid.urn.serialize(room.uid),
                .host_name = room.host.member.name,
                .member_count = room.clients.items.len,
                .member_capacity = conf.room_members_capacity,
                .is_private = room.isPrivate(),
            });
            
            resout.writeAll(room_card_join_html) catch continue;
        }
    }

    fn @"rooms/join/card"(app: *App, req: *Request, res: *Response) !void {
        const rooms_card_template_html = @embedFile("html/dev/room-card-template.html");
        const rooms_join_card_content_html = ""; //TODO
        
        const rooms_join_card_template_html = try mus.allocRenderText(res.arena, rooms_card_template_html, .{
            .content = rooms_join_card_content_html,
        });
        
        const query = try req.query();
        const room_urn = query.get("room-urn") orelse return RequestError.InvalidQuery;

        const room_uid = try uuid.urn.deserialize(room_urn);
        const room = try app.getRoom(room_uid);

        res.content_type = .HTML;
        res.status = 200;
        res.body = try mus.allocRenderText(res.arena, rooms_join_card_template_html, .{
            .room_urn = room_urn,
            .host_name = room.host.member.name,
            .member_count = room.clients.items.len,
            .member_capacity = conf.room_members_capacity,
            .is_private = room.isPrivate(),
        });
    }

    fn @"rooms/join/card/form"(_: *App, req: *Request, res: *Response) !void {
        const rooms_join_card_form_template_html = ""; //TODO
        
        const query = try req.query();
        const room_urn = query.get("room-urn") orelse return RequestError.InvalidQuery;
        
        const rooms_join_card_form = try mus.allocRenderText(res.arena, rooms_join_card_form_template_html, .{
            .room_urn = room_urn,
        });
        
        res.content_type = .HTML;
        res.status = 200;
        res.body = rooms_join_card_form;
    }

    fn @"rooms/create/card"(_: *App, _: *Request, res: *Response) !void {
        const rooms_card_template_html = @embedFile("html/dev/room-card-template.html");
        const rooms_create_card_content_html = ""; //TODO

        const rooms_create_card = try mus.allocRenderText(res.arena, rooms_card_template_html, .{
            .content = rooms_create_card_content_html,
        });
        
        res.content_type = .HTML;
        res.status = 200;
        res.body = rooms_create_card;
    }

    fn @"rooms/create/card/form"(_: *App, _: *Request, res: *Response) !void {
        const rooms_create_card_form = ""; //TODO

        res.content_type = .HTML;
        res.status = 200;
        res.body = rooms_create_card_form;
    }
};

const Post = struct {
    fn @"rooms/join"(app: *App, req: *Request, res: *Response) !void {
        const form_data = try req.formData();       
        const member_name = form_data.get("member-name") orelse return RequestError.InvalidFormData; 
        const room_urn = form_data.get("room-urn") orelse return RequestError.InvalidFormData;
        
        const room_uid = try uuid.urn.deserialize(room_urn); 
        const room = try app.getRoom(room_uid);
        const game = try room.getGame();

        const new_member = try Member.init(app.allocator, member_name); 
        errdefer new_member.deinit(app.allocator);

        const ws_context = Client.Context{
            .app = app,
            .room = room,
            .member = new_member,
            .game_tag = game.tag,
        };

        _ = try httpz.upgradeWebsocket(Client, req, res, &ws_context);
    }

    fn @"rooms/create"(app: *App, req: *Request, res: *Response) !void {
        const form_data = try req.formData();
        const member_name = form_data.get("member-name") orelse return RequestError.InvalidFormData;
        const game_choice = form_data.get("game-choice") orelse return RequestError.InvalidFormData;
        const password = form_data.get("password");
        
        const privacy: Room.Privacy = set: {
            if (password) |pw| {
                break :set .{ .private = .{ .pw = pw } };
            } else {
                break :set .public;
            }
        };

        const new_room = try Room.init(app.allocator, privacy); 
        errdefer new_room.deinit(app.allocator); 
        const new_member = try Member.init(app.allocator, member_name);
        errdefer new_member.deinit(app.allocator); 

        const ws_context = Client.Context{
            .app = app,
            .room = new_room,
            .member = new_member,
            .game_tag = try games.toGameTag(game_choice),
        };

        _ = try httpz.upgradeWebsocket(Client, req, res, &ws_context);
    }
}; 
