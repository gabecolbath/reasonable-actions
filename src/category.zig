const std = @import("std");
const conf = @import("config.zig");

pub const Category = []const u8;
pub const Answer = []const u8;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn readCategoryFiles(allocator: Allocator, list_names: []const []const u8) ![]const u8 {
    const cwd = std.fs.cwd();

    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var data = ArrayList(u8).init(allocator);
    for (list_names) |list_name| {
        const full_path = try std.fmt.bufPrint(&path_buffer, "{s}{s}.txt", .{
            conf.categories_list_filepath,
            list_name,
        });

        const list_file = try cwd.openFile(full_path, .{ .mode = .read_only });
        defer list_file.close();

        const reader = list_file.reader();
        try reader.readAllArrayList(&data, conf.max_categories_list_size);
    }

    return try data.toOwnedSlice();
}

pub fn toCategoryList(allocator: Allocator, buffer: []const u8) ![]Category {
    var list = ArrayList(Category).init(allocator);
    var cat_it = std.mem.splitAny(u8, buffer, "\n");
    while (cat_it.next()) |cat| {
        if (cat.len > 0) {
            try list.append(cat);
        }
    }
    
    return try list.toOwnedSlice();
}

pub fn writeToCustomCategoriesFile(str: []const u8) !void {
    const cwd = std.fs.cwd();
    const list_file = try cwd.openFile(conf.custom_categories_filepath, .{ .mode = .write_only });
    defer list_file.close();
    
    const writer = list_file.writer();
    try writer.writeAll(str);
}

pub fn chooseRandomCategories(allocator: Allocator, list: []Category, choose: usize) ![]Category {
    std.debug.assert(choose < list.len);

    var shuffled = list;
    std.crypto.random.shuffle(Category, shuffled);
    const random_categories = try allocator.alloc([]const u8, choose);
    std.mem.copyBackwards([]const u8, random_categories, shuffled[0..choose]);

    return random_categories;
}
