const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const rendering = @import("rendering.zig");
const server = @import("../../server.zig");
const scatty = @import("scatty.zig");

const ServerError = server.ServerError;

const Allocator = std.mem.Allocator;
const List = std.ArrayList;
const App = server.App;
const Member = server.Member;
const Room = server.Room;
const Game = scatty.Game;
const Player = scatty.Player;
const Request = httpz.Request;
const Response = httpz.Response;

pub fn answering(arena: Allocator, src: *Member) !void {
    const game = &src.room.game;

    game.state.scene = .answer;

    for (src.room.members.values()) |member| {
        src.room.queue.wait(member) catch continue;
        member.conn.write(try rendering.answeringScene(arena, 10)) catch continue;
        for (0..game.opts.num_categories) |idx| {
            member.conn.write(try rendering.answerInput(arena, @intCast(idx + 1), game.round.categories.items[idx])) catch continue;
        }
    }
}

pub fn voting(_: Allocator, _: *Member) !void {
    // TODO
}
