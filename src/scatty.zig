const std = @import("std");
const reasonable_actions = @import("reasonable_actions");
const random = std.crypto.random;

pub const player_limit = 8;
pub const available_category_limit = 256;
pub const username_len_limit = 256;
pub const category_len_limit = 256;
pub const answer_len_limit = 256;

pub const Username = [username_len_limit:0]u8;
pub const Category = [category_len_limit:0]u8;
pub const Answer = [answer_len_limit:0]u8;
pub const Vote = bool;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const List = std.ArrayList;
const Map = std.AutoArrayHashMapUnmanaged;

pub const GameError = error {
    UsernameTooLong,
    AtPlayerLimit,
};

pub const Player = struct {
    game: *Game,
    username: Username,
    id: u8 = inactive_id,
    score: i16 = 0,

    pub fn init(game: *Game, name: []const u8) !Player {
        const username = if (name.len < username_len_limit) save_username: {
            var username = std.mem.zeroes(Username);
            @memcpy(username[0..name.len], name[0..]);
            break :save_username username;
        } else return GameError.UsernameTooLong;

        return Player{
            .game = game,
            .username = username,
        };
    }

    pub fn rename(self: *Player, new_name: []const u8) !void {
        if (new_name.len < username_len_limit) {
            self.username = std.mem.zeroes(Username);
            @memcpy(self.username[0..new_name.len], new_name[0..]);
        } else return GameError.UsernameTooLong;
    }

    const inactive_id = player_limit;
};

