const std = @import("std");
const reasonable_actions = @import("reasonable_actions");
const scatty = @import("scatty.zig");

pub fn main() !void {
    var dba = std.heap.DebugAllocator(.{}){};
    defer _ = dba.deinit();

    var game = try scatty.Game.init(dba.allocator(), .{});
    defer game.deinit();

    var players = [_]scatty.Player{
        try scatty.Player.init(&game, "Gabe"),
        try scatty.Player.init(&game, "Michael"),
        try scatty.Player.init(&game, "Daniel"),
    };

    for (&players) |player| try game.table.join(player);

    var round = try game.start();
    defer game.end(&round);

    std.debug.print("Table:\n", .{});
    for (game.table.seats, 0..) |seat, num| {
        if (seat) |player| {
            std.debug.print("\t{d}\t{d}\t:\t{s}\n", .{ num, player.id, player.username });
        } else std.debug.print("\t{d}\t--\t:\t-- --\n", .{num});
    }

    for (0..10) |_| {
        for (0..game.opts.num_categories) |num| {
            var turn = game.table.iterate();
            while (turn.next()) |player| {
                round.answer(@intCast(num), player.id, "Test Answer.");
            }
        }

        std.debug.print("Round {d} =========================================\n\n", .{round.num});
        std.debug.print("{s} >>> {c}\n\n", .{ game.available_letters.items, round.letter });
        for (round.categories.items, 0..) |category, num| {
            std.debug.print("{d})\t{s}\n", .{ num + 1, category });
            var turn = game.table.iterate();
            while (turn.next()) |player| {
                std.debug.print("\t - {s} : {s}\n", .{
                    player.username,
                    if (round.answering.get(@intCast(num), player.id)) |*answer| answer else "-- --",
                });
            }
        } else std.debug.print("\n", .{});

        round.new();
    }
}

