const std = @import("std");
const httpz = @import("httpz");
const game = @import("game.zig");
const conf = @import("config.zig");
const app = @import("app.zig");
const uuid = @import("uuid");
const routes = @import("routes.zig");
const html = @import("html.zig");

const websocket = httpz.websocket;

const Allocator = std.mem.Allocator;
const Request = httpz.Request;
const Response = httpz.Response;
const Uuid = uuid.Uuid;

pub const AppHandler = struct {
    allocator: Allocator,
    data: *app.Data,
    controller: app.Control,

    const Self = @This();
    pub const WebsocketContext = struct {
        application: *AppHandler,
        member_id: Uuid,
        room_id: Uuid,
    };
    pub const WebsocketHandler = struct {
        conn: *websocket.Conn,
        application: *AppHandler,
        ids: struct {
            member: Uuid,  
            room: Uuid,
        },

        pub fn init(conn: *websocket.Conn, ctx: *const WebsocketContext) !WebsocketHandler {
            return WebsocketHandler{
                .conn = conn,
                .application = ctx.application,
                .ids = .{
                    .member = ctx.member_id,
                    .room = ctx.room_id,
                },
            };
        }

        pub fn afterInit(client : *WebsocketHandler) !void {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            const allocator = gpa.allocator();

            const room = client.application.data.rooms.get(client.ids.room).?;
            const info = try room.info(allocator);
            defer allocator.free(info);

            const response = try std.fmt.allocPrint(allocator, html.scatty_game, .{info});
            defer allocator.free(response);
            
            try client.conn.write(response); 
        }

        pub fn clientMessage(client: *WebsocketHandler, data: []const u8) !void {
            try client.conn.write(data);
        }

        pub fn close(client: *WebsocketHandler) void {
            client.application.controller.leaveRoom(client.ids.room, client.ids.member) catch return;
        }
    };

    pub fn init(allocator: Allocator) !Self {
        const data_ptr = try allocator.create(app.Data);
        data_ptr.* = app.Data.init(allocator);
        return Self{
            .allocator = allocator,
            .data = data_ptr,
            .controller = app.Control{ .app_data = data_ptr },
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit(); 
        self.allocator.destroy(self.data);
    }

    pub fn notFound(_: *Self, _: *Request, res: *Response) !void {
        res.status = 404;
        res.body = "Error: Not Found";
    }

    pub fn uncaughtError(_: *Self, req: *Request, res: *Response, err: anyerror) void {
        std.debug.print("Uncaught http error at {s}: {}\n", .{ req.url.path, err });
        
        res.status = 505;
        res.body = "Error: Server Error";
    }
};

pub fn start() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var handler = try AppHandler.init(allocator);
    defer handler.deinit();

    var server = try httpz.Server(*AppHandler).init(allocator, .{
        .port = conf.port,
        .request = .{
            .max_form_count = 20,
        },
    }, &handler);
    defer server.deinit();
    defer server.stop();
    
    var router = try server.router(.{});
    router.get("/", routes.@"/", .{});
    router.get("/scatty", routes.@"/scatty", .{});
    router.get("/scatty/room-list", routes.@"/scatty/room-list", .{});
    router.get("/scatty/join-room/:room_id", routes.@"/scatty/join-room/:room_id", .{});
    router.get("/scatty/enter-room/:room_id", routes.@"/scatty/enter-room/:room_id", .{});
    router.get("/scatty/connect-room/:room_id/:member_id", routes.@"/scatty/connect-room/:room_id/:member_id", .{});

    std.debug.print("Creating room..\n", .{});
    const kitty_room_result = try handler.controller.createRoom("KittyRoom", "Gabe");
    const kitty_room = handler.data.rooms.get(kitty_room_result.room_id).?;
    kitty_room.print();

    std.debug.print("Creating room..\n", .{});
    const peggy_room_result = try handler.controller.createRoom("PeggyRoom", "Sara");
    const peggy_room = handler.data.rooms.get(peggy_room_result.room_id).?;
    peggy_room.print();

    std.debug.print("Listening http://localhost:{d}/\n", .{conf.port});

    try server.listen();
}

