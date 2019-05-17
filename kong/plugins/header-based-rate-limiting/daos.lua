local utils = require "kong.tools.utils"
local RateLimitModel = require "kong.plugins.header-based-rate-limiting.rate_limit_model"
local get_null_uuid = require "kong.plugins.header-based-rate-limiting.get_null_uuid"

local function is_null_or_exists(entity_db, entity_id)
    if not entity_id or entity_id == get_null_uuid(kong.db.strategy) then
        return true
    end

    local res, err = entity_db:select({ id = entity_id })

    if not err and res then
        return true
    end

    return false
end

local function check_whether_service_exists(service_id)
    if is_null_or_exists(kong.db.services, service_id) then
        return true
    end

    return false, ("The referenced service '%s' does not exist."):format(service_id)
end

local function check_whether_route_exists(route_id)
    if is_null_or_exists(kong.db.routes, route_id) then
        return true
    end

    return false, ("The referenced route '%s' does not exist."):format(route_id)
end

local function check_infix(encoded_header_composition)
    local individual_headers = utils.split(encoded_header_composition, ",")
    local prev_header

    for _, header in ipairs(individual_headers) do
        if header == "*" and prev_header ~= nil and prev_header ~= "*" then
            return false, "Infix wildcards are not allowed in a header composition."
        end

        prev_header = header
    end

    return true
end

local function check_unique(encoded_header_composition, header_based_rate_limit)
    local model = RateLimitModel(kong.dao.db)
    local custom_rate_limits = model:get(
        header_based_rate_limit.service_id,
        header_based_rate_limit.route_id,
        {
            encoded_header_composition
        }
    )

    if #custom_rate_limits == 0 then
        return true
    end

    return false, "A header based rate limit is already configured for this combination of service, route and header composition."
end

local function validate_header_composition(encoded_header_composition, header_based_rate_limit)
    local valid, error_message = check_infix(encoded_header_composition)

    if not valid then
        return false, error_message
    end

    return check_unique(encoded_header_composition, header_based_rate_limit)
end

local db_type = kong and kong.configuration.database or "postgres"
local primary_key = { "id" }

if db_type == "cassandra" then
    primary_key = { "service_id", "route_id", "header_composition" }
end

local SCHEMA = {
    primary_key = primary_key,
    table = "header_based_rate_limits",
    cache_key = { "service_id", "route_id", "header_composition" },
    fields = {
        id = { type = "id", dao_insert_value = true },
        service_id = { type = "id", func = check_whether_service_exists, default = get_null_uuid(db_type) },
        route_id = { type = "id", func = check_whether_route_exists, default = get_null_uuid(db_type) },
        header_composition = { type = "string", required = true, func = validate_header_composition },
        rate_limit = { type = "number", required = true }
    }
}

return { header_based_rate_limits = SCHEMA }
