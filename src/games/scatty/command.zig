const std = @import("std");
const uuid = @import("uuid");
const httpz = @import("httpz"); 
const scatty = @import("scatty.zig");
const mustache = @import("mustache");
const conf = @import("config.zig");
const server = @import("server.zig");
const cmd = @import("command.zig");

const websocket = httpz.websocket;
const json = std.json;

const CommandError = cmd.CommandError;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const App = server.Application;
const Connection = server.Connection;
const Command = cmd.Command;
const CommandMap = std.StaticStringMap(Command);
const ParameterMap = std.StaticStringMap(type);
const Room = server.Room;
const Uuid = uuid.Uuid;
const Urn = uuid.urn.Urn;
const Game = scatty.Game;
const GameOptions = scatty.Options;

const ParsedGameOptions = struct {
    rounds_option: NumberType = 3,
    categories_per_round_option: NumberType = 12,
    repeat_categories_option: CheckboxType = "true",
    answering_time_limit_option: NumberType = 120,
    enable_voting_time_limit_option: CheckboxType = "false",
    voting_time_limit_option: NumberType = 120,
    alliteration_points_option: CheckboxType = "true",
    scoring_mode_option: TextType = "normal",
    weighted_scores_option: CheckboxType = "false",

    const Self = @This();
    pub const NumberType = u32;
    pub const TextType = []const u8;
    pub const CheckboxType = []const u8;
};

const options_html = @embedFile("html/options.html");
pub const cmd_map = CommandMap.initComptime(.{
    .{ "initViewGame", initViewGame },
    .{ "initViewOptions", initViewOptions },
});

pub fn initViewGame(_: Allocator, conn: *Connection, _: ?json.Value) !void {
    const content = 
    \\<div id="lobby-container"
    \\    hx-swap-oob="innerHTML:#lobby-container">
    \\    <div id="options-container"
    \\        hx-vals='{ "cmd": "initViewOptions" }'
    \\        hx-trigger="load"
    \\        ws-send>
    \\        <form id="options-form" ws-send>
    \\            <div id="rounds-option-container"></div>
    \\            <div id="categories-per-round-option-container"></div>
    \\            <div id="repeat-categories-option-container"></div>
    \\            <div id="answering-time-limit-option-container"></div>
    \\            <div id="voting-time-limit-option-container"></div>
    \\            <div id="alliteration-points-option-container"></div>
    \\            <div id="scoring-mode-option-container"></div>
    \\            <div id="weighted-scores-option-container"></div>
    \\            <button name="submit" type="submit">Save</button>
    \\        </form>
    \\    </div>
    \\</div>
    ;

    const default_opts = scatty.Options{};
    conn.game_state = conn.app.games_arena.create("");

    try cmd.respondSelf(conn, content);
}

pub fn initViewOptions(arena: Allocator, conn: *Connection, _: ?json.Value) !void {
    const template = options_html;
    const default_form_values = ParsedGameOptions{};
    const content = try mustache.allocRenderText(arena, template, .{
        .rounds_option_default_value = default_form_values.rounds_option,
        .categories_per_round_option_default_value = default_form_values.categories_per_round_option,
        .repeat_categories_option_default_value = default_form_values.repeat_categories_option,
        .answering_time_limit_option_default_value = default_form_values.answering_time_limit_option,
        .enable_voting_time_limit_option_default_value = default_form_values.enable_voting_time_limit_option,
        .voting_time_limit_option_default_value = default_form_values.voting_time_limit_option,
        .alliteration_points_option_default_value = default_form_values.alliteration_points_option,
        .scoring_mode_option_default_value = default_form_values.scoring_mode_option,
        .weighted_scores_option_default_value = default_form_values.weighted_scores_option,
    });

    try cmd.respondSelf(conn, content);
}
