local Object = require "classic"

local function compose_query_constraint(encoded_header_compositions)
    local constraints = {}

    for _, composition in ipairs(encoded_header_compositions) do
        table.insert(constraints, string.format("header_composition = '%s'", composition))
    end

    return table.concat(constraints, " OR ")
end

local function query_custom_rate_limits(db, service_id, route_id, encoded_header_compositions)

    local header_composition_constraint = compose_query_constraint(encoded_header_compositions)

    local query = string.format(
        [[
            SELECT *
            FROM header_based_rate_limits
            WHERE (%s) AND (%s) AND (%s)
        ]],
        (service_id and "service_id = '" .. service_id .. "'" or " service_id is NULL"),
        (route_id and "route_id = '" .. route_id .. "'" or "route_id is NULL"),
        header_composition_constraint
    )

    local custom_rate_limits, err = db:query(query)

    if not custom_rate_limits then
        error(err)
    end

    return custom_rate_limits
end

local RateLimitModel = Object:extend()

function RateLimitModel:new(db)
    self.db = db
end

function RateLimitModel:get(service_id, route_id, encoded_header_compositions)
    return query_custom_rate_limits(
        self.db,
        service_id,
        route_id,
        encoded_header_compositions
    )
end

return RateLimitModel
