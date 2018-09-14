local Redis = require "resty.redis"

return {
    create = function(config)
        local redis = Redis:new()

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
