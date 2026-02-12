const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const scatty = @import("scatty.zig");
const server = @import("../../server.zig");

const ServerError = server.ServerError;

// std =========================================================================
const Allocator = std.mem.Allocator;
const List = std.ArrayList;
// server ======================================================================
const App = server.App;
const Member = server.Member;
const Room = server.Room;
// scatty ======================================================================
const Game = scatty.Game;
const Player = scatty.Player;
const Source = scatty.events.Source;
// httpz =======================================================================
const Request = httpz.Request;
const Response = httpz.Response;

pub fn answering(arena: Allocator, src: *Source) !void {
    const game = &src.room.game;

    game.state.scene = .answer;

    for (src.room.members.values()) |member| {
        src.room.queue.wait(member) catch continue;
        member.conn.write(try scatty.rendering.answeringScene(arena, 10)) catch continue;
        for (0..game.opts.num_categories) |idx| {
            member.conn.write(try scatty.rendering.answerInput(arena, @intCast(idx + 1), game.round.categories.items[idx])) catch continue;
        }
    }
}

pub fn voting(arena: Allocator, src: *Source) !void {
    const game = &src.room.game;

    const index: usize = get_and_set: {
        switch (game.state.scene) {
            .vote => |data| {
                game.state.scene = .{ .vote = .{ .category = data.category + 1 } };
                break :get_and_set @intCast(data.category + 1);
            },
            else => {
                game.state.scene = .{ .vote = .{ .category = 0 } };
                break :get_and_set 0;
            },
        }
    };


    for (src.room.members.values()) |member| {
        member.conn.write(scatty.rendering.votingScene(arena, src) catch continue) catch continue;
        for (src.room.members.values()) |other_member| {
            const voting_answers_input = scatty.rendering.votingAnswersInput(arena, index, member, other_member) catch continue;
            if (voting_answers_input) |html| member.conn.write(html) catch continue;
        }
    }
}
