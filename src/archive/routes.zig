const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz");
const mustache = @import("mustache");
const conf = @import("config.zig");
const server = @import("server.zig");
const elements = @import("rendering/elements.zig");
const attributes = @import("rendering//attributes.zig");
const games = @import("games/games.zig");

pub const RequestError = error {
    InvalidParameter,
    InvalidFormData,
};

const Allocator = std.mem.Allocator;
const App = server.Application;
const Html = []const u8;
const Elem = elements.Element;
const GameTag = games.GameTag;
const Request = httpz.Request;
const Response = httpz.Response;
const RouteMap = std.StaticStringMap(httpz.Action(*App));
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;

pub const map = .{
    .get = RouteMap.initComptime(.{
        .{ "/", Get.index },
        .{ "/rooms/join/list", Get.roomsJoinList },
        .{ "/rooms/join/card", Get.roomsJoinCard },
        .{ "/rooms/join/form", Get.roomsJoinForm },
        .{ "/rooms/create/card", Get.roomsCreateCard },
        .{ "/rooms/create/form", Get.roomsCreateForm },
        .{ "/rooms/enter/:room_urn/:member_urn/:game_choice", Get.roomsEnter },
        .{ "/styling/index", Get.indexStyling },
        .{ "/styling/room-card", Get.roomCardStyling },
        .{ "/styling/rooms-page", Get.roomsPageStyling },
        .{ "/styling/enter-room-form", Get.enterRoomFormStyling },
        .{ "/debug/room-card-template", Get.debugRoomCardTemplate },
    }),
    .post = RouteMap.initComptime(.{
        .{ "rooms/join", Post.joinRoom },
        .{ "rooms/create", Post.createRoom },
    }),
};

pub const Get = struct {
    pub fn index(_: *App, _: *Request, res: *Response) !void {
        const index_page_template = @embedFile("html/dev/index-page-template.html");
        const rooms_page = @embedFile("html/dev/rooms-page.html"); 

        const index_page = try mustache.allocRenderText(res.arena, index_page_template, .{
            .page = rooms_page, 
        });

        res.content_type = .HTML;
        res.status = 200;
        res.body = index_page;
    }

    pub fn roomsJoinList(app: *App, _: *Request, res: *Response) !void {
        const room_card_template = @embedFile("html/dev/room-card-template.html");
        
        const rooms = app.rooms.values();

        res.content_type = .HTML;
        res.status = 200;
        const res_out = res.writer();
        for (rooms) |room| {
            const room_host = try app.host(room.uid.self);
            const room_card = try mustache.allocRenderText(res.arena, room_card_template, .{
                .room_urn = uuid.urn.serialize(room.uid.self), 
                .host_name = room_host.name,
                .member_count = room.uid.members.count(),
                .member_capacity = conf.room_members_capacity,
                .is_private = true,
            });
            
            try res_out.writeAll(room_card);
        }
    }

    pub fn roomsJoinCard(app: *App, req: *Request, res: *Response) !void {
        const room_card_template = @embedFile("html/dev/room-card-template.html");
        
        const query = try req.query();
        const req_room_urn = query.get("room-urn") orelse return RequestError.InvalidFormData;
        const req_room_uid = try uuid.urn.deserialize(req_room_urn);
        const req_room = try app.room(req_room_uid);
        const req_host = try app.host(req_room_uid);

        const room_card = try mustache.allocRenderText(res.arena, room_card_template, .{
            .room_urn = req_room_urn,
            .host_name = req_host.name,
            .member_count = req_room.uid.members.count(),
            .member_capacity = conf.room_members_capacity,
            .is_private = true,
        });

        res.content_type = .HTML;
        res.status = 200;
        res.body = room_card;
    }

    pub fn roomsJoinForm(app: *App, req: *Request, res: *Response) !void {
        const join_room_form_template = @embedFile("html/dev/join-room-form-template.html");
        
        const query = try req.query();
        const req_room_urn = query.get("room-urn") orelse return RequestError.InvalidFormData;
        const req_room_uid = try uuid.urn.deserialize(req_room_urn);
        _ = app.room(req_room_uid) catch {
            res.body = "This Room Does Not Exist. Try Refreshing the Page.";
            return;
        };
        
        const join_room_form = try mustache.allocRenderText(res.arena, join_room_form_template, .{
            .room_urn = req_room_urn,
        });

        res.content_type = .HTML;
        res.status = 200;
        res.body = join_room_form;
    }

    pub fn roomsEnter(app: *App, req: *Request, res: *Response) !void {
        const req_member_urn = req.param("member_urn") orelse return RequestError.InvalidParameter;
        const req_room_urn = req.param("room_urn") orelse return RequestError.InvalidParameter;
        const req_game = req.param("game_choice") orelse return RequestError.InvalidParameter;
        const req_member_uid = try uuid.urn.deserialize(req_member_urn);
        const req_room_uid = try uuid.urn.deserialize(req_room_urn); 

        const req_game_tag: GameTag = if (std.mem.eql(u8, req_game, @tagName(GameTag.scatty))) .scatty else return RequestError.InvalidParameter;

        const ctx = server.Client.Context{
            .app = app,
            .game = req_game_tag,
            .uid = .{
                .room = req_room_uid,
                .member = req_member_uid,
            }
        };
        
        _ = try httpz.upgradeWebsocket(server.Client, req, res, &ctx);
    }

    pub fn roomsCreateCard(_: *App, _: *Request, res: *Response) !void {
        const create_room_card = @embedFile("html/dev/create-room-card.html");
        
        res.content_type = .HTML;
        res.status = 200;
        res.body = create_room_card;
    }

    pub fn roomsCreateForm(_: *App, _: *Request, res: *Response) !void {
        const create_room_form = @embedFile("html/dev/create-room-form-template.html");
        
        res.content_type = .HTML;
        res.status = 200;
        res.body = create_room_form;
    }
    
    pub fn debugRoomCardTemplate(_: *App, _: *Request, res: *Response) !void {
        const page_template = @embedFile("html/dev/index-page-template.html");
        const card_template = @embedFile("html/dev/room-card-template.html");

        const card = try mustache.allocRenderText(res.arena, card_template, .{
            .room_name = "Kitty Room",
            .member_count = 3,
            .member_capacity = conf.room_members_capacity, 
            .is_private = true,
        });

        const page = try mustache.allocRenderText(res.arena, page_template, .{
            .page = card, 
        });

        res.content_type = .HTML;
        res.status = 200;
        res.body = page;
    }

    pub fn indexStyling(_: *App, _: *Request, res: *Response) !void {
        const stylesheet = @embedFile("html/dev/styles/index.css");
        
        res.content_type = .CSS;
        res.status = 200;
        res.body = stylesheet;
    }

    pub fn roomCardStyling(_: *App, _: *Request, res: *Response) !void {
        const stylesheet = @embedFile("html/dev/styles/room-card.css");
        
        res.content_type = .CSS;
        res.status = 200;
        res.body = stylesheet;
    }

    pub fn roomsPageStyling(_: *App, _: *Request, res: *Response) !void {
        const stylesheet = @embedFile("html/dev/styles/rooms-page.css");
        
        res.content_type = .CSS;
        res.status = 200;
        res.body = stylesheet;
    }

    pub fn enterRoomFormStyling(_: *App, _: *Request, res: *Response) !void {
        const stylesheet = @embedFile("html/dev/styles/enter-room-form.css");
        
        res.content_type = .CSS;
        res.status = 200;
        res.body = stylesheet;
    }
};

