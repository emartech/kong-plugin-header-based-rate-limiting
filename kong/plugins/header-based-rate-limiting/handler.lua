local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"

local ConsumerIdentifier = require "kong.plugins.header-based-rate-limiting.consumer_identifier"
local RateLimitKey = require "kong.plugins.header-based-rate-limiting.rate_limit_key"
local RateLimitPool = require "kong.plugins.header-based-rate-limiting.rate_limit_pool"
local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"

local RATE_LIMIT_HEADER = "X-RateLimit-Limit"
local REMAINING_REQUESTS_HEADER = "X-Ratelimit-Remaining"
local POOL_RESET_HEADER = "X-Ratelimit-Reset"

local HeaderBasedRateLimitingHandler = BasePlugin:extend()

HeaderBasedRateLimitingHandler.PRIORITY = 901

function HeaderBasedRateLimitingHandler:new()
    HeaderBasedRateLimitingHandler.super.new(self, "header-based-rate-limiting")
end

function HeaderBasedRateLimitingHandler:access(conf)
    HeaderBasedRateLimitingHandler.super.access(self)

    local success, result = pcall(RedisFactory.create, conf.redis)

    if success then
        local redis = result
        local pool = RateLimitPool(redis)

        local rate_limit_key = RateLimitKey.generate(
            ConsumerIdentifier.generate({ "x-custom-identifier" }, ngx.req.get_headers()),
            conf
        )

        local request_count = pool:request_count(rate_limit_key)

        local time_reset = os.date("!%Y-%m-%dT%H:%M:00Z", os.time() + 60)

        if not conf.log_only then
            ngx.header[RATE_LIMIT_HEADER] = conf.default_rate_limit
            ngx.header[REMAINING_REQUESTS_HEADER] = conf.default_rate_limit - (request_count + 1)
            ngx.header[POOL_RESET_HEADER] = time_reset
        end

        if request_count >= conf.default_rate_limit then
            if not conf.log_only then
                responses.send(429, "Rate limit exceeded")
            end
        else
            pool:increment(rate_limit_key)
        end
    end
end

return HeaderBasedRateLimitingHandler
