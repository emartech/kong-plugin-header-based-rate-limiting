local crud = require "kong.api.crud_helpers"
local Redis = require "resty.redis"

return {
    ["/plugins/:plugin_id/redis-ping"] = {
        before = function(self, dao_factory, helpers)
            crud.find_plugin_by_filter(self, dao_factory, {
                id = self.params.plugin_id
            }, helpers)
        end,

        GET = function(self, dao_factory, helpers)
            if self.plugin.name ~= "header-based-rate-limiting" then
                return helpers.responses.send_HTTP_BAD_REQUEST("Plugin is not of type header-based-rate-limiting")
            end

            local redis = Redis:new()

            local success, _ = redis:connect(
                self.plugin.config.redis.host,
                self.plugin.config.redis.port
            )

            if not success then
                return helpers.responses.send_HTTP_BAD_REQUEST("Could not connect to Redis")
            end

            local success, _ = redis:select(self.plugin.config.redis.db)

            if not success then
                return helpers.responses.send_HTTP_BAD_REQUEST("Could not select Redis DB")
            end

            local result = redis:ping()

            helpers.responses.send_HTTP_OK(result)
        end
    }
}