pub const Post = struct {
    pub fn joinRoom(app: *App, req: *Request, res: *Response) !void {
        const room_page_template = @embedFile("html/dev/room-page.html");
        
        const form_data = try req.formData();
        const room_urn = form_data.get("room-urn") orelse return RequestError.InvalidFormData;
        const member_name = form_data.get("member-name") orelse "???";
        
        const req_room_uid = try uuid.urn.deserialize(room_urn);
        const join_result = app.joinRoom(member_name, .{ .room = req_room_uid }) catch |err| {
            if (err == server.ServerError.AtRoomMemberCapacity) {
                res.body = "At Capacity for this room. Try another.";
                return;
            } else return err;
        }; 

        const room_page = try mustache.allocRenderText(res.arena, room_page_template, .{
            .room_urn = uuid.urn.serialize(join_result.room.uid.self),
            .member_urn = uuid.urn.serialize(join_result.member.uid.self),
        });

        res.content_type = .HTML;
        res.status = 200;
        res.body = room_page;
    }

    pub fn createRoom(app: *App, req: *Request, res: *Response) !void {
        const room_page_template = @embedFile("html/dev/room-page.html");
    
        const form_data = try req.formData();
        const member_name = form_data.get("member-name") orelse return RequestError.InvalidFormData;
        const req_game = form_data.get("game-choice") orelse return RequestError.InvalidFormData;

        const game_choice = try games.toGameTag(req_game);

        const create_result = try app.createRoom(game_choice, member_name);
        
        const room_page = try mustache.allocRenderText(res.arena, room_page_template, .{
            .room_urn = uuid.urn.serialize(create_result.room.uid.self),
            .member_urn = uuid.urn.serialize(create_result.member.uid.self),
            .game_choice = game_choice,
        });

        res.content_type = .HTML;
        res.status = 200;
        res.body = room_page;
    }
};
