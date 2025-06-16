const std = @import("std");
const mustache = @import("mustache");
const httpz = @import("httpz");

const Allocator = std.mem.Allocator;

pub const Attributes = struct {
    elem: Essential = .{},
    form: Form = .{},
    media: Media = .{},
    htmx: Htmx = .{},

    pub fn generateTemplate() []const u8 {
        return comptime "{{#attr}}" 
            ++ "{{#elem}}" ++ Essential.template ++ "{{/elem}} "
            ++ "{{#form}}" ++ Form.template ++ "{{/form}} "
            ++ "{{#media}}" ++ Media.template ++ "{{/media}} "
            ++ "{{#htmx}}" ++ Htmx.template ++ "{{/htmx}}"
            ++ "{{/attr}}";
    } 
};

pub const Essential = struct {
    id: ?[]const u8 = null,
    class: ?[]const u8 = null,
    style: ?[]const u8 = null,
    title: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    dir: ?Dir = null,
    hidden: bool = false,
    tabindex: ?i8 = null,
    accesskey: ?[]const u8 = null,
    contenteditable: bool = false,
    draggable: bool = false,
    spellcheck: bool = false,
    translate: bool = false,

    const template = \\
        ++ \\{{#id}}id="{{{.}}}"{{/id}}
        ++ \\{{#class}}class="{{{.}}}"{{/class}}
        ++ \\{{#style}}style="{{{.}}}"{{/style}}
        ++ \\{{#title}}title="{{{.}}}"{{/title}}
        ++ \\{{#lang}}lang="{{{.}}}"{{/lang}}
        ++ \\{{#dir}}dir="{{{.}}}"{{/dir}}
        ++ \\{{#hidden}}hidden{{/hidden}}
        ++ \\{{#tabindex}}tabindex="{{{.}}}"{{/tabindex}}
        ++ \\{{#accesskey}}accesskey="{{{.}}}"{{/accesskey}}
        ++ \\{{#contenteditable}}contenteditable{{/contenteditable}}
        ++ \\{{#draggable}}draggable{{/draggable}}
        ++ \\{{#spellcheck}}spellcheck{{/spellcheck}}
        ++ \\{{#translate}}translate{{/translate}}
    ;

    const Dir = enum {
        ltr, rtl, auto,
    };
};

pub const Htmx = struct {
    hx_get: ?[]const u8 = null,
    hx_post: ?[]const u8 = null,
    hx_on: ?[]const u8 = null,
    hx_push_url: ?[]const u8 = null,
    hx_select: ?[]const u8 = null,
    hx_swap: ?Swap = null,
    hx_target: ?[]const u8 = null,
    hx_trigger: ?[]const u8 = null,
    hx_vals: ?[]const u8 = null,
    hx_swap_oob: ?*const SwapOob = null,
    hx_select_oob: ?*const SelectOob = null,
    ws_connect: ?[]const u8 = null,
    ws_send: bool = false,

    const template = \\
        ++ \\{{#hx_get}}hx-get="{{{.}}}"{{/hx_get}}
        ++ \\{{#hx_post}}hx-post="{{{.}}}"{{/hx_post}}
        ++ \\{{#hx_on}}hx-on="{{{.}}}"{{/hx_on}}
        ++ \\{{#hx_push_url}}hx-push-url="{{{.}}}"{{/hx_push_url}}
        ++ \\{{#hx_select}}hx-select="{{{.}}}"{{/hx_select}}
        ++ \\{{#hx_swap}}hx-swap="{{{.}}}"{{/hx_swap}}
        ++ \\{{#hx_target}}hx-target="{{{.}}}"{{/hx_target}}
        ++ \\{{#hx_trigger}}hx-trigger="{{{.}}}"{{/hx_trigger}}
        ++ \\{{#hx_vals}}hx-vals="{{{.}}}"{{/hx_vals}}
        ++ \\{{#hx_swap_oob}}hx-swap-oob="{{{strategy}}}{{#target}}:{{{.}}}{{/target}}"{{/hx_swap_oob}}
        ++ \\{{#hx_select_oob}}hx-select-oob="{{{target}}}{{#strategy}}:{{{.}}}{{/strategy}}{{/hx_select_oob}}
    ;

    pub const Swap = enum {
        innerHTML, outerHTML, textContent, beforebegin,
        afterbegin, beforeend, afterend, delete, none,
    };

    pub const SwapOob = struct {
        strategy: Swap,
        target: ?[]const u8,
    };

    pub const SelectOob = struct {
        target: []const u8,
        strategy: ?Swap,
    };
};

pub const Form = struct {
    name: ?[]const u8 = null,
    value: ?[]const u8 = null,
    itype: ?InputType = null,
    placeholder: ?[]const u8 = null,
    required: bool = false,
    disabled: bool = false,
    readonly: bool = false,
    checked: bool = false,
    selected: bool = false,
    multiple: bool = false,
    autocomplete: ?[]const u8 = null,
    pattern: ?[]const u8 = null,
    min: ?u32 = null,
    max: ?u32 = null,
    step: ?f32 = null,
    maxlength: ?u32 = null,
    minlength: ?u32 = null,

    const template = \\
        ++ \\{{#name}}name="{{{.}}}"{{/name}}
        ++ \\{{#value}}value="{{{.}}}"{{/value}}
        ++ \\{{#itype}}itype="{{{.}}}"{{/itype}}
        ++ \\{{#placeholder}}placeholder="{{{.}}}"{{/placeholder}}
        ++ \\{{#required}}required{{/required}}
        ++ \\{{#disabled}}disabled{{/disabled}}
        ++ \\{{#readonly}}readonly{{/readonly}}
        ++ \\{{#checked}}checked{{/checked}}
        ++ \\{{#selected}}selected{{/selected}}
        ++ \\{{#multiple}}multiple{{/multiple}}
        ++ \\{{#autocomplete}}autocomplete{{/autocomplete}}
        ++ \\{{#pattern}}pattern="{{{.}}}"{{/pattern}}
        ++ \\{{#min}}min="{{{.}}}"{{/min}}
        ++ \\{{#max}}max="{{{.}}}"{{/max}}
        ++ \\{{#step}}step="{{{.}}}"{{/step}}
        ++ \\{{#maxlength}}maxlength="{{{.}}}"{{/maxlength}}
        ++ \\{{#minlength}}minlength="{{{.}}}"{{/minlength}}
    ;

    pub const InputType = enum {
        text, password, email, number,
        checkbox, radio, submit, button,
    };
};

pub const Media = struct {
    href: ?[]const u8 = null,
    target: ?Target = null,
    rel: ?Rel = null,
    download: ?[]const u8 = null,
    src: ?[]const u8 = null,
    alt: ?[]const u8 = null,
    width: ?u32 = null,
    hight: ?u32 = null,
    loading: ?Loading = null,
    controls: bool = false,
    autoplay: bool = false,

    const template = \\
        ++ \\{{#href}}href="{{{.}}}"{{/href}}
        ++ \\{{#target}}target="{{{.}}}"{{/target}}
        ++ \\{{#rel}}rel="{{{.}}}"{{/rel}}
        ++ \\{{#download}}download="{{{.}}}"{{/download}}
        ++ \\{{#src}}src="{{{.}}}"{{/src}}
        ++ \\{{#alt}}alt="{{{.}}}"{{/alt}}
        ++ \\{{#width}}width="{{{.}}}"{{/width}}
        ++ \\{{#height}}height="{{{.}}}"{{/height}}
        ++ \\{{#loading}}loading="{{{.}}}"{{/loading}}
        ++ \\{{#controls}}controls{{/controls}}
        ++ \\{{#autoplay}}autoplay{{/autoplay}}
    ;

    pub const Target = enum { _self, _blank, _parent, _top };
    pub const Rel = enum { nofollow, noopener, noreferrer };
    pub const Loading = enum { lazy, eager };
};
