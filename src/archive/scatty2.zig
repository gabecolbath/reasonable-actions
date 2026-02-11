const std = @import("std");
const server =  @import("server.zig");
const uuid = @import("uuid");

pub const rendering = @import("rendering.zig");
pub const frontend = @import("frontend.zig");
pub const events = @import("events.zig");

const random = std.crypto.random;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const List = std.ArrayList;
const Map = std.AutoArrayHashMapUnmanaged;
const Uuid = uuid.Uuid;
const Room = server.Room;
const Member = server.Member;

const Category = []const u8;
const Answer = []const u8;
const Vote = bool;

pub const Player = struct {
    arena: ArenaAllocator,
    game: *Game,
    id: Id,
    round: Round = undefined,
    score: i16 = 0,

    pub fn init(allocator: Allocator, game: *Game) Player {
        return Player{
            .arena = ArenaAllocator.init(allocator),
            .game = game,
            .id = uuid.v7.new(),
        };
    }

    pub fn deinit(self: *Player) void {
        if (self.game.state.started) {
            self.round.deinit();
        }

        self.arena.deinit();
    }

    pub fn start(self: *Player) !void {
        if (!self.game.state.started) {
            self.round = Round.init(self.arena.allocator(), self);
            try self.round.start();
        }
    }

    pub fn restart(self: *Player) !void {
        if (self.game.state.started) self.round.deinit();
        try self.start();
    }

    pub const Id = Uuid;
    pub const Round = struct {
        arena: ArenaAllocator,
        player: *Player,
        started: bool = false,
        score: i16 = 0,
        answers: List(Answer) = .{},
        votes: List(Map(Id, Vote)) = .{},

        pub fn init(allocator: Allocator, player: *Player) Round {
            return Round{
                .arena = ArenaAllocator.init(allocator),
                .game = player.game,
                .player = player,
            };
        }

        pub fn start(self: *Round) !void {
            if (self.started) return;
            errdefer self.deinit();

            try self.answers.ensureTotalCapacity(self.arena.allocator(), self.player.game.opts.num_categories);
            try self.votes.ensureTotalCapacity(self.arena.allocator(), self.player.game.opts.num_categories);

            for (self.answers.items) |_| self.answers.appendAssumeCapacity(null);
            for (self.votes.items) |_| self.votes.appendAssumeCapacity(Map(Id, Vote));

            self.started = true;
        }

        pub fn next(self: *Round) !void {
            if (self.started) {
                try self.reset();
            } else try self.start();
        }

        pub fn reset(self: *Round) !void {
            errdefer self.deinit();

            try self.answers.clearAndFree(self.arena.allocator());
            try self.votes.clearAndFree(self.arena.allocator());
            _ = self.arena.reset(.retain_capacity);

            try self.answers.ensureTotalCapacity(self.arena.allocator(), self.player.game.opts.num_categories);
            try self.votes.ensureTotalCapacity(self.arena.allocator(), self.player.game.opts.num_categories);

            for (self.answers.items) |_| self.answers.appendAssumeCapacity(null);
            for (self.votes.items) |_| self.votes.appendAssumeCapacity(Map(Id, Vote));

            self.player.score += self.score;
            self.score = 0;
        }

        pub fn deinit(self: *Round) void {
            self.answers.deinit(self.arena.allocator());
            self.votes.deinit(self.arena.allocator());
            self.arena.deinit();
        }

    };
};

