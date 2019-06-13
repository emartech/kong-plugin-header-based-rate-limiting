local Object = require "classic"

local RateLimitPool = Object:extend()

RateLimitPool.TTL = 300

local function is_string(request_count)
    return type(request_count) == "string"
end

function RateLimitPool:new(redis)
    self.redis = redis
end

function RateLimitPool:increment(key)
    self.redis:incr(key)
    self.redis:expire(key, self.TTL)
end

function RateLimitPool:request_count(key)
    local request_count, err = self.redis:get(key)

    if not request_count then
        error({
            msg = "Redis failure",
            reason = err
        })
    end

    if not is_string(request_count) then
        return 0
    end

    return tonumber(request_count)
end

return RateLimitPool
