const std = @import("std");
const cat = @import("category.zig");
const conf = @import("config.zig");

const random = std.crypto.random;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub const PlayerError = error {
    AtPlayerCapacity,
    LastPlayerRemoved,
    PlayerNotFound,
    DuplicateName,
};

pub const Scene = enum {
    pregame,
    reviewing,
    answering,
    voting,
    winning,
};

pub const Options = struct {
    general: GeneralOptions = .{},
    voting: VotingOptions = .{},
    answering: AnsweringOptions = .{},
    scoring: ScoringOptions = .{},

    const GeneralOptions = struct {
        num_categories: u8 = 12,
        num_rounds: u8 = 3,
        same_categories_per_round: bool = true,
        list_names: []const []const u8 = &.{ "base" },
    };

    const AnsweringOptions = struct {
        pre_answering_review_time_limit: ?u8 = null,
        answering_time_limit: u16 = 120,
        bonus_time_for_last_answer: ?u8 = null,
    };
    
    const VotingOptions = struct {
        vote_time_limit: ?u8 = null,
        show_names_in_vote: bool = false,
        challenges_time_limit: ?u8 = null,
    };

    const ScoringOptions = struct {
        score_weighted_by_vote: bool = false,
    };
};

const Vote = struct {
    category_no: usize,
    player: *Player,
    score: struct {
        total_num_votes: u8 = 0,
        num_yes_votes: u8 = 0,
    },

    const Self = @This();
    
    fn updateVote(self: *Self, choice: enum { yes, no }) void {
        self.score.num_yes_votes += if (choice == .yes) 1 else 0;
        self.score.total_num_votes += 1;
    }

    fn answerOrNull(self: *const Self) ?cat.Answer {
        if (self.player.answers[self.category_no].len > 0) {
            return self.player.answers[self.category_no];
        } else {
            return null;
        }
    }

    fn isMajorityYes(self: *const Self) bool {
        const criteria = @divFloor(self.score.total_num_votes, 2);
        return self.score.num_yes_votes > criteria;
    }
};

