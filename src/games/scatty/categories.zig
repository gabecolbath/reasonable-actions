const std = @import("std");
const scatty = @import("scatty.zig");

const random = std.crypto.random;

const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const LetterSet = std.AutoArrayHashMapUnmanaged(u8, void);
pub const Category = []const u8;
pub const CategoryListSourceMap = std.StringArrayHashMapUnmanaged([]const Category);
pub const StaticCategoryListSourceMap = std.StaticStringMap([]const Category);

pub const Round = struct {
    allocator: Allocator,
    sources: CategoryListSourceMap,
    letters: LetterSet,
    generated: Generated,
    
    const Self = @This();
    const Method = enum { repeat, no_repeat }; 

    const Generated = struct {
        method: Method,
        letter: u8,
        categories: []Category,
    }; 

    const Options = struct {
        sources: ?StaticCategoryListSourceMap = null,
        num_categories: usize,
        method: Method,
    }; 

    pub fn init(allocator: Allocator, opts: Options) !Self {
        var available_letters = LetterSet{};
        try available_letters.ensureTotalCapacity(allocator, default_letter_set.len);
        for (default_letter_set) |let| available_letters.putAssumeCapacity(let, {});

        const init_sources = process: {
            var result = CategoryListSourceMap{};
            if (opts.sources) |user_provided| {
                try result.ensureTotalCapacity(allocator, user_provided.values().len + 1);
                for (user_provided.keys()) |listname| {
                    const fetched_list = user_provided.get(listname) orelse continue;
                    result.putAssumeCapacity(listname, fetched_list);
                }
            } else {
                try result.ensureTotalCapacity(allocator, 1);
            }

            result.putAssumeCapacity("base", base_categories); 
            break :process result; 
        };

        const init_generation = process: {
            switch (opts.method) {
                .repeat => break :process Generated{
                    .method = opts.method,
                    .letter = randLetterRemove(&available_letters),
                    .categories = try randCategories(allocator, &init_sources, opts.num_categories)
                },
                .no_repeat => break :process Generated{
                    .method = opts.method,
                    .letter = randLetter(&available_letters),
                    .categories = try randCategories(allocator, &init_sources, opts.num_categories),
                },
            }  
        };

        return Self{
            .allocator = allocator,
            .sources = init_sources,
            .letters = available_letters,
            .generated = init_generation,
        };
    }

    pub fn deinit(self: *Self) void {
        self.sources.deinit(self.allocator);
        self.allocator.free(self.generated.categories);
    }

    pub fn newRound(self: *Self) !void {
        switch (self.generated.method) {
            .repeat => {
                self.generated.letter = randLetterRemove(&self.letters);
            },
            .no_repeat => {
                const new_categories = try randCategories(self.allocator, &self.sources, self.generated.categories.len);
                self.allocator.free(self.allocator);
                
                self.generated.letter = randLetter(&self.letters);
                self.generated.categories = new_categories; 
            },
        }
    }
};

const default_letter_set: []const u8 = "ABCDEFGHIJKLMNOPRSTW";
const base_categories: []const Category = readCategoryFile("categories/base.txt");

fn randCategories(allocator: Allocator, source_map: *const CategoryListSourceMap, num_categories: usize) ![]Category {
    const sources = source_map.values();
    var result = try ArrayListUnmanaged(Category).initCapacity(allocator, num_categories); 
    
    if (sources.len > 1) {
        for (0..num_categories) |_| {
            const rand_source_index = random.intRangeLessThan(usize, 0, sources.len);
            const rand_source = sources[rand_source_index];
            const rand_category = randCategory(rand_source);
            result.appendAssumeCapacity(rand_category);
        }
    } else {
        for (0..num_categories) |_| {
            const rand_category = randCategory(sources[0]);
            result.appendAssumeCapacity(rand_category);
        }
    }

    return try result.toOwnedSlice(allocator); 
}

fn randCategory(categories: []const Category) Category {
    const rand_category_index = random.intRangeLessThan(usize, 0, categories.len);
    const rand_category = categories[rand_category_index];

    return rand_category;
}

fn randLetterRemove(set: *LetterSet) u8 {
    if (set.count() > 0) {
        const rand_letter = randLetter(set);
        defer _ = set.swapRemove(rand_letter); 
        return rand_letter;
    } else {
        set.clearRetainingCapacity();
        for (default_letter_set) |let| set.putAssumeCapacity(let, {}); 
        return randLetterRemove(set); 
    }
}

fn randLetter(set: *const LetterSet) u8 {
    const available = set.keys();
    const rand_letter_index = random.intRangeLessThan(usize, 0, available.len);
    const rand_letter = available[rand_letter_index];
    
    return rand_letter; 
}

pub fn readCategoryFile(comptime path: []const u8) []const Category {
    @setEvalBranchQuota(10_000);
    const base_file = @embedFile(path);
    var tok_it = std.mem.tokenizeAny(u8, base_file, "\n\t");
    var result: []const []const u8 = &.{};
    while (tok_it.next()) |cat| {
        if (cat.len == 0) continue;
        result = result ++ &[_][]const u8{ cat };
    }

    return result;
}
