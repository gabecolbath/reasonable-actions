const std = @import("std");


const core = @import("core.zig");
const Agent = core.agent.Agent;
const Scope = core.scope.Scope;
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
    scope: Scope,
    assets: Assets,

    const Self = @This();

    const Assets = struct {
        room: Room,
        game: Game,
    };

    pub fn synced(self: *Self) bool {
        if (self.assets.room.scope != self.assets.game.scope) return false;
        
        for (self.assets.room.members.values()) |member| {
            if (!self.assets.game.players.contains(member.agent.uuid)) return false;
        }
        for (self.assets.game.players.values()) |player| {
            if (!self.assets.room.members.contains(player.agent.uuid)) return false;
        }
    }

    pub fn pull(self: *Self) !void {
        var room = self.app.server.rooms.get(self.scope.uuid) orelse return ServerError.RoomNotFound;
        var game = self.app.engine.games.get(self.scope.uuid) orelse return ServerError.MemberNotFound; 

        room.members.clearRetainingCapacity();
        game.players.clearRetainingCapacity();

        for (room.members.values()) |member| {
            const member_data = self.app.server.members.get(member.agent.uuid) orelse continue;
            const player_data = self.app.engine.players.get(member.agent.uuid) orelse continue;
            room.members.putAssumeCapacity(member.agent.uuid, member_data);
            game.players.putAssumeCapacity(member.agent.uuid, player_data);
        }

        self.assets = Assets{
            .room = room,
            .game = game,
        };
    }

    pub fn push(self: *Self) !void {
    }
};