// const player_limit = 8;
// const username_len_limit = 256;
// const category_len_limit = 256;
// const answer_len_limit = 256;
//
// const GameError = error {
//     UsernameTooLong,
//     AtPlayerLimit,
//     GameOver,
//     VotingOver,
// };
//
// const Player = struct {
//     game: *Game,
//     username: []const u8,
//     id: u8 = 0,
//     round: ?Round = null,
//     score: u16 = 0,
//
//     const Self = @This();
//     const CategoryBuffer = Game.CategoryBuffer;
//     const AnswerBuffer = Game.AnswerBuffer;
//
//     const Round = struct {
//         arena: std.heap.ArenaAllocator,
//         player: *Player,
//         answers: []?AnswerBuffer,
//         voting: Voting,
//         score: u16 = 0,
//
//         const Voting = struct {
//             round: *Round,
//             votes: std.AutoArrayHashMapUnmanaged(u8, bool),
//             balance: u16 = 0,
//             index: u8 = 0,
//
//             pub fn init(round: *Round) !Voting {
//                 var votes = std.AutoArrayHashMapUnmanaged(u8, bool){};
//                 try votes.ensureTotalCapacity(round.arena.allocator(), round.player.game.players().count());
//
//                 return Voting{
//                     .round = round,
//                     .votes = votes,
//                 };
//             }
//         };
//
//         pub fn init(player: *Player) !Round {
//             var arena = std.heap.ArenaAllocator.init(player.game.allocator);
//             errdefer arena.deinit();
//
//             const answers = try arena.allocator().alloc(?AnswerBuffer, player.game.opts.num_categories);
//             for (answers) |*answer| answer.* = null;
//
//             return Round{
//                 .arena = arena,
//                 .player = player,
//                 .answers = answers,
//             };
//         }
//
//         pub fn new(round: *Round) !void {
//             const player = round.player;
//             var arena = std.heap.ArenaAllocator.init(player.game.allocator);
//
//             const answers = try arena.allocator().alloc(?AnswerBuffer, player.game.opts.num_categories);
//             for (answers) |*answer| answer.* = null;
//
//             round.arena.deinit();
//             round.* = Round{
//                 .arena = arena,
//                 .player = player,
//                 .answers = answers,
//             };
//         }
//     };
//
//     pub fn init(game: *Game, username: []const u8) !Self {
//         return Player{
//             .game = game,
//             .username = try game.allocator.dupe(u8, username),
//         };
//     }
//
//     pub fn deinit(self: *Self) void {
//         if (self.round) |round| round.arena.deinit();
//         self.game.allocator.free(self.username);
//     }
//
//     pub fn join(self: *Self) !void {
//         errdefer self.deinit();
//
//         for (self.game.seats, 0..) |seat, id| {
//             if (seat == null) {
//                 self.game.seats[id] = self.*;
//                 self.id = @intCast(id);
//                 return;
//             }
//         }
//
//         return GameError.AtPlayerLimit;
//     }
//
//     pub fn kick(self: *Self) void {
//         defer self.deinit();
//
//         self.game.seats[id] = null;
//         if (self.game.seats[id]) |_| {
//             self.game.seats[id] = null;
//             if (id == self.game.host) self.game.new_host();
//         }
//     }
//
//     pub fn record_answer(self: *Self, index: usize, answer: []const u8) void {
//         if (self.round) |*round| {
//             var answer_buff = std.mem.zeroes(AnswerBuffer);
//             if (answer.len >= answer_len_limit) {
//                 @memcpy(answer_buff[0..answer_len_limit], answer[0..answer_len_limit]);
//             } else {
//                 @memcpy(answer_buff[0..answer.len], answer[0..]);
//             }
//             round.answers[index] = answer_buff;
//         }
//     }
//
//     pub fn cast_vote(self: *Self, to_id: u8, approved: bool) void {
//         if (self.game.seats[to_id]) |*recipient| {
//             recipient.receive_vote(self.id, approved);
//         }
//     }
//
//     pub fn receive_vote(self: *Self, from_id: u8, approved: bool) void {
//         if (self.game.seats[from_id] == null) return;
//
//         if (self.round) |*round| {
//             round.voting.votes.putAssumeCapacity(from_id, approved);
//             if (approved) {
//                 round.voting.balance += 1;
//             } else {
//                 round.voting.balance -= 1;
//             }
//         }
//     }
//
//     pub fn clear_votes(self: *Self) void {
//         if (self.round) |*round| {
//             round.voting.
//         }
//     }
// };
//
// const Game = struct {
//     allocator: std.mem.Allocator,
//     opts: Options,
//     seats: []?Player,
//     host: u8 = 0,
//     round: ?Round = null,
//     available_categories: std.ArrayListUnmanaged(CategoryBuffer),
//     available_letters: std.ArrayListUnmanaged(u8),
//
//     const Self = @This();
//     const CategoryBuffer = [category_len_limit:0]u8;
//     const AnswerBuffer = [answer_len_limit:0]u8;
//
//     const Round = struct {
//         arena: std.heap.ArenaAllocator,
//         game: *Game,
//         players: std.AutoArrayHashMapUnmanaged(u8, *Player),
//         num: u8,
//         categories: []CategoryBuffer,
//         letter: u8,
//
//         pub fn init(game: *Game) !Round {
//             var arena = std.heap.ArenaAllocator.init(game.allocator);
//             errdefer arena.deinit();
//
//             const categories = try arena.allocator().alloc(CategoryBuffer, game.opts.num_categories);
//             std.crypto.random.shuffle(CategoryBuffer, game.available_categories.items);
//             @memcpy(categories[0..game.opts.num_categories], game.available_categories.items[0..game.opts.num_categories]);
//
//             const letter = roll_letter: {
//                 const chosen = std.crypto.random.intRangeLessThan(usize, 0, game.available_letters.items.len);
//                 if (game.opts.repeat_categories) {
//                     break :roll_letter game.available_letters.swapRemove(chosen);
//                 } else {
//                     break :roll_letter game.available_letters.items[chosen];
//                 }
//             };
//
//             return Round{
//                 .arena = arena,
//                 .game = game,
//                 .num = 1,
//                 .categories = categories,
//                 .letter = letter,
//             };
//         }
//
//         pub fn new(round: *Round) !void {
//             const game = round.game;
//             errdefer game.end();
//
//             if (round.num >= round.game.opts.num_rounds) return GameError.GameOver;
//
//             var arena = std.heap.ArenaAllocator.init(game.allocator);
//
//             const categories = try arena.allocator().alloc(CategoryBuffer, game.opts.num_categories);
//             if (game.opts.repeat_categories) {
//                 @memcpy(categories[0..], round.categories[0..]);
//             } else {
//                 std.crypto.random.shuffle(CategoryBuffer, round.game.available_categories.items);
//                 @memcpy(categories[0..], round.game.available_categories.items[0..categories.len]);
//             }
//
//             const letter = roll_letter: {
//                 if (game.opts.repeat_categories) {
//                     if (game.available_letters.items.len == 0) game.available_letters.appendSliceAssumeCapacity(game.opts.letter_space);
//                     const chosen = std.crypto.random.intRangeLessThan(usize, 0, game.available_letters.items.len);
//                     break :roll_letter game.available_letters.swapRemove(chosen);
//                 } else {
//                     const chosen = std.crypto.random.intRangeLessThan(usize, 0, game.available_letters.items.len);
//                     break :roll_letter game.available_letters.items[chosen];
//                 }
//             };
//
//             const num = round.num + 1;
//
//             var iter = game.players();
//             while (iter.next()) |player| {
//                 if (player.round) |*player_round| {
//                     player_round.new() catch player.kick();
//                 } else player.kick();
//             }
//
//             round.arena.deinit();
//             round.* = Round{
//                 .arena = arena,
//                 .game = game,
//                 .num = num,
//                 .categories = categories,
//                 .letter = letter,
//             };
//         }
//     };
//
//     const Options = struct {
//         num_rounds: u8 = 2,
//         num_categories: u8 = 12,
//         category_source: []const u8 = default_category_source,
//         letter_space: []const u8 = default_letter_space,
//         repeat_categories: bool = true,
//         scoring_method: ScoringMethod = .majority,
//
//         const default_category_source: []const u8 = @embedFile("./assets/default_categories.txt");
//         const default_letter_space: []const u8 = "abcdefghijklmnoprstvw";
//
//         const ScoringMethod = enum { majority, punish_majority, weighed, punish_weighed };
//     };
//
//     const PlayerIterator = struct {
//         game: *Game,
//         id: usize,
//         player: ?*Player,
//
//         pub fn init(game: *Game) PlayerIterator {
//             for (0..game.seats.len) |id| {
//                 if (game.seats[id]) |*player| {
//                     return PlayerIterator{
//                         .game = game,
//                         .id = id,
//                         .player = player,
//                     };
//                 }
//             }
//
//             return PlayerIterator{
//                 .game = game,
//                 .id = game.seats.len,
//                 .player = null,
//             };
//         }
//
//         pub fn next(self: *PlayerIterator) ?*Player {
//             var next_id = self.id + 1;
//             while (next_id < self.game.seats.len) : (next_id += 1) {
//                 if (self.game.seats[next_id]) |*player| {
//                     defer self.id = next_id;
//                     defer self.player = player;
//                     return self.player;
//                 }
//             }
//
//             defer self.id = next_id;
//             defer self.player = null;
//             return self.player;
//         }
//
//         pub fn count(self: *PlayerIterator) usize {
//             self.reset();
//             defer self.reset();
//
//             var net: usize = 0;
//             while (self.next()) |_| net += 1;
//
//             return net;
//         }
//
//         pub fn reset(self: *PlayerIterator) void {
//             self.* = PlayerIterator.init(self.game);
//         }
//     };
//
//     pub fn init(allocator: std.mem.Allocator, opts: Options) !Self {
//         const seats = try allocator.alloc(?Player, player_limit);
//         for (seats) |*seat| seat.* = null;
//         errdefer allocator.free(seats);
//
//         return Self{
//             .allocator = allocator,
//             .opts = opts,
//             .seats = seats,
//             .available_categories = .{},
//             .available_letters = .{},
//         };
//     }
//
//     pub fn deinit(self: *Self) void {
//         if (self.round) |round| round.arena.deinit();
//
//         for (self.seats) |*seat| {
//             if (seat.*) |*player| player.deinit();
//         } else self.allocator.free(self.seats);
//
//         self.available_categories.deinit(self.allocator);
//         self.available_letters.deinit(self.allocator);
//     }
//
//     pub fn start(self: *Self) !void {
//         errdefer self.end();
//
//         var available_categories = std.ArrayListUnmanaged(CategoryBuffer){};
//         var category_tokenizer = std.mem.tokenizeAny(u8, self.opts.category_source, "\n");
//         while (category_tokenizer.next()) |category_tok| {
//             var category = std.mem.zeroes(CategoryBuffer);
//             if (category_tok.len >= category_len_limit) {
//                 @memcpy(category[0..category_len_limit], category_tok[0..category_len_limit]);
//             } else {
//                 @memcpy(category[0..category_tok.len], category_tok[0..]);
//             }
//             try available_categories.append(self.allocator, category);
//         }
//
//         var available_letters = std.ArrayListUnmanaged(u8){};
//         try available_letters.appendSlice(self.allocator, self.opts.letter_space);
//
//         self.available_categories = available_categories;
//         self.available_letters = available_letters;
//
//         if (self.round) |round| round.arena.deinit();
//         for (self.seats) |seat| {
//             if (seat) |*player| {
//                 if (player.round) |player_round| player_round.arena.deinit();
//             }
//         }
//
//         self.round = try Round.init(self);
//         for (self.seats) |*seat| {
//             if (seat.*) |*player| {
//                 player.round = try Player.Round.init(player);
//             }
//         }
//     }
//
//     pub fn end(self: *Self) void {
//         self.available_categories.clearRetainingCapacity();
//         self.available_letters.clearRetainingCapacity();
//
//         if (self.round) |round| {
//             round.arena.deinit();
//             self.round = null;
//         }
//
//         for (self.seats) |*seat| {
//             if (seat.*) |*player| {
//                 if (player.round) |round| {
//                     round.arena.deinit();
//                     player.round = null;
//                 }
//             }
//         }
//     }
//
//     pub fn new_host(self: *Self) void {
//         for (self.seats) |seat| {
//             if (seat) |player| {
//                 if (player.id) |id| {
//                     if (id == self.host) continue;
//                     self.host = id;
//                     return;
//                 } else continue;
//             } else continue;
//         } else self.host = 0;
//     }
//
//     pub fn players(self: *Self) PlayerIterator {
//         return PlayerIterator.init(self);
//     }
// };
//
// pub fn main() !void {
//     var dba = std.heap.DebugAllocator(.{}).init;
//     defer _ = dba.deinit();
//
//     var game = try Game.init(dba.allocator(), .{});
//     defer game.deinit();
//
//     var players = [_]Player{
//         try Player.init(&game, "Gabe"),
//         try Player.init(&game, "Mihcael"),
//         try Player.init(&game, "Kade"),
//     };
//
//     for (&players) |*player| try player.join();
//
//     try game.start();
//     if (game.round) |*round| {
//         while (true) {
//             std.debug.print("Round {d} ========================== Letter {c}\n", .{ round.num, round.letter });
//             for (round.categories, 0..) |category, index| {
//
//                 var player_it = game.players();
//                 while (player_it.next()) |player| {
//                     const has_answered = std.crypto.random.boolean();
//                     if (has_answered) {
//                         player.record_answer(index, "Test Answer");
//                     }
//                 }
//
//                 player_it.reset();
//
//                 std.debug.print("\t{d}) {s}\n", .{ index + 1, category });
//                 while (player_it.next()) |player| {
//                     if (player.round) |*player_round| {
//                         if (player_round.answers[index]) |*answer| {
//                             std.debug.print("\t\t{s} : {s}\n", .{ player.username, answer });
//                         } else std.debug.print("\t\t{s} : [No Answer]\n", .{ player.username });
//                     }
//                 }
//             } else std.debug.print("\n", .{});
//
//             round.new() catch |err| {
//                 if (err == GameError.GameOver) {
//                     std.debug.print("Game Over\n", .{});
//                     return;
//                 } else return err;
//             };
//         }
//     }
// }
