local ResourceObject = require "spec.kong_sdk.resource_object"

local Route = ResourceObject:extend()

Route.PATH = "routes"

function Route:create_for_service(service_id, ...)
    return self:create({
        service = {
            id = service_id
        },
        paths = { ... }
    })
end

function Route:add_plugin(route_id, plugin_data)
    return self:request({
        method = "POST",
        path = self.PATH .. "/" .. route_id .. "/plugins",
        body = plugin_data
    })
end

return Route
