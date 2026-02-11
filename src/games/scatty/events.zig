const std = @import("std");
const scatty = @import("scatty.zig");
const server = @import("../../server.zig");

// std =========================================================================
const Allocator = std.mem.Allocator;
// server ======================================================================
const Room = server.Room;
const Member = server.Member;
// scatty ======================================================================
const Game = scatty.Game;
const Player = scatty.Player;

const Event = server.events.Event;
const Source = server.events.Source;
const Context = server.events.Context;
const Handler = server.events.Handler;
const Parser = server.events.Parser;
const Queue = server.events.Queue;

pub const handler = Handler.init(.{
    .{ "start", &onStart },
    .{ "player-joined", &onPlayerJoined },
    .{ "player-left", &onPlayerLeft },
    .{ "player-answered", &onPlayerAnswered },
});

pub fn onStart(arena: Allocator, ctx: *const Context) !void {
    const src = ctx.src;

    try src.room.game.start();
    try scatty.frontend.answering(arena, src);
}

pub fn onPlayerJoined(arena: Allocator, ctx: *const Context) !void {
    const src = ctx.src;

    try server.frontend.msg.newGame(arena, src);
    try server.frontend.msg.updateNames(arena, src);
    try src.room.game.join(&src.player);
}

pub fn onPlayerLeft(arena: Allocator, ctx: *const Context) !void {
    const src = ctx.src;

    try server.frontend.msg.updateNames(arena, src);
    src.room.game.kick(&src.player);
}

pub fn onPlayerAnswered(arena: Allocator, ctx: *const Context) !void {
    const src = ctx.src;
    const game = &src.room.game;
    // const player = &src.player;

    src.room.queue.done(src);

    std.debug.print("\n\nPlayer answered event triggered with msg: \n {s} \n\n", .{
        if (ctx.msg) |msg| msg.raw else @as([]const u8, "-- --"),
    });

    update_answers: {
        const answers = Parser.list(arena, ctx, .{
            .list_name = "answer",
            .include_missing = true,
            .num_vals_limit = game.opts.num_categories,
        }) catch break :update_answers;

        std.debug.print("Answers from {s}:\n", .{src.name});
        for (0..answers.len) |category| {
            if (answers[category]) |answer| {
                std.debug.print("\t{d}. {s}\n", .{
                    category,
                    if (Parser.string(answer)) |str| str else @as([]const u8, "-- --"),
                });
            }
        }
    }

    if (src.room.queue.allDone(src)) {
        try scatty.frontend.voting(arena, src);
    }
}
