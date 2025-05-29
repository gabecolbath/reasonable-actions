pub const packages = struct {
    pub const @"1220bf87d2f9994c323abfbc878fa5699d326f904fb8b91bf9fc580a7a319ad1f41c" = struct {
        pub const build_root = "/home/gabe/.cache/zig/p/zigclonedx-0.1.0-AAAAABiTAAC_h9L5mUwyOr-8h4-laZ0yb5BPuLkb-fxY";
        pub const build_zig = @import("1220bf87d2f9994c323abfbc878fa5699d326f904fb8b91bf9fc580a7a319ad1f41c");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"N-V-__8AAHOzAQBh8wB371GN1DXTl1mKs8Rdqj0sJea0U4P7" = struct {
        pub const build_root = "/home/gabe/.cache/zig/p/N-V-__8AAHOzAQBh8wB371GN1DXTl1mKs8Rdqj0sJea0U4P7";
        pub const build_zig = @import("N-V-__8AAHOzAQBh8wB371GN1DXTl1mKs8Rdqj0sJea0U4P7");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"httpz-0.0.0-PNVzrDm1BgBS1NqfP2uTPocAxDSTjZNJKr41Q_S63cFB" = struct {
        pub const build_root = "/home/gabe/.cache/zig/p/httpz-0.0.0-PNVzrDm1BgBS1NqfP2uTPocAxDSTjZNJKr41Q_S63cFB";
        pub const build_zig = @import("httpz-0.0.0-PNVzrDm1BgBS1NqfP2uTPocAxDSTjZNJKr41Q_S63cFB");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "metrics", "N-V-__8AAHOzAQBh8wB371GN1DXTl1mKs8Rdqj0sJea0U4P7" },
            .{ "websocket", "websocket-0.1.0-ZPISdXNIAwCXG7oHBj4zc1CfmZcDeyR6hfTEOo8_YI4r" },
        };
    };
    pub const @"uuid-0.3.0-oOieIVZ4AAB_apOo9zFV0a85GYAST-trqzRJMeEfYuQu" = struct {
        pub const build_root = "/home/gabe/.cache/zig/p/uuid-0.3.0-oOieIVZ4AAB_apOo9zFV0a85GYAST-trqzRJMeEfYuQu";
        pub const build_zig = @import("uuid-0.3.0-oOieIVZ4AAB_apOo9zFV0a85GYAST-trqzRJMeEfYuQu");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zigclonedx", "1220bf87d2f9994c323abfbc878fa5699d326f904fb8b91bf9fc580a7a319ad1f41c" },
        };
    };
    pub const @"websocket-0.1.0-ZPISdXNIAwCXG7oHBj4zc1CfmZcDeyR6hfTEOo8_YI4r" = struct {
        pub const build_root = "/home/gabe/.cache/zig/p/websocket-0.1.0-ZPISdXNIAwCXG7oHBj4zc1CfmZcDeyR6hfTEOo8_YI4r";
        pub const build_zig = @import("websocket-0.1.0-ZPISdXNIAwCXG7oHBj4zc1CfmZcDeyR6hfTEOo8_YI4r");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "httpz", "httpz-0.0.0-PNVzrDm1BgBS1NqfP2uTPocAxDSTjZNJKr41Q_S63cFB" },
    .{ "uuid", "uuid-0.3.0-oOieIVZ4AAB_apOo9zFV0a85GYAST-trqzRJMeEfYuQu" },
};
