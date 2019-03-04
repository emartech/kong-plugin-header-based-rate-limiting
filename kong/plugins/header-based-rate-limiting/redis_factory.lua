local Redis = require "resty.redis"

return {
    create = function(config)
        local redis = Redis:new()

        local redis_timeout_in_milliseconds = (config.timeout or 1000)

        local success, _ = pcall(redis.set_timeout, redis, redis_timeout_in_milliseconds)

        if not success then
            error({ msg = "Error while setting Redis timeout"})
        end

        local success, _ = redis:connect(config.host, config.port)

        if not success then
            error({ msg = "Could not connect to Redis" })
        end

        local success, _ = redis:select(config.db)

        if not success then
            error({ msg = "Could not select Redis DB" })
        end

        return redis
    end
}
