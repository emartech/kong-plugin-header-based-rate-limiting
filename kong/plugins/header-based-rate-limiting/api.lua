local crud = require "kong.api.crud_helpers"
local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"

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

            local success, redis_or_error = pcall(RedisFactory.create, self.plugin.config.redis)

            if not success then
                return helpers.responses.send_HTTP_BAD_REQUEST(redis_or_error.message)
            end

            local result = redis_or_error:ping()

            helpers.responses.send_HTTP_OK(result)
        end
    }
}
