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

pub const Event = server.events.Event;
pub const Source = server.events.Source;
pub const Context = server.events.Context;
pub const Handler = server.events.Handler;
pub const Parser = server.events.Parser;
pub const Queue = server.events.Queue;

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
    const player = &src.player;

    src.room.queue.done(src);

    update_answers: {
        const form = Parser.list(arena, ctx, .{
            .list_name = "answer",
            .include_missing = true,
            .num_vals_limit = game.opts.num_categories,
        }) catch break :update_answers;

        for (0..form.len) |index| {
            if (form[index]) |value| {
                const answer = Parser.string(value);
                player.round.answers.items[index] = answer;
            }
        }
    }

    if (src.room.queue.allDone(src)) {
        try scatty.frontend.voting(arena, src);
    }
}
