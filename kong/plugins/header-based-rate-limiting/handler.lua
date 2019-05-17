local Logger = require "logger"
local BasePlugin = require "kong.plugins.base_plugin"
local Access = require "kong.plugins.header-based-rate-limiting.access"

local HeaderBasedRateLimitingHandler = BasePlugin:extend()

HeaderBasedRateLimitingHandler.PRIORITY = 901

function HeaderBasedRateLimitingHandler:new()
    HeaderBasedRateLimitingHandler.super.new(self, "header-based-rate-limiting")
end

function HeaderBasedRateLimitingHandler:access(conf)
    HeaderBasedRateLimitingHandler.super.access(self)

    local success, error = pcall(Access.execute, conf)

    if not success then
        Logger.getInstance(ngx):logError(error)
    end
end

return HeaderBasedRateLimitingHandler
