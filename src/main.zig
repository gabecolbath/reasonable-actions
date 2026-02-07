const std = @import("std");
const uuid = @import("uuid");

const server = @import("server.zig");
const scatty = @import("scatty.zig");
const print = std.debug.print;

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}){};
    defer _ = dba.deinit();

    var app = try server.App.init(dba.allocator());
    defer app.deinit();

    var game_arena = std.heap.ArenaAllocator.init(dba.allocator());

    var test_room_name_buf: [32]u8 = undefined;
    const test_room_name_template = "test_room_{d}";

    for (0..10) |index| {
        const test_game = scatty.Game.init(game_arena.allocator(), .{});

        const test_room_ctx = server.Room.Context{
            .app = &app,
            .game = test_game,
            .name = std.fmt.bufPrint(&test_room_name_buf, test_room_name_template, .{index}) catch "test_room_?",
        };

        _ = server.Room.new(&test_room_ctx) catch continue;
    }

    defer game_arena.deinit();

    var host = try server.start(dba.allocator(), &app);
    defer host.deinit();
}

// pub fn main() !void {
//     var dba = std.heap.DebugAllocator(.{}){};
//     defer _ = dba.deinit();
//
//     var game = try scatty.Game.init(dba.allocator(), .{
//         .num_rounds = 2,
//         .scoring_method = .by_count,
//     });
//
//     defer game.deinit();
//
//     var players_joining = [_]scatty.Player{
//         try scatty.Player.init(&game, "Gabe"),
//         try scatty.Player.init(&game, "Michael"),
//         try scatty.Player.init(&game, "Daniel"),
//         try scatty.Player.init(&game, "Reese"),
//         try scatty.Player.init(&game, "Kade"),
//         try scatty.Player.init(&game, "Stephan"),
//     };
//
//     for (&players_joining) |player| try game.table.join(player);
//
//     var round = try game.start();
//     defer game.end(&round);
//
//     const players = try game.table.players(dba.allocator());
//     defer dba.allocator().free(players);
//
//     for (0..game.opts.num_rounds) |_| {
//
//         print("Round {d} =====================================================\n\n", .{round.num + 1});
//         defer round.new();
//
//         // Collect Answers
//         for (players) |player| {
//             for (0..round.categories.items.len) |index| {
//                 round.record_answer(@intCast(index), player.id, "test answer");
//             }
//         }
//
//         // Print Categories
//         for (round.categories.items, 0..) |category, index| {
//             print("{d}) {s}\n", .{ index + 1, category });
//         } else print("\n", .{});
//
//         for (round.categories.items, 0..) |category, index| {
//             defer round.voting.new();
//             defer print("\n", .{});
//
//             for (players) |sender| {
//                 for (players) |receipient| {
//                     if (sender.id == receipient.id) continue;
//                     const roll = std.crypto.random.uintLessThan(u8, 100);
//                     const vote = roll >= 10;
//                     round.cast_vote(sender.id, receipient.id, vote);
//                 }
//             }
//
//             print("{d}. {s}\n", .{ index + 1, category });
//             for (players) |player| {
//                 const balance = round.voting.balance(player.id) orelse continue;
//                 if (balance >= 0) {
//                     print("\t+{d}\t", .{balance});
//                 } else {
//                     print("\t{d}\t", .{balance});
//                 }
//
//                 const answer = round.answering.read_answer(@intCast(index), player.id) orelse continue;
//                 print("{s} - {s}\t", .{ player.username, answer });
//
//                 const counts = round.voting.counts.get(player.id) orelse continue;
//                 print("({d}/{d}) ", .{ counts.yes, counts.yes + counts.no });
//
//                 for (players) |voter| {
//                     const vote = round.voting.read_vote(player.id, voter.id) orelse continue;
//                     if (vote) {
//                         print("[{s} : yes] ", .{voter.username});
//                     } else {
//                         print("[{s} : no] ", .{voter.username});
//                     }
//                 } else print("\n", .{});
//             }
//
//             round.update_scores();
//
//             print("\t-------------\n", .{});
//             print("\tScore\tPlayer\n", .{});
//             print("\t-------------\n", .{});
//             for (players) |player| {
//                 const score = round.scores.get(player.id) orelse continue;
//                 print("\t{d}\t{s}\n", .{ score, player.username });
//             }
//         }
//     }
// }
