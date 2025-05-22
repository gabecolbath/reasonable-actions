const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList; 
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub const BUILTIN_CATEGORY_LIST_FILEPATH: []const u8 = "categories/";
pub const MAX_CATEGORY_LEN: usize = 128;
pub const MAX_NUM_CATEGORIES: usize = 256;
pub const MAX_CATEGORY_LIST_SIZE: usize = (MAX_CATEGORY_LEN * MAX_NUM_CATEGORIES) + MAX_NUM_CATEGORIES;

pub fn loadCategoriesFromFile(list_name: []const u8, master_list: *ArrayList([]const u8), allocator: Allocator) !void {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const full_path: []const u8 = try std.fmt.bufPrint(&path_buffer, "{s}{s}.txt", .{ BUILTIN_CATEGORY_LIST_FILEPATH, list_name });

    const cwd = std.fs.cwd();
    const file = try cwd.openFile(full_path, .{ .mode = .read_only });
    defer file.close();

    const reader = file.reader();

    var category_buffer: [MAX_NUM_CATEGORIES][]const u8 = undefined;
    var loaded = ArrayListUnmanaged([]const u8).initBuffer(&category_buffer);
    while (try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', MAX_CATEGORY_LIST_SIZE)) |cat| {
        if (cat.len > 0) {
            loaded.appendAssumeCapacity(cat);
        }
    }

    try master_list.appendSlice(loaded.items);
}

pub fn loadCategoriesFromStr(str: []const u8, master_list: *ArrayList([]const u8)) !void {
    var it = std.mem.splitAny(u8, str, "\n");
    while (it.next()) |cat| {
        if (cat.len > 0) {
            try master_list.append(cat);
        }
    }
}

pub fn addCustomCategory(new_category: []const u8, list: *ArrayList([]const u8), allocator: Allocator) !void {
    try list.append(try allocator.dupe(u8, new_category));
}

pub fn chooseRandomCategories(num_categories: usize, master_list: *ArrayList([]const u8), allocator: Allocator) ![][]const u8 {
    var list = try master_list.clone();
    defer list.deinit();

    var rand: usize = 0;
    const chosen = try allocator.alloc([]const u8, num_categories);
    for (chosen) |*choose| {
        rand = std.crypto.random.intRangeLessThan(usize, 0, list.items.len);
        choose.* = list.swapRemove(rand);
    }

    return chosen;
}

pub fn chooseRandomLetterDynamic(available_letters: *ArrayList(u8)) u8 {
    const rand = std.crypto.random.intRangeLessThan(usize, 0, available_letters.items.len);
    const letter = available_letters.swapRemove(rand);
    
    return letter;
}

pub fn chooseRandomLetterStatic(available_letters: *ArrayList(u8)) u8 {
    const rand = std.crypto.random.intRangeLessThan(usize, 0, available_letters.items.len);
    const letter = available_letters.items[rand];
    
    return letter;
}
//
// test "Load Base Categories" {
//     std.debug.print("Test 1) Load Base Categories \n\n", .{});
//     defer std.debug.print("--------------------------------------------------------\n\n\n", .{});
//
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     const allocator = arena.allocator();
//     defer arena.deinit();
//     
//     var list = ArrayList([]const u8).init(std.testing.allocator);
//     defer list.deinit();
//
//     std.debug.print("Loaded Base Categories: \n", .{});
//     try loadCategoriesFromFile("base", &list, allocator);
//
//     for (list.items) |cat| {
//         std.debug.print("{s}\n", .{cat});
//     }
// }
//
// test "Create Custom Categories" {
//     std.debug.print("Test 2) Create Custom Categories \n\n", .{});
//     defer std.debug.print("--------------------------------------------------------\n\n\n", .{});
//
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     const allocator = arena.allocator();
//     defer arena.deinit();
//
//     const custom = 
//         \\BOYSIES PHRASES
//         \\WAYS TO DESCRIBE KADE
//         \\WAYS TO DESCRIBE DAN
//         \\WAYS TO DESCRIBE MICHAEL
//         \\WAYS TO DESCRIBE GABE
//         \\WAYS TO DESCRIBE REESE
//         \\WAYS TO DESCRIBE BOBBY
//         \\BOOG SNACK
//         \\THINGS KITTY WOULD LOVE TO KILL
//     ;
//     
//     var list = ArrayList([]const u8).init(std.testing.allocator);
//     defer list.deinit();
//
//     try loadCategoriesFromStr(custom, &list, allocator);
//     try addCustomCategory("BOYSIES TRIP LOCATIONS", &list, allocator);
//     
//     std.debug.print("Loaded Custom Categories: \n", .{});
//     for (list.items) |cat| {
//         std.debug.print("{s}\n", .{cat});
//     }
// }
//
// test "Choose Random Categories for a Game" {
//     std.debug.print("Test 3) Choose Random Categories for a Game\n\n", .{});
//     defer std.debug.print("--------------------------------------------------------\n\n\n", .{});
//
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     const allocator = arena.allocator();
//     defer arena.deinit();
//
//     var list = ArrayList([]const u8).init(std.testing.allocator);
//     defer list.deinit();
//
//     try loadCategoriesFromFile("base", &list, allocator);
//
//     for (1..11) |round| {
//         const chosen = try chooseRandomCategories(12, &list, std.testing.allocator);
//         defer std.testing.allocator.free(chosen);
//
//         std.debug.print("Round {d}\n", .{round});
//         for (chosen, 0..) |cat, count| {
//             std.debug.print("\t{d}. {s}\n", .{ count + 1, cat });
//         }
//     }
// }
//
// test "Choose Letter Given an Exclusion List" {
//     std.debug.print("Test 4) Choose Letter Given an Exclusion List\n\n", .{});
//     defer std.debug.print("--------------------------------------------------------\n\n\n", .{});
//
//     const exclude = "QUVXYZ";
//     
//     std.debug.print("Some Random Letters: \n", .{});
//     for (0..100) |_| {
//         std.debug.print("{c}, ", .{ chooseRandomLetter(exclude) });
//     } else std.debug.print("\n", .{});
// }
//
// test "Load Multiple Lists" {
//     std.debug.print("Test 5) Load Multiple Lists\n\n", .{});
//     defer std.debug.print("--------------------------------------------------------\n\n\n", .{});
//
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     const allocator = arena.allocator();
//     defer arena.deinit();
//     
//     const test_list: []const u8 = "--- FROM LIST 2 ---\n" ** 30;
//     
//     var list = ArrayList([]const u8).init(std.testing.allocator);
//     defer list.deinit();
//     
//     try loadCategoriesFromFile("base", &list, allocator);
//     try loadCategoriesFromStr(test_list, &list, allocator);
//     
//     std.debug.print("Master List: \n", .{});
//     for (list.items) |cat| {
//         std.debug.print("{s}\n", .{cat});
//     }
// }
