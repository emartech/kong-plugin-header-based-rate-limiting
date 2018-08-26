local Object = require "classic"

local singletons = require "kong.singletons"

local function create_encoded_identifier_array(identification_headers, request_headers)
    local composition = {}

    for _, header_name in ipairs(identification_headers) do
        local encoded_header = ngx.encode_base64(request_headers[header_name])
        table.insert(composition, encoded_header)
    end

    return composition
end

local function calculate_header_compositions_with_fallback(most_specific_composition)
    local compositions = {}
    local included_headers = {}

    for _, header in ipairs(most_specific_composition) do
        table.insert(included_headers, header)
        table.insert(compositions, table.concat(included_headers, ":"))
    end

    return compositions
end

local function compose_query_constraint(compositions_with_fallback)
    local constraints = {}

    for _, composition in ipairs(compositions_with_fallback) do
        table.insert(constraints, string.format("header_composition = '%s'", composition))
    end

    return table.concat(constraints, " OR ")
end

local function select_most_specific_rule(rules)
    local most_specific_one

    for _, rule in ipairs(rules) do
        if not most_specific_one or string.len(rule.header_composition) > string.len(most_specific_one) then
            most_specific_one = rule
        end
    end

    return most_specific_one
end

local function find_applicable_rate_limit(service_id, route_id, entity_identifier)
    local compositions_with_fallback = calculate_header_compositions_with_fallback(entity_identifier)

    local header_composition_constraint = compose_query_constraint(compositions_with_fallback)

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

    local custom_rate_limits = singletons.dao.db:query(query)

    local most_specific_rate_limit = select_most_specific_rule(custom_rate_limits)

    return most_specific_rate_limit and most_specific_rate_limit.rate_limit
end

local RateLimitRule = Object:extend()

function RateLimitRule:new(identification_headers, default_rate_limit)
    self.identification_headers = identification_headers
    self.default_rate_limit = default_rate_limit
end

function RateLimitRule:find(service_id, route_id, headers)
    local entity_identifier = create_encoded_identifier_array(self.identification_headers, headers)

    local rate_limit_from_rules = find_applicable_rate_limit(service_id, route_id, entity_identifier)

    return rate_limit_from_rules or self.default_rate_limit
end

return RateLimitRule
