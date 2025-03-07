const std = @import("std");
const uuid = @import("uuid");

const RoomId = uuid.Uuid;

pub const AppError = error{
    AppNotRunning,
};

pub const AppOptions = struct {};

pub const RoomOptions = struct {
    room_client_capacity: usize = 8,
    default_name_generator: fn (allocator: std.mem.Allocator) []const u8 = genDefaultRoomName,
};

pub const App = struct {
    opts: AppOptions,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, opts: AppOptions) App {
        return App{
            .opts = opts,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.arena.deinit();
    }
};

// TODO implement Room struct.
pub const Room = struct {
    opts: RoomOptions,
    arena: std.heap.ArenaAllocator,
    name: []const u8,
    id: RoomId,

    pub fn init(allocator: std.mem.Allocator, name: ?[]const u8, opts: AppOptions) Room {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const set_name_or_default = name orelse opts.default_name_generator(arena.allocator());

        return Room{
            .opts = opts,
            .arena = arena,
            .name = set_name_or_default,
            .id = uuid.v7.new(),
        };
    }

    pub fn deinit(self: *Room) void {
        self.arena.deinit();
    }
};

pub fn genDefaultRoomName(allocator: std.mem.Allocator) []const u8 {
    var room_name = std.ArrayList(u8).init(allocator);
    const writer = room_name.writer();

    writer.write("room_") catch return "anonymous_room";
    for (0..4) |_| {
        writer.writeByte(std.crypto.random.intRangeAtMost(u8, 'a', 'z')) catch return "anonymous_room";
    }

    const generated = room_name.toOwnedSlice() catch return "anonymous_room";
    return generated;
}
