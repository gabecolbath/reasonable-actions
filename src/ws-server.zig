const std = @import("std");
const httpz = @import("httpz");
const app = @import("application.zig");
const ws = httpz.websocket;

const App = app.App;

pub const WebsocketHandler = struct {
    conn: *ws.Conn,
    client: *app.Client,

    const Context = struct {
        app: *App,
        room_to_join: union(enum) { by_id: app.RoomId, by_ptr: *app.Room },
        client_name: ?[]const u8,
    };

    pub fn init(hs: ws.Handshake, conn: *ws.Conn, ctx: *Context) !WebsocketHandler {
        _ = hs;
        const room = switch (ctx.room_to_join) {
            .by_id => |id| try ctx.app.rooms.get(id),
            .by_ptr => |r| r,
        };

        const new_client = try room.newClient(ctx.name);
        _ = new_client.connect(conn);
        const handler = WebsocketHandler{ .conn = conn, .client = new_client };

        return handler;
    }

    pub fn clientMessage(handler: *WebsocketHandler, allocator: std.mem.Allocator, data: []const u8) !void {
        _ = allocator;

        // TODO implement message handling.
        handler.conn.write(data);
    }
};
