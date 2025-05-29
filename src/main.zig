const std = @import("std");
const httpz = @import("httpz");
const game = @import("game.zig");
const conf = @import("config.zig");
const app = @import("app.zig");

const Request = httpz.Request;
const Response = httpz.Response;

const Handler = struct {

    const Self = @This();

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var handler = Handler{};
    var server = try httpz.Server(*Handler).init(allocator, .{
        .port = conf.port,
        .request = .{
            .max_form_count = 20,
        },
    }, &handler);
    defer server.deinit();
    defer server.stop();
    
    var router = try server.router(.{});
    router.get("/", indexView, .{});
    router.post("/join", joinRoom, .{});
    router.get("/room/:id", enterRoom, .{});

    std.debug.print("Listening http://localhost:{d}/\n", .{conf.port});
    
    try server.listen();
}

fn indexView(_: *Handler, _: *Request, res: *Response) !void {
    res.body = conf.index_view;
}

fn joinRoom(_: *Handler, req: *Request, _: *Response) !void {
    // TODO
    const form_data = try req.formData();
    const name = form_data.get("name") orelse "???";

    std.debug.print("{s} joined the room.", .{name});
}

fn enterRoom(_: *Handler, _: *Request, _: *Response) !void {
    // TODO
}
