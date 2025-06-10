const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz"); 
const game = @import("game.zig");
const mustache = @import("mustache");
const conf = @import("config.zig");
const server = @import("server.zig");

const websocket = httpz.websocket;
const json = std.json;

const CommandError = error {
    InvalidJson,
    InvalidParameters,
    InvalidOptionValue,
    UnknownCmd,
    UnknownParameter,
    MissingCmd,
    MissingParameters,
    MissingParametersType,
};

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const App = server.Application;
const Connection = server.Connection;
const CommandMap = std.StaticStringMap(Command);
const OptionMap = std.StaticStringMap(SetOption);
const ParameterMap = std.StaticStringMap(type);
const Room = server.Room;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;
const GameState = game.GameState;
const GameOptions = game.GameOptions;

const Command = *const fn (arena: Allocator, conn: *Connection, parameters: ?json.Value) anyerror!void;
const SetOption = *const fn (arena: Allocator, opts: *GameOptions, raw_value: ParsedOptionValue) anyerror!void;

pub const ParsedOptionValue = union(enum) {
    num: u32,
    label: []const u8,
    cond: []const u8,
};

const opt_map = OptionMap.initComptime(.{
    .{ "rounds", setRoundsOption },
    .{ "categoriesPerRoundOption", setCategoriesPerRoundOption },
    .{ "repeatCategoriesPerRoundOption", setRepeatCategoriesPerRoundOption },
    .{ "answeringTimeLimitOption", setAnsweringTimeLimitOption },
    .{ "enableVotingTimeLimitOption", setEnableVotingTimeLimitOption },
    .{ "votingTimeLimitOption", setVotingTimeLimitOption },
    .{ "alliterationPointsOption", setAlliterationPointsOption },
    .{ "scoringModeOption", setScoringModeOption },
    .{ "weightedScoresOption", setWeightedScoresOption },
});

const cmd_map = CommandMap.initComptime(.{
    "roundsOption",
    "categoriesPerRoundOption",
    "repeatCategoriesPerRoundOption",
    "answeringTimeLimitOption",
    "enableVotingTimeLimitOption",
    "votingTimeLimitOption",
});

pub fn valueOfNumOption(IntType: type, raw_val: ParsedOptionValue) !IntType {
    switch (raw_val) {
        .num => |val| {
            if (val < std.math.maxInt(IntType)) {
                return @intCast(val);
            } else return CommandError.InvalidOptionValue;
        },
        else => return CommandError.InvalidOptionValue,
    }
}

pub fn valueOfLabelType(Label: type, raw_val: ParsedOptionValue) !IntType {

}

pub fn setRoundsOption(_: Allocator, conn: *Connection, raw_val: ParsedOptionValue) !void {
    const game_state = conn.game_state orelse return server.ServerError.NoActiveGame;
    switch (raw_val) {
        .num => |val| {
            if (val < std.math.maxInt(@TypeOf(game_state.opts.rounds))) {
                game_state.opts.rounds = val;
            } else return CommandError.InvalidOptionValue;
        },
        else => return CommandError.InvalidOptionValue,
    }
}
pub fn setCategoriesPerRoundOption(_: Allocator, conn: *Connection, raw_val: ParsedOptionValue) !void {
    const game_state = conn.game_state orelse server.ServerError.NoActiveGame;
    switch (raw_val) {
        .num => |val| {
            if (val < std.math.maxInt(@TypeOf(game_state.opts.categories_per_round))) {
                game_state.opts.categories_per_round = val;
            } else return CommandError.InvalidOptionValue;
        },
        else => return CommandError.InvalidOptionValue,
    }
}
pub fn setRepeatCategoriesPerRoundOption(arena: Allocator, conn: *Connection, _: ?json.Value) !void {

}
pub fn setAnsweringTimeLimitOption(arena: Allocator, conn: *Connection, _: ?json.Value) !void {

}
pub fn setEnableVotingTimeLimitOption(arena: Allocator, conn: *Connection, _: ?json.Value) !void {

}
pub fn setVotingTimeLimitOption(arena: Allocator, conn: *Connection, _: ?json.Value) !void {

}
pub fn setAlliterationPointsOption(arena: Allocator, conn: *Connection, _: ?json.Value) !void {

}
pub fn setScoringModeOption(arena: Allocator, conn: *Connection, _: ?json.Value) !void {

}
pub fn setWeightedScoresOption(arena: Allocator, conn: *Connection, _: ?json.Value) !void {

}