const Round = struct {
    game_state: *State,
    no: u8,
    letter: u8,
    categories: []cat.Category,

    const Self = @This();

    pub fn init(game_state: *State, no: u8) !Self {
        const rand_letter = rand_letter: { 
            if (game_state.opts.general.same_categories_per_round) {
                break :rand_letter randLetterDynamic(game_state);
            } else {
                break :rand_letter randLetterStatic(game_state);
            }
        };

        const rand_categories = try cat.chooseRandomCategories(game_state.allocator, game_state.category_list, game_state.opts.general.num_categories);

        return Self{
            .game_state = game_state,
            .no = no,
            .letter = rand_letter,
            .categories = rand_categories,
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_state.allocator.free(self.categories);
    }

    fn randLetterStatic(game_state: *State) u8 {
        const available_letters = &game_state.letter_buffer;
        const rand = random.intRangeLessThan(usize, 0, available_letters.items.len);

        return available_letters.items[rand];
    }

    fn randLetterDynamic(game_state: *State) u8 {
        var available_letters = &game_state.letter_buffer;
        if (available_letters.items.len == 0) {
            game_state.resetLetterBuffer();
        }
        const rand = random.intRangeLessThan(usize, 0, available_letters.items.len);
        
        return available_letters.swapRemove(rand);
    }
    
    fn print(self: *Self) void {
        defer std.debug.print("\n", .{});
        std.debug.print("Round {d}\n", .{self.no});
        std.debug.print("{c}\n", .{self.letter});
        for (self.categories, 0..) |category, index| {
            std.debug.print("\t{d}. {s}\n", .{ index + 1, category });
        }
    }
};

const Player = struct {
    game_state: *State,
    total_score: u32,
    round_score: u32,
    name: []const u8,
    answers: []cat.Answer,

    const Self = @This();

    pub fn init(game_state: *State, player_name: []const u8) !Self {
        const name = try game_state.allocator.dupe(u8, player_name);

        const answers = try game_state.allocator.alloc(cat.Answer, game_state.opts.general.num_categories); 
        @memset(answers, "");

        return Self{
            .game_state = game_state,
            .total_score = 0,
            .round_score = 0,
            .name = name,
            .answers = answers,
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_state.allocator.free(self.name);
        
        for (self.answers) |answer| {
            self.game_state.allocator.free(answer);
        } else {
            self.game_state.allocator.free(self.answers);
        }
    }

    fn changeName(self: *Self, new_name: []const u8) !void {
        self.game_state.allocator.free(self.name);
        self.name = try self.game_state.allocator.dupe(u8, new_name);
    }
};

const State = struct {
    allocator: Allocator,
    opts: Options,
    round: Round,
    scene: Scene,
    players: ArrayListUnmanaged(Player),
    category_list: []cat.Category,
    categories_buffer: []const u8,
    letter_buffer: ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: Allocator, opts: Options) !Self {
        const read_category_list = try cat.readCategoryFiles(allocator, opts.general.list_names);
        const generated_category_list = try cat.toCategoryList(allocator, read_category_list);

        var available_letters = ArrayList(u8).init(allocator);
        try available_letters.appendSlice(conf.valid_letters);

        const player_list = try ArrayListUnmanaged(Player).initCapacity(allocator, conf.max_players_per_game);

        return Self{
            .allocator = allocator,
            .opts = opts,
            .round = undefined,
            .scene = .pregame,
            .players = player_list,
            .category_list = generated_category_list,
            .categories_buffer = read_category_list,
            .letter_buffer = available_letters,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.players.items) |*player| {
            player.deinit();
        }
        self.round.deinit();
        self.players.deinit(self.allocator);
        self.allocator.free(self.category_list);
        self.allocator.free(self.categories_buffer);
        self.letter_buffer.deinit();
    }

    fn addPlayer(self: *Self, name: []const u8) !void {
        if (self.players.items.len < conf.max_players_per_game) {
            for (self.players.items) |player| {
                if (std.mem.eql(u8, player.name, name)) {
                    return PlayerError.DuplicateName;
                }
            } else {
                self.players.appendAssumeCapacity(try Player.init(self, name));
            }
        } else return PlayerError.AtPlayerCapacity;
    }

    fn removePlayer(self: *Self, name: []const u8) void {
        for (self.players.items, 0..) |player, index| {
            if (std.mem.eql(u8, player.name, name)) {
                self.players.swapRemove(index);
            }
        } else {
            PlayerError.PlayerNotFound;
        }

        if (self.players.items.len == 0) {
            return PlayerError.LastPlayerRemoved;
        }
    }

    fn resetLetterBuffer(self: *Self) void {
        self.letter_buffer.clearRetainingCapacity();
        self.letter_buffer.appendSliceAssumeCapacity(conf.valid_letters);
    }

    fn generateFirstRound(self: *Self) !void {
        const first_round = try Round.init(self, 0);
        self.round = first_round;
    }

    fn generateNextRound(self: *Self) !void {
        if (self.opts.general.same_categories_per_round) {
            self.round.letter = Round.randLetterDynamic(self);
            self.round.no += 1;
        } else {
            const new_round = try Round.init(self, self.round.no + 1);
            self.round.deinit();
            self.round = new_round;
        }
    }

    fn getPlayerByName(self: *Self, name: []const u8) !*Player {
        for (self.players.items) |*player| {
            if (std.mem.eql(u8, player.name, name)) {
                return player;
            }
        } else {
            return PlayerError.PlayerNotFound;
        }
    }

    fn generateVotesForCategory(self: *Self, category_no: usize) ![]Vote {
        const players = self.players.items;
        const votes = try self.allocator.alloc(Vote, players.len);
        for (players, votes) |*player, *vote| {
            vote.* = Vote{
                .player = player,
                .category_no = category_no,
                .score = .{},
            };
        }

        return votes;
    }

    fn updateScores(self: *Self, votes: []Vote) void {
        if (self.opts.scoring.score_weighted_by_vote) {
            for (votes) |vote| {
                vote.player.round_score += vote.score.num_yes_votes;
            }
        } else {
            for (votes) |vote| {
                vote.player.round_score += if (vote.isMajorityYes()) 1 else 0;
            }
        }
    }
};

test "Generate A Game" {
    var game = try State.init(std.testing.allocator, .{
        .general = .{ .same_categories_per_round = true },
    });
    defer game.deinit();
    
    try game.generateFirstRound();

    try game.addPlayer("Gabe");
    const gabe = try game.getPlayerByName("Gabe");
    
    std.debug.print("{s} joined...\n", .{gabe.name});
    
    try gabe.changeName("Michael");
    
    std.debug.print("Gabe changed name to {s}...\n", .{gabe.name});

    game.round.print();

    for (0..10) |_| {
        try game.generateNextRound();
        game.round.print(); 
    }
}

test "Generate Votes" {
    var game = try State.init(std.testing.allocator, .{
        .general = .{
            .same_categories_per_round = true,
        }, 
        .scoring = .{ 
            .score_weighted_by_vote = false,
        },
    });
    defer game.deinit();

    try game.generateFirstRound();

    game.round.print();
    
    try game.addPlayer("Gabe");
    try game.addPlayer("Daniel");
    try game.addPlayer("Michael");
    try game.addPlayer("Kade");

    for (0..(game.players.items.len - 1)) |index| {
        var test_answer = ArrayList(u8).init(std.testing.allocator);
        try test_answer.appendSlice("Test Answer");
        game.players.items[index].answers[0] = try test_answer.toOwnedSlice();
    }
    
    const votes = try game.generateVotesForCategory(0);

    votes[0].updateVote(.yes);
    votes[1].updateVote(.no);
    votes[2].updateVote(.no);
    
    votes[0].updateVote(.yes);
    votes[1].updateVote(.yes);
    votes[2].updateVote(.no);

    std.debug.print("{s}\n", .{game.category_list[0]});
    for (votes) |*vote| {
        std.debug.print("\t{s}: {s} ({d}/{d})\n", .{
            vote.player.name,
            if (vote.answerOrNull() != null) vote.answerOrNull().? else "none",
            vote.score.num_yes_votes,
            vote.score.total_num_votes,
        });
    }

    game.updateScores(votes);
    
    std.debug.print("Scores: \n", .{});
    for (game.players.items) |player| {
        std.debug.print("\t{s}: {d}\n", .{ player.name, player.round_score });
    }

    std.testing.allocator.free(votes);
}
