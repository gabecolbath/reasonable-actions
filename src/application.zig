const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const ArrayListUnmanaged = std.ArrayListUnmanaged;


const core = @import("core/core.zig");
const Server = core.server.Server;
const Engine = core.engine.Engine;
const Scope = core.scope.Scope;
const Agent = core.agent.Agent;


const network = @import("network/network.zig"); 


const ScopeToAgentsMap = AutoHashMapUnmanaged(Scope.Identifier, ArrayListUnmanaged(Agent));
const AgentToScopeMap = AutoHashMapUnmanaged(Agent.Identifier, Scope);


pub const AppError = error {
    SyncError,
};


pub const App = struct {
    allocator: Allocator,
    server: Server, 
    engine: Engine,
    
    const Self = @This(); 
    const WebsocketHandler = network.websocket.WebsocketHandler;
};
