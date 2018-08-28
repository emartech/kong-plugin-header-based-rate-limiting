local Object = require "classic"

local function calculate_header_compositions_with_fallback(most_specific_composition)
    local compositions = {}
    local included_headers = {}

    for _, header in ipairs(most_specific_composition) do
        table.insert(included_headers, header)
        table.insert(compositions, table.concat(included_headers, ","))
    end

    return compositions
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

local function find_applicable_rate_limit(model, service_id, route_id, entity_identifier)
    local compositions_with_fallback = calculate_header_compositions_with_fallback(entity_identifier)

    local custom_rate_limits = model:get(service_id, route_id, compositions_with_fallback)

    local most_specific_rate_limit = select_most_specific_rule(custom_rate_limits)

    return most_specific_rate_limit and most_specific_rate_limit.rate_limit
end

local RateLimitRule = Object:extend()

function RateLimitRule:new(model, default_rate_limit)
    self.model = model
    self.default_rate_limit = default_rate_limit
end

function RateLimitRule:find(service_id, route_id, subject)
    local entity_identifier = subject:encoded_identifier_array()

    local rate_limit_from_rules = find_applicable_rate_limit(self.model, service_id, route_id, entity_identifier)

    return rate_limit_from_rules or self.default_rate_limit
end

return RateLimitRule
