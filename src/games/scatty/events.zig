const std = @import("std");
const scatty = @import("scatty.zig");
const server = @import("../../server.zig");
const rendering = @import("../../rendering.zig");
const frontend = @import("../../frontend.zig");

const Allocator = std.mem.Allocator;
const Room = server.Room;
const Member = server.Member;
const EventHandler = server.EventHandler;
const Event = server.Event;
const Game = scatty.Game;
const Player = scatty.Player;

pub const handler = EventHandler.init(.{
    .{ "start", &onStart },
    .{ "player-joined", &onPlayerJoined },
    .{ "player-left", &onPlayerLeft },
    .{ "player-answered", &onPlayerAnswered },
});

pub fn onStart(arena: Allocator, src: *EventHandler.Source, _: []const u8) !void {
    try src.room.game.start();
    try scatty.frontend.answering(arena, src);
}

pub fn onPlayerJoined(arena: Allocator, src: *EventHandler.Source, _: []const u8) !void {
    try frontend.msg.newGame(arena, src);
    try frontend.msg.updateNames(arena, src);
    try src.room.game.join(&src.player);
}

pub fn onPlayerLeft(arena: Allocator, src: *EventHandler.Source, _: []const u8) !void {
    try frontend.msg.updateNames(arena, src);
    try src.room.game.kick(&src.player);
}

pub fn onPlayerAnswered(arena: Allocator, src: *EventHandler.Source, msg: []const u8) !void {
    std.debug.print("Player - {s} submitted their answers!\n", .{src.name});
    src.room.queue.done(src);

    update_answers: {
        const form = try handler.form(arena, msg, &.{ .{ .list = .{ .name = "answer", .limit = src.room.game.opts.num_categories } } });
        const values = form.get("answer") orelse break :update_answers;
        const answers = if (values == .list) values.list else break :update_answers;

        for (0.., answers) |idx, answer| {
            src.player.round.answers.items[idx] = answer;
        }
    }

    if (src.room.queue.allDone(src)) {
        try scatty.frontend.voting(arena, src);
    }
}
