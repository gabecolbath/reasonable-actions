const std = @import("std");
const mustache = @import("mustache");
const httpz = @import("httpz");
const attributes = @import("attributes.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Attributes = attributes.Attributes;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const StackFallbackAllocator = std.heap.StackFallbackAllocator;

const Tag = enum { 
    div, input, form, sup,
    h1, a,
};

pub const Html = struct {
    elems: []const Element,

    const Self = @This();
    
    pub fn init(elems: []const Element) Self {
        return Self{ .elems = elems, };
    }

    pub fn allocRender(self: *const Self, allocator: Allocator) ![]const u8 {
        var rendered = ArrayListUnmanaged(u8){};
        for (self.elems) |elem| {
            const rendered_elem = elem.allocRender(allocator);
            try rendered.appendSlice(allocator, rendered_elem);
            allocator.free(rendered_elem);
        }

        return try rendered.toOwnedSlice(allocator);
    }
};

pub const Element = struct {
    fmt: Format = .@"<></>",
    tag: Tag = .div,
    attr: Attributes = .{},
    content: ?Content = null,

    const Self = @This();
    const Format = enum { @"<></>", @"</>" };
    const Meta = struct { tag: Tag, class: ?[]const u8 = null, id: ?[]const u8 = null };

    pub const Content = union(enum) {
        no_content,
        text: []const u8,
        html: []const Element,
    };

    pub const Templates = struct {
        with_content: []const u8 = "<{{{tag}}} " ++ Attributes.generateTemplate() ++ ">" ++ "{{{content}}}" ++ "</{{{tag}}}>",
        self_closing: []const u8 = "<{{{tag}}} " ++ Attributes.generateTemplate() ++ " />",
    };

    pub fn init(meta: Meta, attr: Attributes, content: ?Content) Element {
        var modded_attr = attr;
        modded_attr.elem.class = meta.class;
        modded_attr.elem.id = meta.id;
        
        return Element{
            .tag = meta.tag,
            .attr = modded_attr,
            .content = content,
        };
    }

    pub fn allocRender(self: *const Self, allocator: Allocator) ![]const u8 {
        const available_templates = Templates{};
        const template = switch (self.fmt) {
            .@"<></>" => available_templates.with_content,
            .@"</>" => available_templates.self_closing,
        };

        return try self.allocRenderWithTemplate(allocator, template);
    }

    pub fn allocRenderWithTemplate(self: *const Self, allocator: Allocator, template: []const u8) ![]const u8 {
        const rendered_content: []const u8 = render_content: {
            if (self.content) |content| {
                switch (content) {
                    .no_content => break :render_content "",
                    .text => |text| break :render_content text,
                    .html => |html| break :render_content {
                        var rendered_elems = ArrayListUnmanaged(u8){};
                        for (html) |elem| {
                            const rendered_elem = try elem.allocRenderWithTemplate(allocator, template);
                            try rendered_elems.appendSlice(allocator, rendered_elem); 
                            allocator.free(rendered_elem);
                        }
                        break :render_content try rendered_elems.toOwnedSlice(allocator);
                    },
                }
            } else break :render_content "";
        };

        return try mustache.allocRenderText(allocator, template, .{
            .tag = self.tag,
            .attr = .{
                .elem = self.attr.elem,
                .form = self.attr.form,
                .media = self.attr.media,
                .htmx = self.attr.htmx,
            },
            .content = rendered_content,
        });
    }
};
