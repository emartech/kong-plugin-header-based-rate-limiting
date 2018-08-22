local Object = require "classic"
local Logger = require "logger"

local RateLimitPool = Object:extend()

RateLimitPool.TTL = 300

function RateLimitPool:new(redis, nginx)
    self.redis = redis
    self.nginx = nginx
end

function RateLimitPool:increment(key)
    self.redis:incr(key)
    self.redis:expire(key, self.TTL)
end

function RateLimitPool:request_count(key)
    local request_count, err = self.redis:get(key)

    if not request_count then
        Logger.getInstance(self.nginx):logError({
            ["error"] = err,
            ["msg"] = "Redis failure"
        })
        error(err)
    end

    if request_count == self.nginx.null then
        return 0
    end

    return tonumber(request_count)
end

return RateLimitPool
