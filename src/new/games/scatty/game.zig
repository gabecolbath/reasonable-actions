const std = @import("std");
const httpz = @import("httpz");
const uuid = @import("uuid");
const random = std.crypto.random;
const assert = std.debug.assert;


// std
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const List = std.ArrayList;
const Map = std.AutoArrayHashMapUnmanaged;
// uuid
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;


// ============================================================================
pub const Player = struct {

    arena: ArenaAllocator,
    game: *Game,
    round: Round,
    score: i16 = 0,

    pub fn init(allocator: Allocator, game: *Game) Self {

        // Initialize arena allocator for the player to manage players's lifetime.
        var arena = ArenaAllocator.init(allocator);

        // Initialize round.
        const round = Round.init(arena.allocator());

        // Initialize and return self.
        return Self{
            .arena = arena,
            .game = game,
            .round = round,
        };
    }

    pub fn deinit(self: *Self) void {

        // Free memory allocated by the round.
        self.round.deinit();

        // Free memory allocated by the player arena.
        self.arena.deinit();
    }

    pub fn newRound(self: *Self) void {
        // Clear memory allocated last round.
        self.round.arena.reset(.retain_capacity);

        // Reset answers and votes.
        self.round.answers = .{};
        self.round.votes = .{};

        // Initialize answers for all categories to null.
        try self.round.answers.appendNTimes(self.round.arena.allocator(), null, self.game.opts.num_categories);

        // Update player score and reset round score to 0.
        self.score += self.round.score;
        self.round.score = 0;
    }

    pub fn recordAnswer(self: *Self, cat: usize, answer: []const u8) !void {

        // Do nothing if cat is not in range.
        if (cat >= self.round.answers.capacity or cat >= self.round.answers.items.len) {
            return;
        }

        // If there is already an answer free and reset it.
        if (self.round.answers.items[cat]) |ans| {
            self.round.arena.allocator().free(ans);
            self.round.answers.items[cat] = null;
        }

        // Allocate and save the answer for the respective category.
        self.round.answers.items[cat] = try self.round.arena.allocator().dupe(u8, answer);
    }

    pub fn receiveVote(self: *Self, sender_id: Uuid, vote: bool) !void {

        // Save vote via the sender id.
        try self.round.votes.put(self.round.arena.allocator(), sender_id, vote);
    }

    // ------------------------------------------------------------------------

    const Self = @This();

    // ------------------------------------------------------------------------
    pub const Round = struct {

        arena: ArenaAllocator,
        score: i16 = 0,
        answers: List(?[]const u8) = .{},
        votes: Map(Uuid, bool),

        pub fn init(allocator: Allocator) Round {

            // Initialize arena allocator for the round to manage round's lifetime.
            const arena = ArenaAllocator.init(allocator);

            // Initialize and return round.
            return Round{ .arena = arena };
        }


        pub fn deinit(self: *Round) void {

            // Free memory of answers and votes list.
            self.answers.deinit(self.arena.allocator());
            self.votes.deinit(self.arena.allocator());

            // Free all allocated memory under the arena.
            self.arena.deinit();
        }
    };
};


// =============================================================================
pub const Game = struct {

    arena: ArenaAllocator,
    round: Round,
    players: Map(Uuid, *Player) = .{},
    opts: Options = .{},
    cached_letters: List(u8) = .{},
    cached_categories: List([]const u8) = .{},

    pub fn init(allocator: Allocator, opts: Options) Self {

        // Initialize arena allocator for the player to manage players's lifetime.
        var arena = ArenaAllocator.init(allocator);

        // Initialize round.
        const round = Round.init(arena.allocator());

        // Initialize and return self.
        return Self{
            .arena = arena,
            .round = round,
            .opts = opts,
        };
    }

    pub fn deinit(self: *Self) void {

        // Free memory allocated by the round.
        self.round.deinit();

        // Free memory allocated by the player arena.
        self.arena.deinit();
    }

    pub fn start(self: *Self) !void {

        // Cache letters.
        try self.cached_letters.ensureTotalCapacity(self.arena.allocator(), 26);
        self.cached_letters.appendSliceAssumeCapacity(self.arena.allocator(), self.opts.letter_space);

        // Cache categories.
        var token: [128]u8 = undefined;
        var tokenizer = std.mem.tokenizeAny(u8, &token, "\n");
        while (tokenizer.next()) |tok| {
            self.cached_categories.append(self.arena.allocator(), tok) catch continue;
        }
    }

    pub fn end(self: *Self) void {

        // Clear cached letters.
        self.cached_letters.clearRetainingCapacity();

        // Clear cached categories.
        self.cached_categories.clearRetainingCapacity();

        // Reset the round.
        self.round.deinit();
        self.round = Round.init(self.arena.allocator());
    }

    pub fn chooseLetter(self: *Self) u8 {

        // Assert that letters were correctly allocated.
        assert(self.cached_letters.capacity == 26);

        // If game opts are set to repeat categories choose and remove the random letter.
        if (self.opts.repeat_categories) {

            // Cache new letters if there are none left in the cache.
            if (self.cached_letters.items.len == 0) {
                self.cached_letters.appendSliceAssumeCapacity(self.opts.letter_space);
            }

            // Make random choice, swap remove, and return the chosen letter.
            const choice = random.uintLessThan(usize, self.cached_letters.items.len);
            return self.cached_letters.swapRemove(choice);

        // Other wise choose without removing the letter.
        } else {

            // Make random choice and return the chosen letter.
            const choice = random.uintLessThan(usize, self.cached_letters.items.len);
            return self.cached_letters.items[choice];
        }
    }

    pub fn chooseCategories(self: *Self) []const u8 {

        // Assert that there are enough categories to choose from.
        assert(self.cached_categories.items.len >= self.opts.num_categories);

        // Shuffle the categories and return the first optionally set number of categories.
        random.shuffle([]const u8, self.cached_categories.items);
        return self.cached_categories.items[0..self.opts.num_categories];
    }

    pub fn newRound(self: *Self) !void {
        // Clear memory allocated last round.
        self.round.arena.reset(.retain_capacity);

        // Call a new round for the players.
        for (self.players.values()) |player| {
            try player.newRound();
        }

        // Choose a new letter.
        self.round.letter = self.chooseLetter();

        // Reset categories.
        self.round.categories = self.chooseCategories();

        // Increase the round number.
        self.round.num += 1;
    }

    // -------------------------------------------------------------------------
    pub const Self = @This();

    // -------------------------------------------------------------------------
    pub const Round = struct {

        arena: ArenaAllocator,
        num: u8 = 0,
        letter: u8 = 0,
        categories: [][]const u8 = &.{},

        pub fn init(allocator: Allocator) Round {

            // Initialize arena allocator for the round to manage round's lifetime.
            const arena = ArenaAllocator.init(allocator);

            // Initialize and return round.
            return Round{ .arena = arena };
        }

        pub fn deinit(self: *Round) void {

            // Free memory of categories list.
            self.categories.deinit(self.arena.allocator());

            // Free all allocated memory under the arena.
            self.arena.deinit();
        }
    };

    // -------------------------------------------------------------------------
    pub const Options = struct {
        num_rounds: u8 = 2,
        num_categories: u8 = 12,
        letter_space: []const u8 = "abcdefghijklmnoprstw",
        category_space: []const u8 = @embedFile("assets/default_categories.txt"),
        repeat_categories: bool = true,
        scoring_method: ScoringMethod = .fair_majority,
        answering_time_limit: u8 = 120,

        const ScoringMethod = enum {
            fair_majority,
            punish_majority,
            fair_weighed,
            punish_weighed,
            by_count,
        };
    };
};
