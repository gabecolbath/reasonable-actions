const std = @import("std");
const reasonable_actions = @import("reasonable_actions");

const player_limit = 8;
const username_len_limit = 256;
const category_len_limit = 256;
const answer_len_limit = 256;

const GameError = error {
    UsernameTooLong,
};

const Player = struct {
    game: *Game,
    username: []const u8,
    round: ?Round = null,
    score: u16 = 0,

    const Self = @This();
    const CategoryBuffer = Game.CategoryBuffer;
    const AnswerBuffer = Game.AnswerBuffer;
    const Round = struct {
        arena: std.heap.ArenaAllocator,
        answers: []?AnswerBuffer,
        score: u16 = 0,
    };

    pub fn init(game: *Game, username: []const u8) !Self {
        return Player{
            .game = game,
            .username = try game.allocator.dupe(u8, username),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.round) |round| round.arena.deinit();
        self.game.allocator.free(self.username);
    }
};

const Game = struct {
    allocator: std.mem.Allocator,
    opts: Options,
    seats: std.ArrayListUnmanaged(Player),
    round: ?Round = null,

    const Self = @This();
    const CategoryBuffer = [category_len_limit:0]u8;
    const AnswerBuffer = [answer_len_limit:0]u8;

    const Round = struct {
        arena: std.heap.ArenaAllocator,
        num: u8,
        categories: []CategoryBuffer,
    };

    const Options = struct {
        num_categories: u8 = 12,
    };

    pub fn init(self: *Self, opts: Options) !Self {

    }
};

pub fn main() !void {

}


