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
local REMAINING_REQUESTS_HEADER = "X-RateLimit-Remaining"
local POOL_RESET_HEADER = "X-RateLimit-Reset"

local Access = {}

local function calculate_remaining_request_count(previous_request_count, maximum_number_of_requests)
    local remaining_requests = maximum_number_of_requests - (previous_request_count + 1)
    return remaining_requests >= 0 and remaining_requests or 0
end

local function load_rate_limit_value(db, conf, rate_limit_subject)
    local model = RateLimitModel(db)
    local rule = RateLimitRule(model, conf.default_rate_limit)
    local rate_limit_value = rule:find(conf.service_id, conf.route_id, rate_limit_subject)

    return rate_limit_value
end

function Access.execute(conf)
    local redis = RedisFactory.create(conf.redis)
    local pool = RateLimitPool(redis, ngx)

    local actual_time = os.time()
    local time_reset = actual_time + 60

    local rate_limit_subject = RateLimitSubject.from_request_headers(conf.identification_headers, ngx.req.get_headers())
    local rate_limit_identifier = rate_limit_subject:identifier()
    local rate_limit_key = RateLimitKey.generate(rate_limit_identifier, conf, actual_time)

    local request_count = pool:request_count(rate_limit_key)

    local cache_key = singletons.dao.header_based_rate_limits:cache_key(conf.service_id, conf.route_id, rate_limit_subject:encoded_identifier())
    local rate_limit_value = singletons.cache:get(cache_key, nil, load_rate_limit_value, singletons.dao.db, conf, rate_limit_subject)

    local remaining_requests = calculate_remaining_request_count(request_count, rate_limit_value)

    if not conf.log_only then
        ngx.header[RATE_LIMIT_HEADER] = rate_limit_value
        ngx.header[REMAINING_REQUESTS_HEADER] = remaining_requests
        ngx.header[POOL_RESET_HEADER] = time_reset
    end

    if conf.forward_headers_to_upstream then
        ngx.req.set_header(REMAINING_REQUESTS_HEADER, remaining_requests)
        ngx.req.set_header(RATE_LIMIT_HEADER, rate_limit_value)
        ngx.req.set_header(POOL_RESET_HEADER, time_reset)
    end

    local rate_limit_exceeded = request_count >= rate_limit_value

    if not rate_limit_exceeded then
        if conf.forward_headers_to_upstream then
            ngx.req.set_header("X-RateLimit-Decision", "allow")
        end

        pool:increment(rate_limit_key)
    end

    redis:set_keepalive(
        conf.redis.max_idle_timeout_in_milliseconds or 1000,
        conf.redis.pool_size or 10
    )

    if rate_limit_exceeded then
        if conf.forward_headers_to_upstream then
            ngx.req.set_header("X-RateLimit-Decision", "block")
        end

        if conf.log_only then
            Logger.getInstance(ngx):logInfo({
                msg = "Rate limit exceeded",
                uri = ngx.var.request_uri,
                identifier = rate_limit_identifier
            })
        else
            responses.send(429, "Rate limit exceeded")
        end
    end
end

return Access
