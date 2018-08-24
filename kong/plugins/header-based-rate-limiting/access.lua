local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"

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

local function header_composition(identification_headers, request_headers)
    local composition = {}

    for _, header_name in ipairs(identification_headers) do
        local encoded_header = ngx.encode_base64(request_headers[header_name])
        table.insert(composition, encoded_header)
    end

    return table.concat(composition, ":")
end

local function rate_limit(conf, headers)
    local custom_rate_limit = singletons.dao.header_based_rate_limits:find_all({
        service_id = conf.service_id,
        route_id = conf.route_id,
        header_composition = header_composition(conf.identification_headers, ngx.req.get_headers())
    })

    return custom_rate_limit and custom_rate_limit[1] and custom_rate_limit[1].rate_limit or conf.default_rate_limit
end

function Access.execute(conf)
    local redis = RedisFactory.create(conf.redis)
    local pool = RateLimitPool(redis, ngx)

    local actual_time = os.time()
    local time_reset = os.date("!%Y-%m-%dT%H:%M:00Z", actual_time + 60)

    local identifier = ConsumerIdentifier.generate(conf.identification_headers, ngx.req.get_headers())
    local rate_limit_key = RateLimitKey.generate(identifier, conf, actual_time)

    local request_count = pool:request_count(rate_limit_key)

    rate_limit_value = rate_limit(conf, ngx.req.get_headers())

    if not conf.log_only then
        ngx.header[RATE_LIMIT_HEADER] = conf.default_rate_limit
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
