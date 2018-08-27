local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"

local RateLimitSubject = require "kong.plugins.header-based-rate-limiting.rate_limit_subject"
local RateLimitKey = require "kong.plugins.header-based-rate-limiting.rate_limit_key"
local RateLimitPool = require "kong.plugins.header-based-rate-limiting.rate_limit_pool"
local RateLimitRule = require "kong.plugins.header-based-rate-limiting.rate_limit_rule"
local RateLimitModel = require "kong.plugins.header-based-rate-limiting.rate_limit_model"
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
    local pool = RateLimitPool(redis, ngx)

    local actual_time = os.time()
    local time_reset = os.date("!%Y-%m-%dT%H:%M:00Z", actual_time + 60)

    local rate_limit_subject = RateLimitSubject(conf.identification_headers, ngx.req.get_headers())
    local rate_limit_key = RateLimitKey.generate(rate_limit_subject:identifier(), conf, actual_time)

    local request_count = pool:request_count(rate_limit_key)

    local model = RateLimitModel(singletons.dao.db)
    local rule = RateLimitRule(model, conf.default_rate_limit)
    local rate_limit_value = rule:find(conf.service_id, conf.route_id, rate_limit_subject)

    if not conf.log_only then
        ngx.header[RATE_LIMIT_HEADER] = rate_limit_value
        ngx.header[REMAINING_REQUESTS_HEADER] = calculate_remaining_request_count(
            request_count,
            conf.default_rate_limit
        )
        ngx.header[POOL_RESET_HEADER] = time_reset
    end

    if request_count >= rate_limit_value then
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
