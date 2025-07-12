const std = @import("std");

const Allocator = std.mem.Allocator;

const scatty = @import("scatty.zig");
const games = @import("../games.zig");
const cli = @import("../../client.zig");


const Event = games.Event;
const EventMap = games.EventMap;
const ClientSource = cli.ClientSource;
const RoomSource = cli.RoomSource;

pub var events = EventMap.initComptime(.{
    .{ "AnswersSubmitted", OnAnswersSubmitted },
});


const OnAnswersSubmitted = struct {
    const Self = @This();

    const FormData = struct {
        @"answers[]": ?[][]const u8 = null,
    };

    pub fn exec(_: *Self, allocator: Allocator, trigger: Event.Trigger) !void {
        const form_data = try trigger.formData(allocator, FormData);
        const player: *scatty.State.Player = @ptrCast(@alignCast(trigger.client.player.state));
        const opts: *scatty.Options = @ptrCast(@alignCast(trigger.client.game.opts));

        player.answers.clear(allocator);

        if (form_data.@"answers[]") |answers| {
            std.debug.assert(answers.len == opts.categories_per_round);
            
            player.answers.load(allocator, answers); 
        }
    }
};