pub const Game = struct {
    allocator: Allocator,
    opts: Options,
    table: *Table,
    available_categories: List(Category),
    available_letters: List(u8),

    pub fn init(allocator: Allocator, opts: Options) !Game {
        const table = try allocator.create(Table);
        table.* = Table.init(allocator);
        errdefer table.deinit();
        errdefer allocator.destroy(table);

        var available_categories = try List(Category).initCapacity(allocator, available_category_limit);
        errdefer available_categories.deinit(allocator);

        var available_letters = try List(u8).initCapacity(allocator, 26);
        errdefer available_letters.deinit(allocator);

        return Game{
            .allocator = allocator,
            .opts = opts,
            .table = table,
            .available_categories = available_categories,
            .available_letters = available_letters,
        };
    }

    pub fn deinit(self: *Game) void {
        self.table.deinit();
        self.allocator.destroy(self.table);
        self.available_categories.deinit(self.allocator);
        self.available_letters.deinit(self.allocator);
    }

    pub fn start(self: *Game) !Round {
        var tok = std.mem.tokenizeAny(u8, self.opts.category_source, "\n");
        while (tok.next()) |category| {
            if (self.available_categories.items.len < available_category_limit) {
                if (category.len < category_len_limit) {
                    var buf = std.mem.zeroes(Category);
                    @memcpy(buf[0..category.len], category[0..]);

                    self.available_categories.appendAssumeCapacity(buf);
                } else continue;
            } else break;
        }

        self.available_letters.appendSliceAssumeCapacity(self.opts.letter_space);

        return Round.init(self);
    }

    pub fn end(self: *Game, round: *Round) void {
        round.arena.deinit();
        self.available_categories.clearRetainingCapacity();
        self.available_letters.clearRetainingCapacity();
    }

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
        game: *Game,
        arena: ArenaAllocator,
        categories: List(Category),
        letter: u8,
        scores: Map(u8, i16),
        answering: Answering,
        voting: Voting,
        num: u8 = 0,

        pub fn init(game: *Game) !Round {
            var arena = ArenaAllocator.init(game.allocator);
            errdefer arena.deinit();

            const roll = random.uintLessThan(usize, game.available_letters.items.len);
            const letter = if (game.opts.repeat_categories) without_replacement: {
                break :without_replacement game.available_letters.swapRemove(roll);
            } else with_replacement: {
                break :with_replacement game.available_letters.items[roll];
            };

            var categories = List(Category){};
            var answers = List(Map(u8, Answer)){};
            var scores = Map(u8, i16){};
            var results = Map(u8, Map(u8, Vote)){};
            var counts = Map(u8, Voting.Counts){};

            try categories.ensureTotalCapacity(arena.allocator(), game.opts.num_categories);
            try answers.ensureTotalCapacity(arena.allocator(), game.opts.num_categories);
            try scores.ensureTotalCapacity(arena.allocator(), game.table.size());
            try results.ensureTotalCapacity(arena.allocator(), game.table.size());
            try counts.ensureTotalCapacity(arena.allocator(), game.table.size());

            random.shuffle(Category, game.available_categories.items);
            categories.appendSliceAssumeCapacity(game.available_categories.items[0..game.opts.num_categories]);

            for (0..game.opts.num_categories) |_| {
                var answer_map = Map(u8, Answer){};
                try answer_map.ensureTotalCapacity(arena.allocator(), game.table.size());
                answers.appendAssumeCapacity(answer_map);
            }

            var table = game.table.iterate();
            while (table.next()) |player| {
                var vote_map = Map(u8, Vote){};
                try vote_map.ensureTotalCapacity(arena.allocator(), game.table.size());
                results.putAssumeCapacity(player.id, vote_map);
                scores.putAssumeCapacity(player.id, 0);
                counts.putAssumeCapacity(player.id, .{});
            }

            return Round{
                .game = game,
                .arena = arena,
                .categories = categories,
                .letter = letter,
                .scores = scores,
                .answering = Answering{ .answers = answers },
                .voting = Voting{ .results = results, .counts = counts },
            };
        }

        pub fn update_scores(self: *Round) void {
            var table = self.game.table.iterate();
            while (table.next()) |player| {
                const counts = self.voting.counts.get(player.id) orelse continue;
                const score = self.scores.getPtr(player.id) orelse continue;
                const balance = @as(i16, counts.yes) - @as(i16, counts.no);

                switch (self.game.opts.scoring_method) {
                    .fair_majority   => score.* += if (balance >= 0) 1 else 0,
                    .fair_weighed    => score.* += if (balance >= 0) balance else 0,
                    .punish_majority => score.* += if (balance >= 0) 1 else -1,
                    .punish_weighed  => score.* += balance,
                    .by_count        => score.* += counts.yes,
                }
            }
        }

        pub fn record_answer(self: *Round, category: u8, id: u8, answer: []const u8) void {
            if (answer.len < answer_len_limit) {
                var buf = std.mem.zeroes(Answer);
                @memcpy(buf[0..answer.len], answer[0..]);
                self.answering.answers.items[category].putAssumeCapacity(id, buf);
            } else return;
        }

        pub fn cast_vote(self: *Round, sender: u8, receipient: u8, approved: Vote) void {
            var votes = self.voting.results.getPtr(receipient) orelse return;
            votes.putAssumeCapacity(sender, approved);

            const counts = self.voting.counts.getPtr(receipient) orelse return;
            if (approved) {
                counts.yes += 1;
            } else {
                counts.no += 1;
            }
        }

        pub fn new(self: *Round) void {
            var scorers = self.game.table.iterate();
            while (scorers.next()) |player| {
                const round_score = self.scores.get(player.id) orelse continue;
                player.score += round_score;
            }

            self.reset_categories();
            self.reset_letter();
            self.reset_scores();

            self.answering.new();
            self.voting.new();

            self.num += 1;
        }

        fn reset_categories(self: *Round) void {
            if (!self.game.opts.repeat_categories or self.num == 0) {
                self.categories.clearRetainingCapacity();
                random.shuffle(Category, self.game.available_categories.items);
                self.categories.appendSliceAssumeCapacity(self.game.available_categories.items[0..self.game.opts.num_categories]);
            }
        }

        fn reset_letter(self: *Round) void {
            if (self.game.available_letters.items.len == 0) {
                self.game.available_letters.appendSliceAssumeCapacity(self.game.opts.letter_space);
            }

            const roll = random.uintLessThan(usize, self.game.available_letters.items.len);
            self.letter = if (self.game.opts.repeat_categories) without_replacement: {
                break :without_replacement self.game.available_letters.swapRemove(roll);
            } else with_replacement: {
                break :with_replacement self.game.available_letters.items[roll];
            };
        }

        fn reset_scores(self: *Round) void {
            self.update_scores();
            self.scores.clearRetainingCapacity();
            var table = self.game.table.iterate();
            while (table.next()) |player| {
                self.scores.putAssumeCapacity(player.id, 0);
            }
        }

        pub const Answering = struct {
            answers: List(Map(u8, Answer)),

            pub fn new(self: *Answering) void {
                for (0..self.answers.items.len) |category| {
                    self.answers.items[category].clearRetainingCapacity();
                }
            }

            pub fn read_answer(self: *Answering, category: u8, id: u8) ?Answer {
                return self.answers.items[category].get(id);
            }
        };

        pub const Voting = struct {
            results: Map(u8, Map(u8, Vote)),
            counts: Map(u8, Counts),
            category: u8 = 0,

            pub fn new(self: *Voting) void {
                for (self.results.keys()) |id| {
                    const votes = self.results.getPtr(id) orelse continue;
                    votes.clearRetainingCapacity();
                }

                for (self.counts.keys()) |id| {
                    const count = self.counts.getPtr(id) orelse continue;
                    count.* = .{};
                }

                self.category += 1;
            }

            pub fn balance(self: *Voting, id: u8) ?i16 {
                const counts = self.counts.get(id) orelse return null;
                return @as(i16, counts.yes) - @as(i16, counts.no);
            }

            pub fn read_vote(self: *Voting, receipient: u8, sender: u8) ?Vote {
                const results = self.results.get(receipient) orelse return null;
                return results.get(sender);
            }

            pub fn read_counts(self: *Voting, id: u8) ?Counts {
                return self.counts.get(id);
            }

            pub const Counts = struct {
                yes: u8 = 0,
                no: u8 = 0,
            };
        };
    };
};

