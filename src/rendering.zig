const std = @import("std");
const uuid = @import("uuid");
const http = @import("httpz");
const zigomponents = @import("zigomponents");
const server = @import("server.zig");

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
fn Hr() Node { return Elem("hr", null); }

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
const Style = attr.Style;
fn CrossOrigin(value: []const u8) Node { return Attr("crossorigin", value); }

const ToNode = elem.ToNode;
const Node = zigomponents.Node;
const RawElem = zigomponents.el.Raw;
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
};

const Ws = struct {
    fn connect(value: []const u8) Node { return Attr("ws-connect", value); }
    const send = Attr("ws-send", null);
};

const template_len_limit = 256;

pub const template = std.fmt.allocPrint;

pub fn render(arena: std.mem.Allocator, node: Node) ![]const u8 {
    var data = std.ArrayList(u8){};
    try node.render(data.writer(arena));
    return data.items;
}

pub fn vals(arena: std.mem.Allocator, items: []const struct { name: []const u8, value: []const u8 }) ![]const u8 {
    var str = std.ArrayList(u8){};
    var val_buf: [256]u8 = undefined;

    try str.append(arena, '{');
    for (items) |item| {
        const val = try std.fmt.bufPrint(&val_buf, "&quot;{s}&quot;:&quot;{s}&quot;,", .{ item.name, item.value });
        try str.appendSlice(arena, val);
    } else _ = str.pop();
    try str.append(arena, '}');

    return str.items;
}

// Static
pub const create_room_button = Button(&.{
    Hx.get("/create"),
    Hx.swap("outerHTML"),
    Hx.swap_oob("outerHTML:#room-form"),

    Text("Create"),
});

pub const room_list = Div(&.{
    Id("room-list"),

    Hx.get("/rooms"),
    Hx.trigger("load once"),
    Hx.swap("beforeend"),
});

pub const empty_member_list = Div(&.{
    Id("member-list"),
    Style("display: flex; flex-direction: column;"),

    Hx.swap_oob("outerHTML:#member-list"),
});

// Dynamic
pub fn index(arena: Allocator) ![]const u8 {
    return try render(arena, elem.ToNode(&.{
        RawElem("<!DOCTYPE html>"),
        Html(&.{
            Head(&.{
                Title("Reasonable Actions"),
                Script(&.{
                    Src("https://cdn.jsdelivr.net/npm/htmx.org@2.0.8/dist/htmx.min.js"),
                    Integrity("sha384-/TgkGk7p307TH7EXJDuUlgG3Ce1UVolAOFopFekQkkXihi5u/6OCvVKyz1W+idaz"),
                    CrossOrigin("anonymous"),
                }),
                Script(&.{
                    Src("https://cdn.jsdelivr.net/npm/htmx-ext-ws@2.0.4"),
                    Integrity("sha384-1RwI/nvUSrMRuNj7hX1+27J8XDdCoSLf0EjEyF69nacuWyiJYoQ/j39RT1mSnd2G"),
                    CrossOrigin("anonymous"),
                })
            }),
            Body(&.{
                Div(&.{
                    Id("page"),

                    H1(&.{ Text("Rooms") }),
                    create_room_button,
                    room_list,
                }),
            }),
        }),
    }));
}

pub fn game(arena: Allocator, room: *Room, member: *Member) ![]const u8 {
    return try render(arena, elem.ToNode(&.{
        Div(&.{
            Hx.swap_oob("innerHTML:#websocket"),

            H4(&.{ Text(try template(arena, "{s} | {s}", .{ room.name, member.name })) }),
            Hr(),
            Div(&.{
                Id("game"),

                Div(&.{
                    Id("lobby"),

                    if (member.is_host) host: {
                        break :host Button(&.{
                            Hx.vals(try vals(arena, &.{ .{ .name = "event", .value = "game/start" } })),
                            Ws.send,

                            Text("Start"),
                        });
                    } else member: {
                            break :member Text("Waiting for host to start the game...");
                        },
                }),
            }),
            Hr(),
            Div(&.{
                Id("member-list"),
                Style("display: flex; flex-direction: column;"),
            }),
            Hr(),
            P(&.{ Text(&room.urn()) }),
        }),
    }));
}

pub fn memberForm(arena: Allocator, room_urn: []const u8) ![]const u8 {
    return try render(arena, elem.ToNode(&.{
        Div(&.{
            Id("join-form"),

            Form(&.{
                Hx.post(try template(arena, "/member?room={s}", .{room_urn})),
                Hx.target("#page"),
                Hx.swap("innerHTML"),

                Label(&.{ For("name-input") }),
                Input(&.{
                    Type("text"),
                    Id("name-input"),
                    Name("name"),
                }),
                Input(&.{
                    Type("submit"),
                    Id("join-input"),
                    Name("join"),
                    Value("Join"),
                }),
            }),
        }),
    }));
}

pub fn memberName(arena: Allocator, member: *Member) ![]const u8 {
    return try render(arena, elem.ToNode(&.{
        Div(&.{
            Hx.swap_oob("beforeend:#member-list"),

            Span(&.{
                Class("member-name"),

                if (member.is_host) host: {
                    break :host Text(try template(arena, "{s} ♔", .{member.name}));
                } else member: {
                    break :member Text(member.name);
                },
            }),
        }),
    }));
}

pub fn roomCard(arena: Allocator, room: *Room) ![]const u8 {
    return try render(arena, elem.ToNode(&.{
        Div(&.{
            Class("room-card"),

            A(&.{
                Href(""),

                Hx.get(try template(arena, "/join?room={s}", .{room.urn()})),
                Hx.swap("outerHTML"),

                Text(room.name),
            })
        }),
    }));
}

pub fn roomForm(arena: Allocator) ![]const u8 {
    return try render(arena, elem.ToNode(&.{
        Div(&.{
            Id("room-form"),

            Form(&.{
                Hx.post("/room"),
                Hx.target("#room-list"),
                Hx.swap("afterbegin"),

                Label(&.{ For("name-input") }),
                Input(&.{
                    Type("text"),
                    Id("name-input"),
                    Name("name"),
                }),
                Input(&.{
                    Type("submit"),
                    Id("create-input"),
                    Name("create"),
                    Value("Create"),
                }),
            }),
        }),
    }));
}

pub fn websocket(arena: Allocator, room_urn: []const u8, member_name: []const u8) ![]const u8 {
    return try render(arena, elem.ToNode(&.{
        Div(&.{
            Id("websocket"),

            Hx.ext("ws"),
            Ws.connect(try template(arena, "/ws?room={s}&name={s}", .{ room_urn, member_name })),

            Text("Connecting..."),
        }),
    }));
}

pub fn errorPage(arena: Allocator, code: u16, msg: []const u8) ![]const u8 {
    return try render(arena, elem.ToNode(&.{
        Div(&.{
            Id("error"),

            Hx.swap_oob("innerHTML:#page"),

            H3(&.{ Text(try template(arena, "{d} Error", .{code})) }),
            P(&.{ Text(msg) }),
        })
    }));
}
