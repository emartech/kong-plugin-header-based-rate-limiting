local responses = require "kong.tools.responses"

local ConsumerIdentifier = require "kong.plugins.header-based-rate-limiting.consumer_identifier"
local RateLimitKey = require "kong.plugins.header-based-rate-limiting.rate_limit_key"
local RateLimitPool = require "kong.plugins.header-based-rate-limiting.rate_limit_pool"
local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"
local Logger = require "logger"

local RATE_LIMIT_HEADER = "X-RateLimit-Limit"
local REMAINING_REQUESTS_HEADER = "X-Ratelimit-Remaining"
local POOL_RESET_HEADER = "X-Ratelimit-Reset"

local Access = {}

local function calculate_remaining_request_count(previous_request_count, maximum_number_of_requests)
    local remaining_requests = maximum_number_of_requests - (previous_request_count + 1)
    return remaining_requests >= 0 and remaining_requests or 0
end

function Access.execute(conf)
    local redis = RedisFactory.create(conf.redis)
    local pool = RateLimitPool(redis)
    local actual_time = os.time()
    local time_reset = os.date("!%Y-%m-%dT%H:%M:00Z", actual_time + 60)
    local identifier = ConsumerIdentifier.generate(conf.identification_headers, ngx.req.get_headers())

    local rate_limit_key = RateLimitKey.generate(identifier, conf, actual_time)

    local request_count = pool:request_count(rate_limit_key)

    if not conf.log_only then
        ngx.header[RATE_LIMIT_HEADER] = conf.default_rate_limit
        ngx.header[REMAINING_REQUESTS_HEADER] = calculate_remaining_request_count(
            request_count,
            conf.default_rate_limit
        )
        ngx.header[POOL_RESET_HEADER] = time_reset
    end

    if request_count >= conf.default_rate_limit then
        if not conf.log_only then
            responses.send(429, "Rate limit exceeded")
        end

        Logger.getInstance(ngx):logInfo({
            ["msg"] = "Rate limit exceeded",
            ["uri"] = ngx.var.request_uri,
            ["identifier"] = identifier
        })
    else
        pool:increment(rate_limit_key)
    end
end

return Access
