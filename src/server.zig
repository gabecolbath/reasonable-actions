const std = @import("std");
const httpz = @import("httpz");
const app = @import("application.zig");

const App = app.App;

const HttpHandler = struct {
    app: *App,

    pub fn notFound(_: *HttpHandler, req: *httpz.Request, res: *httpz.Response) !void {
        std.debug.print("ERROR 404 - Not Found at {s}.\n", .{req.url.path});

        res.content_type = .HTML;
        res.status = 404;
        res.body =
            \\<h1>Error 404</h1>
            \\<h2>Not Found.</h2>
        ;
    }

    pub fn uncaughtError(_: *HttpHandler, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
        std.debug.print("ERROR 500 - Uncaught Error at {s}.\n", .{req.url.path});
        std.debug.print("{}\n", .{err});

        res.content_type = .HTML;
        res.status = 505;
        res.body =
            \\<h1>Error 500</h1>
            \\<h2>Internal Server Error.</h2>
        ;
    }
};

const app_opts = app.AppOptions{};

const server_opts = httpz.Config{
    .port = 3000,
    .request = .{ .max_form_count = 5 },
};

pub fn main() !void {
    var running_application = App.init(std.heap.smp_allocator, app_opts);
    defer running_application.deinit();

    const http_handler = HttpHandler{ .app = &running_application };
    var server = try httpz.Server(HttpHandler).init(std.heap.smp_allocator, server_opts, http_handler);
    defer server.deinit();

    // TODO setup router.
    const router = try server.router(.{});
    _ = router;

    std.debug.print("Listening to http://localhost:{any}/\n", .{server_opts.port});
    try server.listen();
}
