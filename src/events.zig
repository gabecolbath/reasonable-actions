const std = @import("std");
const server = @import("server.zig");
const httpz = @import("httpz");
const uuid = @import("uuid");
const json = std.json;
const websocket = httpz.websocket;

const games = struct {
    const scatty = @import("games/scatty/scatty.zig");
};

pub const EventError = error {
    UnknownEvent,
};

pub const assert = std.debug.assert;

// std =========================================================================
const Allocator = std.mem.Allocator;
const StaticStringMap = std.StaticStringMap;
const StringMap = std.StringArrayHashMap;
const Map = std.AutoArrayHashMapUnmanaged;
const List = std.ArrayListUnmanaged;
// server ======================================================================
const Room = server.Room;
const Member = server.Member;
// uuid ========================================================================
const Uuid = uuid.Uuid;

pub const Source = Member;
pub const Event = *const fn (arena: Allocator, ctx: *const Context) anyerror!void;

pub const Context = struct {
    src: *Source,
    event: []const u8,
    msg: ?struct {
        raw: []const u8,
        parsed: json.ObjectMap,
    } = null,
};

pub const Handler = struct {
    events: StaticStringMap(Event),

    pub fn init(comptime entries: anytype) Handler {
        return Handler{
            .events = StaticStringMap(Event).initComptime(entries),
        };
    }

    pub fn trigger(self: *const Handler, arena: Allocator, ctx: *const Context) !void {
        const call = self.events.get(ctx.event) orelse return EventError.UnknownEvent;
        try call(arena, ctx);
    }
};

pub const Parser = struct {
    pub const Val = json.Value;

    pub const ListOptions = struct {
        list_name: []const u8,
        include_missing: bool = true,
        num_vals_limit: usize = 16,
        treat_empty_strings_as_null: bool = true,
    };

    pub fn item(ctx: *const Context, name: []const u8) ?Val {
        const vals = if (ctx.msg) |msg| msg.parsed else return null;
        return vals.get(name);
    }

    pub fn list(arena: Allocator, ctx: *const Context, opts: ListOptions) ![]?Val {
        assert(opts.num_vals_limit < 100);
        assert(opts.list_name.len < 32);

        const name = opts.list_name;
        var buf: [32 + 4]u8 = undefined;

        if (opts.include_missing) {
            const result = try arena.alloc(?Val, opts.num_vals_limit);
            errdefer arena.free(result);

            const vals = if (ctx.msg) |msg| msg.parsed else {
                for (0..opts.num_vals_limit) |index| result[index] = null;
                return result;
            };

            get_vals: for (0..opts.num_vals_limit) |index| {
                const indexed_name = try std.fmt.bufPrint(&buf, "{s}[{d}]", .{ name, index + 1 });
                const val = vals.get(indexed_name) orelse {
                    result[index] = null;
                    continue;
                };

                switch (val) {
                    .string => |str| if (str.len == 0 and opts.treat_empty_strings_as_null) {
                        result[index] = null;
                        continue :get_vals;
                    },
                    .null => {
                        result[index] = null;
                        continue :get_vals;
                    },
                    else => {},
                }

                result[index] = val;
            }

            return result;
        } else {
            var result = try List(?Val).initCapacity(arena, opts.num_vals_limit);
            errdefer result.deinit(arena);

            const vals = if (ctx.msg) |msg| msg.parsed else {
                return try result.toOwnedSlice(arena);
            };

            get_vals: for (0..opts.num_vals_limit) |index| {
                const indexed_name = try std.fmt.bufPrint(&buf, "{s}[{d}]", .{ name, index });
                const val = vals.get(indexed_name) orelse break;

                switch (val) {
                    .string => |str| if (str.len == 0 and opts.treat_empty_strings_as_null) {
                        break :get_vals;
                    },
                    else => {},
                }

                result.appendAssumeCapacity(val);
            }

            return try result.toOwnedSlice(arena);
        }
    }

    pub fn string(val: json.Value) ?[]const u8 {
        switch (val) {
            .string => |str| return str,
            else => return null,
        }
    }
};

pub const Queue = struct {
    clients: Map(Uuid, *Source) = .{},

    pub fn reset(self: *Queue) void {
        self.clients.clearRetainingCapacity();
    }

    pub fn wait(self: *Queue, src: *Source) !void {
        try self.clients.put(src.room.game.arena.allocator(), src.id, src);
    }

    pub fn done(self: *Queue, src: *Source) void {
        _ = self.clients.swapRemove(src.id);
    }

    pub fn waiting(self: *Queue, src: *Source) bool {
        return self.clients.contains(src.id);
    }

    pub fn allWaiting(self: *Queue, src: *Source) bool {
        for (src.room.members.values()) |member| {
            if (!self.waiting(member)) return false;
        } else return true;
    }

    pub fn allDone(self: *Queue, src: *Source) bool {
        for (src.room.members.values()) |member| {
            if (self.waiting(member)) return false;
        } else return true;
    }
};
