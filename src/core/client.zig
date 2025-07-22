const std = @import("std");
const ArrayListUnamanged = std.ArrayListUnmanaged;


const application = @import("../application.zig");
const App = application.App;
const AppError = application.AppError;


const core = @import("core.zig");
const Agent = core.agent.Agent;
const Scope = core.scope.Scope;
const ServerError = core.server.ServerError;
const EngineError = core.engine.EngineError;


const network = @import("../network/network.zig");
const Connection = network.httpz.websocket.Conn;


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
    pub const List = ArrayListUnamanged(*Client);

    const Assets = struct {
        room: Room,
        game: Game,
    };

    pub fn pull(self: *Self) !void {
        var room = self.app.server.rooms.get(self.scope.uuid) orelse return ServerError.RoomNotFound;
        var game = self.app.engine.games.get(self.scope.uuid) orelse return EngineError.GameNotFound;
        const clients_in_scope = self.scope.clients.items;
        
        room.members.clearRetainingCapacity();
        game.players.clearRetainingCapacity();

        for (clients_in_scope) |client| {
            const member = self.app.server.members.get(client.agent.uuid) orelse continue;
            const player = self.app.engine.players.get(client.agent.uuid) orelse continue;
            
            room.members.putAssumeCapacity(member.agent.uuid, member); 
            game.players.putAssumeCapacity(player.agent.uuid, player);
        }

        self.assets.room = room;
        self.assets.game = game;
    }

    pub fn push(self: *Self) !void {
        var room = self.assets.room;
        var game = self.assets.game;
        const clients_in_scope = self.scope.clients.items;

        for (clients_in_scope) |client| {
            const member = room.members.get(client.agent.uuid) orelse continue;
            const player = game.players.get(client.agent.uuid) orelse continue;
            
            self.app.server.members.putAssumeCapacity(member.agent.uuid, member);
            self.app.engine.players.putAssumeCapacity(player.agent.uuid, player);
        }

        self.app.server.rooms.putAssumeCapacity(room.scope.uuid, room);
        self.app.engine.games.putAssumeCapacity(game.scope.uuid, game);
    }
};