pub const Game = struct {
    arena: ArenaAllocator,
    round: Round = undefined,
    players: Map(Player.Id, *Player) = .{},
    state: State = .{},
    opts: Options = .{},

    pub fn init(allocator: Allocator, opts: Options) Game {
        return Game{
            .arena = ArenaAllocator.init(allocator),
            .opts = opts,
        };
    }

    pub fn deinit(self: *Game) void {
        if (self.state.started) {
            self.round.deinit();
        }

        for (self.players.values()) |player| player.deinit();
        self.arena.deinit();
    }

    pub fn start(self: *Game) !void {
        if (!self.state.started) {
            self.round = try Round.init(self.arena.allocator(), self);
            try self.round.start();
            self.state.started = true;
        }

        for (self.players.values()) |player| try player.start();
    }

    pub fn restart(self: *Game) !void {
        if (self.state.started) {
            self.round.deinit();
            self.state.started = false;
            self.start();
        }

        for (self.players.values()) |player| try player.restart();
    }

    pub const State = struct {
        started: bool = false,
        scene: Scene = .lobby,

        pub const Scene = union(enum) {
            lobby,
            answer,
            vote: struct { category: u8 = 0 },
            score,
        };
    };

    pub const Options = struct {
        num_rounds: u8 = 2,
        num_categories: u8 = 12,
        category_source: []const u8 = @embedFile("./assets/default_categories.txt"),
        letter_space: []const u8 = "abcdefghijklmnoprstw",
        repeat_categories: bool = true,
        scoring_method: ScoringMethod = .fair_majority,

        const ScoringMethod = enum {
            fair_majority,
            punish_majority,
            fair_weighed,
            punish_weighed,
            by_count,
        };
    };

    pub const Round = struct {
        arena: ArenaAllocator,
        game: *Game,
        started: bool = false,
        num: u8 = 0,
        available_categories: List(Category) = .{},
        available_letters: List(u8) = .{},
        letter: u8 = 0,
        categories: List(Category) = .{},

        pub fn init(allocator: Allocator, game: *Game) Round {
            return Round{
                .arena = ArenaAllocator.init(allocator),
                .game = game,
            };
        }

        pub fn deinit(self: *Round) void {
            self.available_categories.deinit(self.arena.allocator());
            self.available_letters.deinit(self.arena.allocator());
            self.categories.deinit(self.arena.allocator());
            self.arena.deinit();

            for (self.game.players.values()) |player| {
                player.round.deinit();
            }
        }

        pub fn start(self: *Round) !void {
            if (self.started) return;
            errdefer self.deinit();

            try self.available_letters.appendSlice(self.arena.allocator(), self.game.opts.letter_space);
            self.letter = if (self.game.opts.repeat_categories) without_replacement: {
                const choice = random.uintLessThan(usize, self.available_letters.items.len);
                break :without_replacement self.available_letters.swapRemove(choice);
            } else with_replacement: {
                const choice = random.uintLessThan(usize, self.available_letters.items.len);
                break :with_replacement self.available_letters.items[choice];
            };

            var category_tok = std.mem.tokenizeAny(u8, self.game.opts.category_source, "\n");
            while (category_tok.next()) |category|
                self.available_categories.append(self.arena.allocator(), category) catch continue;
            random.shuffle(Category, self.available_categories.items);
            try self.categories.appendSlice(self.arena.allocator(), self.available_categories.items[0..self.game.opts.num_categories]);


            self.num += 1;
            self.started = true;
        }

        pub fn next(self: *Round) !void {
            errdefer self.deinit();

            if (self.started) {
                try self.reset();
            } else try self.start();

            for (self.game.players.values()) |player| {
                try player.round.next();
            }
        }

        pub fn reset(self: *Round) !void {
            errdefer self.deinit();

            self.letter = if (self.game.opts.repeat_categories) without_replacement: {
                if (self.available_letters.items.len == 0) self.available_letters.appendSliceAssumeCapacity(self.game.opts.letter_space);
                const choice = random.uintLessThan(usize, self.available_letters.items.len);
                break :without_replacement self.available_letters.swapRemove(choice);
            } else with_replacement: {
                const choice = random.uintLessThan(usize, self.available_letters.items.len);
                break :with_replacement self.available_letters.items[choice];
            };

            if (!self.game.opts.repeat_categories) {
                self.categories.clearRetainingCapacity();
                random.shuffle(Category, self.available_categories.items);
                self.categories.appendSliceAssumeCapacity(self.available_categories.items[0..self.game.opts.num_categories]);
            }
        }
    };

};