pub const Table = struct {
    arena: ArenaAllocator,
    seats: [player_limit]?*Player,
    host: u8 = 0,
    count: usize = 0,

    pub fn init(allocator: Allocator) Table {
        var seats: [player_limit]?*Player = undefined;
        for (0..seats.len) |id| seats[id] = null;

        return Table{
            .arena = ArenaAllocator.init(allocator),
            .seats = seats,
        };
    }

    pub fn deinit(self: *Table) void {
        self.arena.deinit();
    }

    pub fn join(self: *Table, joining: Player) !void {
        for (0..self.seats.len) |id| {
            if (self.seats[id] == null) {
                defer self.count += 1;

                const new_player = try self.arena.allocator().create(Player);
                new_player.* = joining;
                new_player.id = @intCast(id);

                self.seats[id] = new_player;
                return;
            } else continue;
        } else return GameError.AtPlayerLimit;
    }

    pub fn kick(self: *Table, id: u8) void {
        if (self.seats[id]) |kicking| {
            defer self.count -= 1;
            defer self.arena.allocator().destroy(kicking);
            self.seats[id] = null;
        }
    }

    pub fn player(self: *Table, id: u8) ?*Player {
        return self.seats[id];
    }

    pub fn size(self: *Table) usize {
        return self.seats.len;
    }

    pub fn iterate(self: *Table) Iterator {
        return Iterator.init(self);
    }

    pub fn players(self: *Table, allocator: Allocator) ![]*Player {
        var list = List(*Player){};
        try list.ensureTotalCapacity(allocator, self.seats.len);

        for (0..self.seats.len) |id| {
            if (self.seats[id]) |active_player| {
                list.appendAssumeCapacity(active_player);
            }
        }

        return list.toOwnedSlice(allocator);
    }

    pub const Iterator = struct {
        seats: [player_limit]?*Player,
        player: ?*Player = null,
        seat: usize = 0,

        pub fn init(table: *Table) Iterator {
            var iter = Iterator{ .seats = table.seats };

            for (0..iter.seats.len) |seat| {
                if (iter.seats[seat]) |first_player| {
                    iter.player = first_player;
                    iter.seat = seat;
                    return iter;
                }
            }

            iter.player = null;
            iter.seat = iter.seats.len;
            return iter;
        }

        pub fn next(self: *Iterator) ?*Player {
            self.seat += 1;
            if (self.seat < self.seats.len) {
                for (self.seat..self.seats.len) |seat| {
                    if (self.seats[seat]) |next_player| {
                        defer self.player = next_player;
                        defer self.seat = seat;
                        return self.player;
                    }
                }

                defer self.player = null;
                defer self.seat = self.seats.len;
                return self.player;
            }

            defer self.player = null;
            defer self.seat = self.seats.len;
            return self.player;
        }

        pub fn reset(self: *Iterator) void {
            for (0..self.seats.len) |seat| {
                if (self.seats[self.seat]) |first_player| {
                    self.player = first_player;
                    self.seat = seat;
                    return;
                }
            }

            self.player = null;
            self.seat = self.seats.len;
        }
    };
};
