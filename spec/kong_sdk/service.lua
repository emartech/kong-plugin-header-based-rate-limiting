local ResourceObject = require "spec.kong_sdk.resource_object"

local Service = ResourceObject:extend()

Service.PATH = "services"

function Service:list_routes(service_id_or_name)
    return self:request({
        method = "GET",
        path = self.PATH .. "/" .. service_id_or_name .. "/routes"
    })
end

return Service
