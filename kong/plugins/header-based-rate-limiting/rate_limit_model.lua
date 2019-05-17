local Object = require "classic"
local get_null_uuid = require "kong.plugins.header-based-rate-limiting.get_null_uuid"

local query_many_compositions = "SELECT * FROM header_based_rate_limits WHERE service_id = ? AND route_id = ? AND header_composition IN ?"
local query_one_composition = "SELECT * FROM header_based_rate_limits WHERE service_id = ? AND route_id = ? AND header_composition = ?"

local function header_composition_constraint(encoded_header_compositions)
    local constraints = {}

    for _, composition in ipairs(encoded_header_compositions) do
        table.insert(constraints, string.format("header_composition = '%s'", composition))
    end

    return table.concat(constraints, " OR ")
end

local query_strategies = {
    cassandra = function(db, service_id, route_id, encoded_header_compositions)
        local prepared_query, header_composition

        if #encoded_header_compositions == 1 then
            prepared_query = query_one_composition
            header_composition = encoded_header_compositions[1]
        else
            prepared_query = query_many_compositions
            header_composition = encoded_header_compositions
        end

        return db:query(prepared_query, {
            db.cassandra.uuid(service_id or get_null_uuid(db.name)),
            db.cassandra.uuid(route_id or get_null_uuid(db.name)),
            header_composition
        })
    end,

    postgres = function(db, service_id, route_id, encoded_header_compositions)
        return db:query(string.format(
            "SELECT * FROM header_based_rate_limits WHERE (%s) AND (%s) AND (%s)",
            (service_id and ("service_id = '%s'"):format(service_id) or "service_id is NULL"),
            (route_id and ("route_id = '%s'"):format(route_id) or "route_id is NULL"),
            header_composition_constraint(encoded_header_compositions)
        ))
    end
}

local function query_custom_rate_limits(db, service_id, route_id, encoded_header_compositions)
    local query_strategy = query_strategies[db.name]
    local custom_rate_limits, err = query_strategy(db, service_id, route_id, encoded_header_compositions)

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
