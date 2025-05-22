const std = @import("std");
const cat = @import("categories.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const MultArrayList = std.MultiArrayList;

const MAX_PLAYERS_PER_GAME = 8;
const VALID_LETTERS = "ABCDEFGHIJKLMNOPRSTW";

const PlayerError = error {
    AtPlayerCapacity,  
    LastPlayerRemoved,
    PlayerNotFound,
};

const GameState = enum {
    lobby,
    answering,
    voting,
    winner,
};

const GameOptions = struct {
    answering_time_limit: u16 = 120,
    bonus_time_for_last_answer: bool = false,
    challenges_time_limit: ?u8 = null,
    num_categories: u8 = 12,
    num_rounds: u8 = 3,
    points_weighted_by_vote: bool = false,
    same_categories_per_round: bool = false,
    show_names_in_vote: bool = false,
    vote_time_limit: ?u8 = null,

    var default_builtin_lists: [1][]const u8 = .{ "base" };
};

const Player = struct {
    id: u8,
    name: []const u8,
    is_active: bool,
    overall_score: u32,
    round_score: u32,
    round_answers: ?[][]const u8,
};

const Game = struct {
    arena: ArenaAllocator,
    allocator: Allocator,
    opts: GameOptions,  
    state: GameState,
    category_master_list: ArrayList([]const u8),
    round: Round,
    players: MultArrayList(Player),
    player_count: usize,
    letter_buffer: ArrayList(u8),

    const Self = @This();
    const Round = struct {
        allocator: Allocator,
        id: u8,
        letter: u8,
        categories: [][]const u8,
    };

    pub fn init(allocator: Allocator, room_creator_name: []const u8, lists: struct { builtin: []const []const u8, custom: ?[]const u8 }, opts: GameOptions) !Self {
        var arena = ArenaAllocator.init(allocator);

        var master_list = ArrayList([]const u8).init(allocator);
        try cat.loadCategoriesFromFile("base", &master_list, arena.allocator());
        for (lists.builtin) |listname| {
            cat.loadCategoriesFromFile(listname, &master_list, arena.allocator()) catch |err| {
                std.debug.print("Unable to load {s} list: {}\n", .{listname, err});
            };
        }
        if (lists.custom) |list| {
            cat.loadCategoriesFromStr(list, &master_list) catch |err| {
                std.debug.print("Unable to load custom list: {}\n", .{err});
            };
        }

        var players = MultArrayList(Player){};
        try players.setCapacity(arena.allocator(), MAX_PLAYERS_PER_GAME);

        var letter_list = ArrayList(u8).init(arena.allocator());
        try letter_list.appendSlice(VALID_LETTERS);
        

        var self = Self{
            .arena = arena,
            .allocator = arena.allocator(),
            .opts = opts,
            .state = .lobby,
            .category_master_list = master_list,
            .round = undefined,
            .players = players,
            .player_count = 0,
            .letter_buffer = letter_list,
        };

        try self.newPlayer(room_creator_name);
        try self.newRound(self.allocator);
        
        return self;
    }

    pub fn deinit(self: *Self) void {
        // self.players.deinit(self.allocator);
        self.category_master_list.deinit();
        self.letter_buffer.deinit();
        self.arena.deinit();
    }

    pub fn newRound(self: *Self, allocator: Allocator) !void {
        const rand_letter = gen_letter: { 
            if (self.opts.same_categories_per_round) {
                if (self.letter_buffer.items.len == 0) {
                    try self.resetLetterBuffer();
                }

                break :gen_letter cat.chooseRandomLetterDynamic(&self.letter_buffer);
            } else {
                break :gen_letter cat.chooseRandomLetterStatic(&self.letter_buffer);
            }
        };

        self.round = Round{
            .allocator = allocator,
            .id = 0,
            .letter = rand_letter,
            .categories = try cat.chooseRandomCategories(self.opts.num_categories, &self.category_master_list, allocator),
        };
    }

    pub fn freeRoundData(self: *Self) void {
        self.round.allocator.free(self.round.categories);
    }

    pub fn nextRound(self: *Self) !void {
        if (!self.opts.same_categories_per_round) {
            self.round.allocator.free(self.round.categories);
            self.round.categories = try cat.chooseRandomCategories(self.opts.num_categories, &self.category_master_list, self.round.allocator);
        }

        const rand_letter = gen_letter: { 
            if (self.opts.same_categories_per_round) {
                if (self.letter_buffer.items.len == 0) {
                    try self.resetLetterBuffer();
                }

                break :gen_letter cat.chooseRandomLetterDynamic(&self.letter_buffer);
            } else {
                break :gen_letter cat.chooseRandomLetterStatic(&self.letter_buffer);
            }
        };

        self.round.id += 1;
        self.round.letter = rand_letter;
    }
    
    pub fn resetRound(self: *Self) !void {
        self.freeRoundData();
        try self.newRound(self.round.allocator);
    }

    pub fn newPlayer(self: *Self, name: []const u8) !void {
        const active = self.state == .lobby;

        if (self.players.len < MAX_PLAYERS_PER_GAME) {
            defer self.player_count += 1;
            self.players.appendAssumeCapacity(Player{
                .id = @intCast(self.player_count),
                .name = name,
                .is_active = active,
                .overall_score = 0,
                .round_score = 0,
                .round_answers = null,
            });
        } else return PlayerError.AtPlayerCapacity;
    }

    pub fn removePlayer(self: *Self, id: u8) !void {
        const index_of_player_to_remove: usize = find_player: for (0..self.players.len) |index| {
            if (self.players.items(.id)[index] == id) {
                break :find_player index;
            }
        } else return PlayerError.PlayerNotFound;

        self.players.swapRemove(index_of_player_to_remove);
        
        if (self.players.len == 0) {
            return PlayerError.LastPlayerRemoved;
        }
    }

    pub fn resetLetterBuffer(self: *Self) !void {
        self.letter_buffer.clearAndFree();
        try self.letter_buffer.appendSlice(VALID_LETTERS);
        
    }
};

test "Generate Rounds For A Game" {
    std.debug.print("Test 1) Generate Rounds For A Game\n\n", .{});
    defer std.debug.print("--------------------------------------------------------\n\n\n", .{});

    const custom: []const u8 = "CUSTOM CATEGORY\n" ** 30;

    var test_game = try Game.init(std.testing.allocator, "Host Player", .{
        .builtin = &.{},
        .custom = custom,
    }, .{
        .same_categories_per_round = true,
    });
    defer test_game.deinit();

    for (0..30) |_| {
        std.debug.print("Round {d}: \n", .{ test_game.round.id });
        std.debug.print("{c}\n", .{test_game.round.letter});
        for (test_game.round.categories, 0..) |category, count| {
            std.debug.print("\t{d}. {s}\n", .{ count + 1, category });
        }

        try test_game.nextRound();
    }
}

test "Generate a Game with Players" {
    std.debug.print("Test 2) Generate a Game with Players\n\n", .{});
    defer std.debug.print("--------------------------------------------------------\n\n\n", .{});

    var test_game = try Game.init(std.testing.allocator, "Gabe", .{
        .builtin = &.{},
        .custom = null,
    }, .{});
    defer test_game.deinit();

    try test_game.newPlayer("Michael");
    try test_game.newPlayer("Reese");
    try test_game.newPlayer("Kade");
    try test_game.newPlayer("Dan");
    try test_game.newPlayer("Bobby");

    std.debug.print("Player List:\n", .{});
    for (0..test_game.players.len) |index| {
        const player = test_game.players.get(index);
        std.debug.print("\t{d}. {s}\n", .{ player.id, player.name });
    }

    try test_game.removePlayer(3);
    std.debug.print("Kade Left...\n\n", .{});
    std.debug.print("Updated Player List:\n", .{});
    for (0..test_game.players.len) |index| {
        const player = test_game.players.get(index);
        std.debug.print("\t{d}. {s}\n", .{ player.id, player.name });
    }
}
