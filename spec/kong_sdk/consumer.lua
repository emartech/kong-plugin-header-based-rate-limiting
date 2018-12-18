local ResourceObject = require "spec.kong_sdk.resource_object"

local Consumer = ResourceObject:extend()

Consumer.PATH = "consumers"

return Consumer
