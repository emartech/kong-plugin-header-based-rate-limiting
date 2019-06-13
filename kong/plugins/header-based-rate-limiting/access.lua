local Logger = require "logger"
local RateLimitSubject = require "kong.plugins.header-based-rate-limiting.rate_limit_subject"
local RateLimitKey = require "kong.plugins.header-based-rate-limiting.rate_limit_key"
local RateLimitPool = require "kong.plugins.header-based-rate-limiting.rate_limit_pool"
local RateLimitRule = require "kong.plugins.header-based-rate-limiting.rate_limit_rule"
local RateLimitModel = require "kong.plugins.header-based-rate-limiting.rate_limit_model"
local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"
local get_null_uuid = require "kong.plugins.header-based-rate-limiting.get_null_uuid"

local RATE_LIMIT_HEADER = "X-RateLimit-Limit"
local REMAINING_REQUESTS_HEADER = "X-RateLimit-Remaining"
local POOL_RESET_HEADER = "X-RateLimit-Reset"
local RATE_LIMIT_DECISION_HEADER = "X-RateLimit-Decision"

local Access = {}

local function calculate_remaining_request_count(previous_request_count, maximum_number_of_requests)
    local remaining_requests = maximum_number_of_requests - (previous_request_count + 1)

    return remaining_requests >= 0 and remaining_requests or 0
end

local function load_rate_limit_value(db, conf, rate_limit_subject)
    local rule = RateLimitRule(RateLimitModel(db), conf.default_rate_limit)

    return rule:find(conf.service_id, conf.route_id, rate_limit_subject)
end

function Access.execute(conf)
    local redis = RedisFactory.create(conf.redis)
    local pool = RateLimitPool(redis)

    local actual_time = os.time()
    local time_reset = actual_time + 60

    local rate_limit_subject = RateLimitSubject.from_request_headers(conf.identification_headers, kong.request.get_headers())
    local rate_limit_identifier = rate_limit_subject:identifier()
    local rate_limit_key = RateLimitKey.generate(rate_limit_identifier, conf, actual_time)

    local request_count = pool:request_count(rate_limit_key)

    local service_id = conf.service_id or get_null_uuid(kong.db.strategy)
    local route_id = conf.route_id or get_null_uuid(kong.db.strategy)

    local cache_key = kong.dao.header_based_rate_limits:cache_key(service_id, route_id, rate_limit_subject:encoded_identifier())
    local rate_limit_value = kong.cache:get(cache_key, nil, load_rate_limit_value, kong.dao.db, conf, rate_limit_subject)

    local remaining_requests = calculate_remaining_request_count(request_count, rate_limit_value)

    if not conf.log_only then
        kong.response.set_header(RATE_LIMIT_HEADER, rate_limit_value)
        kong.response.set_header(REMAINING_REQUESTS_HEADER, remaining_requests)
        kong.response.set_header(POOL_RESET_HEADER, time_reset)
    end

    if conf.forward_headers_to_upstream then
        kong.service.request.set_header(REMAINING_REQUESTS_HEADER, remaining_requests)
        kong.service.request.set_header(RATE_LIMIT_HEADER, rate_limit_value)
        kong.service.request.set_header(POOL_RESET_HEADER, time_reset)
    end

    local rate_limit_exceeded = request_count >= rate_limit_value

    if not rate_limit_exceeded then
        if conf.forward_headers_to_upstream then
            kong.service.request.set_header(RATE_LIMIT_DECISION_HEADER, "allow")
        end

        pool:increment(rate_limit_key)
    end

    redis:set_keepalive(
        conf.redis.max_idle_timeout_in_milliseconds or 1000,
        conf.redis.pool_size or 10
    )

    if rate_limit_exceeded then
        if conf.forward_headers_to_upstream then
            kong.service.request.set_header(RATE_LIMIT_DECISION_HEADER, "block")
        end

        if conf.log_only then
            Logger.getInstance(ngx):logInfo({
                msg = "Rate limit exceeded",
                uri = kong.request.get_path(),
                identifier = rate_limit_identifier
            })

            return
        end

        return kong.response.exit(429, { message = "Rate limit exceeded" })
    end
end

return Access
