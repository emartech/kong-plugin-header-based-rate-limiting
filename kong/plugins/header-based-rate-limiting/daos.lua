local singletons = require "kong.singletons"

local RateLimitModel = require "kong.plugins.header-based-rate-limiting.rate_limit_model"

local function is_null_or_exists(entity_db, entity_id)
    if not entity_id then
        return true
    end

    local res, err = entity_db:select({ id = entity_id })

    if not err and res then
        return true
    else
        return false
    end
end

local function check_whether_service_exists(service_id)
    if is_null_or_exists(singletons.db.services, service_id) then
        return true
    else
        return false, "The referenced service '" .. service_id .. "' does not exist."
    end
end

local function check_whether_route_exists(route_id)
    if is_null_or_exists(singletons.db.routes, route_id) then
        return true
    else
        return false, "The referenced route '" .. route_id .. "' does not exist."
    end
end

local function check_unique(header_composition, header_based_rate_limit)
    local model = RateLimitModel(singletons.dao.db)
    local custom_rate_limits = model:get(header_based_rate_limit.service_id, header_based_rate_limit.route_id, { header_composition })

    if #custom_rate_limits > 0 and custom_rate_limits or nil then
        return false, "A header based rate limit is already configured for this combination of service, route and header composition."
    else
        return true
    end
end

local SCHEMA = {
    primary_key = { "id" },
    table = "header_based_rate_limits",
    cache_key = { "service_id", "route_id", "header_composition" },
    fields = {
        id = { type = "id", dao_insert_value = true },
        service_id = { type = "id", func = check_whether_service_exists },
        route_id = { type = "id", func = check_whether_route_exists },
        header_composition = { type = "string", required = true, func = check_unique },
        rate_limit = { type = "number", required = true }
    }
}

return { header_based_rate_limits = SCHEMA }
