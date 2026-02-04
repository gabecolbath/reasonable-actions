//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const rendering = @import("rendering.zig");

pub const games = struct {
    pub const scatty = @import("scatty.zig");
};
