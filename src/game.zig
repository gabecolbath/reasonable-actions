const std = @import("std");
const conf = @import("config.zig");

const random = std.crypto.random;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Html = []const u8;

pub const Scene = enum {
    lobby,
    reviewing,
    answering,
    voting,
    winning,
};

pub const Options = struct {
    lists: Lists,
    categories: Num = 12,
    rounds: Num = 3,
    repeat_categories: Check = true,
    answer_time_limit: ConditionalNum = null,
    bonus_time: ConditionalNum = null,  
    vote_time_limit: ConditionalNum = null,
    show_names: Check = false,
    vote_weighted: Check = false,

    const OptionError = error {
        UnknownOption,
    };

    const Self = @This();
    pub const Num = u32;
    pub const Check = bool;
    pub const Text = []const u8;
    pub const ConditionalNum = ?u32;
    pub const Lists = struct {
        base: Check = true,
        custom: Check = false,
    };

    pub fn toHtml(self: *Self, allocator: Allocator, comptime option_name: []const u8, comptime label: []const u8) !Html {
        const value: anyopaque = if (@hasField(Options, option_name)) {
            @field(self.*, option_name);
        } else return OptionError.UnknownOption;

        const Type = @FieldType(Options, option_name);
        const resolved_value: Type = @bitCast(value);
        
        const template = switch (Type) {
            Num => try allocator.dupe(u8,
                \\<label for="{{option_name}}>{{label}}</label>"
                \\<input id="{{option_name}}-input" name="{{option_name}}" type="number">
            ),
        };
    }
};
