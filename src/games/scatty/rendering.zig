const std = @import("std");
const uuid = @import("uuid");
const http = @import("httpz");
const zigomponents = @import("zigomponents");
const scatty = @import("scatty.zig");
const server = @import("../../server.zig");

const elem = zigomponents.el;
const attr = zigomponents.attr;

const Allocator = std.mem.Allocator;
const Room = server.Room;
const Member = server.Member;

const Html = elem.Html;
const Head = elem.Head;
const Body = elem.Body;
const Div = elem.Div;
const Title = elem.Title;
const Form = elem.Form;
const H1 = elem.H1;
const H2 = elem.H2;
const H3 = elem.H3;
const H4 = elem.H4;
const H5 = elem.H5;
const P = elem.P;
const Text = elem.Text;
const Script = elem.Script;
const Button = elem.Button;
const Label = elem.LabElement;
const Input = elem.Input;
const A = elem.A;
const Span = elem.Span;

const Src = attr.Src;
const Integrity = attr.Integrity;
const Id = attr.ID;
const Hidden = attr.Hidden;
const For = attr.For;
const Type = attr.Type;
const Name = attr.Name;
const Value = attr.Value;
const Class = attr.Class;
const Href = attr.Href;
const MinLength = attr.MinLength;
const MaxLength = attr.MaxLength;
const Style = attr.Style;
fn CrossOrigin(value: []const u8) Node { return Attr("crossorigin", value); }
fn Size(value: []const u8) Node { return Attr("size", value); }

const ToNode = elem.ToNode;
const Node = zigomponents.Node;
const Elem = zigomponents.wrappers.El;
const Attr = zigomponents.wrappers.Attr;

const Hx = struct {
    fn ext(value: []const u8) Node { return Attr("hx-ext", value); }
    fn get(value: []const u8) Node { return Attr("hx-get", value); }
    fn post(value: []const u8) Node { return Attr("hx-post", value); }
    fn target(value: []const u8) Node { return Attr("hx-target", value); }
    fn trigger(value: []const u8) Node { return Attr("hx-trigger", value); }
    fn swap(value: []const u8) Node { return Attr("hx-swap", value); }
    fn swap_oob(value: []const u8) Node { return Attr("hx-swap-oob", value); }
    fn vals(value: []const u8) Node { return Attr("hx-vals", value); }
    fn include(value: []const u8) Node { return Attr("hx-include", value); }
};

const Ws = struct {
    fn connect(value: []const u8) Node { return Attr("ws-connect", value); }
    const send = Attr("ws-send", null);
};

const template_len_limit = 256;

pub const template = std.fmt.allocPrint;
const render = server.rendering.render;
const vals = server.rendering.vals;

const Custom = struct {
    pub fn answerTimer(arena: Allocator, answering_time_limit: u8) !Node {
        const script = try template(arena,
        \\let remaining = {d};
        \\
        \\const timeEl = document.getElementById("time");
        \\
        \\const timer = setInterval(() => {{
        \\  remaining--;
        \\  timeEl.textContent = remaining;
        \\
        \\  if (remaining <= 0) {{
        \\    clearInterval(timer);
        \\    htmx.trigger("#answering-form", "submit");
        \\  }}
        \\}}, 1000);
        , .{answering_time_limit});

        return elem.Raw(try render(arena, ToNode(&.{
            Div(&.{
                Id("timer"),

                Span(&.{
                    Id("time"),

                    Text(try template(arena, "{d}", .{answering_time_limit}))
                }),
                Script(&.{ Text(script) }),
            }),
        })));
    }
};

pub fn answeringScene(arena: Allocator, answering_time_limit: u8) ![]const u8 {
    return try render(arena, ToNode(&.{
        Div(&.{
            Id("answering"),
            Style("display: flex; flex-direction: column;"),

            Hx.swap_oob("outerHTML:#dashboard"),

            try Custom.answerTimer(arena, answering_time_limit),
            Form(&.{
                Id("answering-form"),
                Style("display: flex; flex-direction: column;"),

                Hx.trigger("submit"),
                Hx.vals(try vals(arena, &.{ .{ .name = "event", .value = "game/player-answered" } })),

                Ws.send,
            }),
        }),
    }));
}

pub fn answerInput(arena: Allocator, category_idx: u8, category: []const u8) ![]const u8 {
    const id = try template(arena, "answer-input[{d}]", .{category_idx});
    const name = try template(arena, "answer[{d}]", .{category_idx});
    const label = try template(arena, "{d}. {s}", .{category_idx, category});

    return try render(arena, ToNode(&.{
        Div(&.{
            Hx.swap_oob("beforeend:#answering-form"),

            Div(&.{
                Class("answering-form-item"),
                Style("display: grid; grid-template-columns: 1fr 1fr;"),

                Label(&.{
                    For(id),

                    Text(label),
                }),
                Input(&.{
                    Type("text"),
                    Id(id),
                    Name(name),
                    MaxLength("64"),
                    Size("64"),
                }),
            }),
        }),
    }));
}

// pub fn votingScene(_: Allocator, _: *scatty.Game) ![]const u8 {
//     // TODO
// }
