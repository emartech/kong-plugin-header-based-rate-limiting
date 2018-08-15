local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"

local RateLimitPool = require "kong.plugins.header-based-rate-limiting.rate_limit_pool"
local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"

local function identifier_from_headers(header_name)
    local headers = ngx.req.get_headers()
    return headers[header_name] or ""
end

local HeaderBasedRateLimitingHandler = BasePlugin:extend()

HeaderBasedRateLimitingHandler.PRIORITY = 2000

function HeaderBasedRateLimitingHandler:new()
    HeaderBasedRateLimitingHandler.super.new(self, "header-based-rate-limiting")
end

function HeaderBasedRateLimitingHandler:access(conf)
    HeaderBasedRateLimitingHandler.super.access(self)

    local success, result = pcall(RedisFactory.create, conf.redis)

    if success then
        local redis = result
        local pool = RateLimitPool(redis)

        local rate_limit_key = "ratelimit:" .. identifier_from_headers("x-custom-identifyer")

        local request_count = pool:request_count(rate_limit_key)

        if request_count >= conf.default_rate_limit then
            responses.send(429, "Rate limit exceeded")
        else
            pool:increment(rate_limit_key)
        end
    end
end

return HeaderBasedRateLimitingHandler
