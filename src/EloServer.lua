--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

type Dependency = any
type Dependencies = {[string]: Dependency}
type ClientFunction = (self: ServerService, player: Player, ...any) -> (...any)
type ClientService = {[string]: ClientFunction}
type ServiceLifecycle = {
    Init?: (self: ServerService) -> (),
    Start?: (self: ServerService) -> (),
    [any]: any
}
type ServerService = ServiceLifecycle & {
    Name: string,
    Dependencies?: Dependencies,
    Client?: ClientService,
    ResponseListeners: {[string]: (any) -> ()},
    WaitForResponse: (string, number) -> ...any,
    Fire: (string, Player, ...any) -> (),
    Invoke: (string, Player, ...any) -> ...any,
    Listen: (string, (Player, ...any) -> ()) -> (),
}

type EloServer = {
    Services: {[string]: ServerService},
    Dependencies: Dependencies,
    CreateServerService: (serviceDef: ServerService) -> (),
    AddDependency: (name: string, dependency: Dependency) -> (),
    Start: () -> (),
    ExtendService: (serviceName: string, extension: ServiceLifecycle) -> (),
}

local EloServer = {
    Services = {},
    Dependencies = {},

    Start = function(self)
        for _, service in self.Services do
            if service.Init then service:Init() end
        end
        for _, service in self.Services do
            if service.Start then service:Start() end
        end
    end,

    CreateServerService = function(self, serviceDef)
        assert(not self.Services[serviceDef.Name], "Service with this name already exists")
        self:_InjectDependencies(serviceDef)
        self:_SetupCommunication(serviceDef)
        self.Services[serviceDef.Name] = serviceDef
    end,

    AddDependency = function(self, name, dependency)
        assert(not self.Dependencies[name], "Dependency already exists with this name")
        self.Dependencies[name] = dependency
    end,

    _InjectDependencies = function(self, service)
        for name in service.Dependencies or {} do
            assert(self.Dependencies[name], "Missing dependency: " .. name)
            service[name] = self.Dependencies[name]
        end
    end,

    _SetupCommunication = function(self, service)
        if not service.Client then return end

        service.ResponseListeners = {}

        service.Fire = function(methodName, player, ...)
            local event = ReplicatedStorage:FindFirstChild(service.Name .. "_" .. methodName)
            assert(event and event:IsA("RemoteEvent"), "RemoteEvent not found for method: " .. methodName)
            event:FireClient(player, ...)
        end

        service.Invoke = function(methodName, player, ...)
            local event = ReplicatedStorage:FindFirstChild(service.Name .. "_" .. methodName)
            assert(event and event:IsA("RemoteEvent"), "RemoteEvent not found for method: " .. methodName)

            local key = service.Name .. "_" .. methodName .. "_" .. player.UserId
            local responseReceived = false
            local responseData = {}

            service.ResponseListeners[key] = function(...)
                responseReceived = true
                responseData = {...}
            end

            event:FireClient(player, ...)

            local startTime = tick()
            while not responseReceived and tick() - startTime < 5 do
                RunService.Heartbeat:Wait()
            end

            if responseReceived then
                return table.unpack(responseData)
            else
                error("Response timed out for method: " .. methodName)
            end
        end

        service.Listen = function(methodName, callback)
            local event = ReplicatedStorage:FindFirstChild(service.Name .. "_" .. methodName)
            assert(event and event:IsA("RemoteEvent"), "RemoteEvent not found for method: " .. methodName)
            event.OnServerEvent:Connect(callback)
        end

        for methodName, method in service.Client do
            local remoteEvent = Instance.new("RemoteEvent")
            remoteEvent.Name = service.Name .. "_" .. methodName
            remoteEvent.Parent = ReplicatedStorage

            remoteEvent.OnServerEvent:Connect(function(player, ...)
                local result = {method(service, player, ...)}
                if #result > 0 then
                    local key = service.Name .. "_" .. methodName .. "_" .. player.UserId
                    service.ResponseListeners[key](table.unpack(result))
                end
            end)
        end
    end,
}

return EloServer
