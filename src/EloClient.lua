--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

type Dependency = any
type Dependencies = {[string]: Dependency}
type ClientFunction = (...any) -> (...any)
type ClientService = {
    [string]: ClientFunction,
    Init?: (self: ClientService, injector: DependencyInjector) -> (),
    Start?: (self: ClientService) -> (),
    Fire: (self: ClientService, methodName: string, ...any) -> (),
    Invoke: (self: ClientService, methodName: string, ...any) -> ...any,
    Extend?: (self: ClientService, extension: table) -> ()
}

type DependencyInjector = {
    AddDependency: (self: DependencyInjector, name: string, dependency: Dependency) -> (),
    GetDependency: (self: DependencyInjector, name: string) -> Dependency,
    Dependencies: Dependencies
}

type EloClient = {
    Services: {[string]: ClientService},
    Injector: DependencyInjector,
    CreateClientService: (self: EloClient, serviceName: string, serviceDef: ClientService) -> (),
    GetService: (self: EloClient, serviceName: string) -> ClientService,
    Start: (self: EloClient) -> (),
    ResponseHandlers: {[string]: (any) -> ()},
    ListenForResponse: (self: EloClient, key: string, handler: (any) -> ()) -> (),
    _CreateRemoteEvents: (self: EloClient, serviceName: string) -> ()
}

local Injector: DependencyInjector = {
    Dependencies = {},
    AddDependency = function(self, name, dependency)
        self.Dependencies[name] = dependency
    end,
    GetDependency = function(self, name)
        return self.Dependencies[name]
    end
}

local EloClient: EloClient = {
    Services = {},
    Injector = Injector,
    ResponseHandlers = {},

    CreateClientService = function(self, serviceName, serviceDef)
        self.Services[serviceName] = serviceDef
        self:_CreateRemoteEvents(serviceName)

        serviceDef.Fire = function(_, methodName, ...)
            local remoteEvent = ReplicatedStorage:FindFirstChild(serviceName .. "_" .. methodName)
            assert(remoteEvent and remoteEvent:IsA("RemoteEvent"), "RemoteEvent not found for Fire: " .. methodName)
            remoteEvent:FireServer(...)
        end

        serviceDef.Invoke = function(_, methodName, ...)
            local remoteEvent = ReplicatedStorage:FindFirstChild(serviceName .. "_" .. methodName)
            assert(remoteEvent and remoteEvent:IsA("RemoteEvent"), "RemoteEvent not found for Invoke: " .. methodName)

            local responseReceived = false
            local responseData = {}
            local key = serviceName .. "_" .. methodName

            self:ListenForResponse(key, function(...)
                responseData = {...}
                responseReceived = true
            end)

            remoteEvent:FireServer(...)

            while not responseReceived do
                RunService.Heartbeat:Wait()
            end

            return table.unpack(responseData)
        end
    end,

    GetService = function(self, serviceName)
        assert(self.Services[serviceName], "Service does not exist: " .. serviceName)
        return self.Services[serviceName]
    end,

    Start = function(self)
        for _, service in pairs(self.Services) do
            if service.Init then
                service:Init(self.Injector)
            end
        end
        for _, service in pairs(self.Services) do
            if service.Start then
                service:Start()
            end
        end
    end,

    _CreateRemoteEvents = function(self, serviceName)
        for _, item in ReplicatedStorage:GetChildren() do
            if item:IsA("RemoteEvent") and item.Name:find(serviceName .. "_") then
                local methodName = item.Name:sub(#serviceName + 2)
                local service = self.Services[serviceName]
                
                service[methodName] = function(self, ...)
                    item:FireServer(...)
                end

                item.OnClientEvent:Connect(function(...)
                    local key = serviceName .. "_" .. methodName
                    if self.ResponseHandlers[key] then
                        self.ResponseHandlers[key](...)
                        self.ResponseHandlers[key] = nil
                    end
                end)
            end
        end
    end
}

return EloClient
