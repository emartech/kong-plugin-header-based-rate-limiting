local ResourceObject = require "spec.kong_sdk.resource_object"

local Plugin = ResourceObject:extend()

Plugin.PATH = "plugins"

function Plugin:list_enabled()
    local response = self:request({
        method = "GET",
        path = self.PATH .. "/enabled"
    })

    return response.enabled_plugins
end

function Plugin:get_schema(plugin_name)
    return self:request({
        method = "GET",
        path = self.PATH .. "/schema/" .. plugin_name
    })
end

return Plugin
