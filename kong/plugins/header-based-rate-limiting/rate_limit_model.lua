local Object = require "classic"
local utils = require "kong.tools.utils"

local function compose_query_constraint(compositions_with_fallback)
    local constraints = {}

    for _, composition in ipairs(compositions_with_fallback) do
        table.insert(constraints, string.format("header_composition = '%s'", composition))
    end

    return table.concat(constraints, " OR ")
end

local function query_custom_rate_limits(db, service_id, route_id, header_compositions)

    local header_composition_constraint = compose_query_constraint(header_compositions)

    local query = string.format(
        [[
            SELECT *
            FROM header_based_rate_limits
            WHERE service_id = %s AND route_id = %s AND (%s)
        ]],
        (service_id and "'" .. service_id .. "'" or "NULL"),
        (route_id and "'" .. route_id .. "'" or "NULL"),
        header_composition_constraint
    )

    local custom_rate_limits = db:query(query)

    return custom_rate_limits
end

local RateLimitModel = Object:extend()

function RateLimitModel:new(db)
    self.db = db
end

function RateLimitModel:get(service_id, route_id, header_composition)
    local custom_rate_limits = query_custom_rate_limits(self.db, service_id, route_id, header_composition)

    return custom_rate_limits
end

function RateLimitModel.decode_header_composition(encoded_header_composition)
    local individual_headers = utils.split(encoded_header_composition, ":")

    local decoded_headers = {}

    for _, header in ipairs(individual_headers) do
        table.insert(decoded_headers, ngx.decode_base64(header))
    end

    return decoded_headers
end

function RateLimitModel.encode_header_composition(header_composition)
    local encoded_headers = {}

    for _, header in ipairs(header_composition) do
        table.insert(encoded_headers, ngx.encode_base64(header))
    end

    return table.concat(encoded_headers, ":")
end

return RateLimitModel
