const std = @import("std");


const core = @import("core.zig");
const Agent = core.agent.Agent;
const Space = core.space.Space;


const application = @import("../application.zig");
const App = application.App;


const entities = @import("../entities/entities.zig");
const Room = entities.room.Room;
const Member = entities.member.Member;
const Game = entities.game.Game;
const Player = entities.player.Player;


const Client = struct {
    app: *App,
    agent: Agent,
    space: Space,
    assets: Assets,

    const Self = @This();

    const Assets = struct {
        room: Room,
        member: Member,
        game: Game,
        player: Player,
    };

    pub fn pull(self: *Self) !void {
        const room = self.app.server.rooms.get(self.space.uuid);
        const game = self.app.engine.games.get(self.space.uuid);

        // TODO
    }
};
