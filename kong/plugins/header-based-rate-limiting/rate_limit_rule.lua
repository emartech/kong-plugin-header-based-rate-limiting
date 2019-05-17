local Object = require "classic"
local LookupKeyGenerator = require "kong.plugins.header-based-rate-limiting.lookup_key_generator"
local KeyRank = require "kong.plugins.header-based-rate-limiting.key_rank"

local function select_most_specific_rule(rules)
    local most_specific = rules[1]

    for i = 2, #rules do
        local rule = rules[i]
        if KeyRank(most_specific.header_composition) < KeyRank(rule.header_composition) then
            most_specific = rule
        end
    end

    return most_specific
end

local function find_applicable_rate_limit(model, service_id, route_id, entity_identifier)
    local compositions_with_fallback = LookupKeyGenerator.from_list(entity_identifier)
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
