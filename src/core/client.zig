const std = @import("std");


const core = @import("core.zig");
const Agent = core.agent.Agent;
const Space = core.space.Space;
const ServerError = core.server.ServerError;
const EngineError = core.engine.EngineError;


const network = @import("../network/network.zig");
const Connection = network.httpz.websocket.Conn;


const application = @import("../application.zig");
const App = application.App;


const entities = @import("../entities/entities.zig");
const Room = entities.room.Room;
const Member = entities.member.Member;
const Game = entities.game.Game;
const Player = entities.player.Player;


pub const Client = struct {
    app: *App,
    conn: *Connection,
    agent: Agent,
    space: Space,
    assets: Assets,

    const Self = @This();

    const Assets = struct {
        server: Server,
        engine: Engine,

        const Server = struct {
            room: Room, 
            member: *Member,
        };
        
        const Engine = struct {
            game: Game, 
            player: *Player,
        };
    };

    pub fn pull(self: *Self) !void {

    }

    pub fn push(self: *Self) !void {

    }
};
