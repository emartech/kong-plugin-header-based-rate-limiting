local cjson = require "cjson"
local endpoints = require "kong.api.endpoints"
local split = require("kong.tools.utils").split
local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"

local decode_base64 = ngx.decode_base64
local encode_base64 = ngx.encode_base64
local escape_uri    = ngx.escape_uri
local null          = ngx.null

local header_based_rate_limits_schema = kong.db.header_based_rate_limits.schema

local function decode_headers(encoded_header_composition)
    local individual_headers = split(encoded_header_composition, ",")
    local decoded_headers = {}

    for _, header in ipairs(individual_headers) do
        local decoded_header = header == "*" and "*" or decode_base64(header)

        table.insert(decoded_headers, decoded_header)
    end

    return decoded_headers
end

local function decode_header_composition(header_based_rate_limit)
    local result = {}

    for key, value in pairs(header_based_rate_limit) do
        if key == "header_composition" then
            result["header_composition"] = decode_headers(value)
        else
            result[key] = value
        end
    end

    return result
end

local function is_wildcard(header)
    return header == "*" or header == cjson.null
end

local function encode_headers(header_composition)
    local encoded_headers = {}

    for _, header in ipairs(header_composition) do
        local encoded_header = is_wildcard(header) and "*" or encode_base64(header)

        table.insert(encoded_headers, encoded_header)
    end

    return table.concat(encoded_headers, ",")
end

local function trim_postfix_wildcards(encoded_header_composition)
    return select(1, encoded_header_composition:gsub("[,*]+$", ""))
end

local function encode_header_composition(header_based_rate_limit)
    local result = {}

    for key, value in pairs(header_based_rate_limit) do
        if key == "header_composition" then
            result["header_composition"] = trim_postfix_wildcards(encode_headers(value))
        else
            result[key] = value
        end
    end

    return result
end

local function post_process_collection(collection, post_process)
    local processed_collection = {}
    for _, item in ipairs(collection) do
        local processed_item = post_process(item)
        table.insert(processed_collection, processed_item)
    end
    return processed_collection
end

local function get_collection_endpoint_with_post_process(schema, foreign_schema, foreign_field_name, method)
    return not foreign_schema and function(self, db, helpers, post_process)
        local next_page_tags = ""

        local args = self.args.uri
        if args.tags then
            next_page_tags = "&tags=" .. (type(args.tags) == "table" and args.tags[1] or args.tags)
        end

        local data, _, err_t, offset = endpoints.page_collection(self, db, schema, method)
        if err_t then
            return endpoints.handle_error(err_t)
        end

        local next_page = offset and string.format("/%s?offset=%s%s",
            schema.admin_api_name or
            schema.name,
            escape_uri(offset),
            next_page_tags) or null

        if post_process then
            data = post_process_collection(data, post_process)
        end

        return kong.response.exit(200, {
            data   = data,
            offset = offset,
            next   = next_page,
        })

    end or function(self, db, helpers, post_process)
        local foreign_entity, _, err_t = endpoints.select_entity(self, db, foreign_schema)
        if err_t then
            return endpoints.handle_error(err_t)
        end

        if not foreign_entity then
            return kong.response.exit(404, { message = "Not found" })
        end

        self.params[schema.name] = foreign_schema:extract_pk_values(foreign_entity)

        local method = method or "page_for_" .. foreign_field_name
        local data, _, err_t, offset = endpoints.page_collection(self, db, schema, method)
        if err_t then
            return endpoints.handle_error(err_t)
        end

        local foreign_key = self.params[foreign_schema.name]
        local next_page = offset and string.format("/%s/%s/%s?offset=%s",
            foreign_schema.admin_api_name or
            foreign_schema.name,
            foreign_key,
            schema.admin_api_nested_name or
            schema.admin_api_name or
            schema.name,
            escape_uri(offset)) or null

        if post_process then
            data = post_process_collection(data, post_process)
        end

        return kong.response.exit(200, {
            data   = data,
            offset = offset,
            next   = next_page,
        })
    end
end

return {
    ["/plugins/:plugins/redis-ping"] = {
        schema = header_based_rate_limits_schema,
        methods = {
            before = function(self, db, helpers)
                local plugin, _, err_t = endpoints.select_entity(self, db, kong.db.plugins.schema)
                if err_t then
                    return endpoints.handle_error(err_t)
                end
                if not plugin then
                    return kong.response.exit(404, { message = "Not found" })
                end
                self.plugin = plugin
            end,
            GET = function(self, db, helpers)
                if self.plugin.name ~= "header-based-rate-limiting" then
                    return kong.response.exit(400, { message = "Plugin is not of type header-based-rate-limiting" })
                end

                local success, redis_or_error = pcall(RedisFactory.create, self.plugin.config.redis)
                if not success then
                    return kong.response.exit(400, { message = redis_or_error.msg })
                end

                local result = redis_or_error:ping()
                return kong.response.exit(200, { message = result })
            end
        }
    },

    ["/header-based-rate-limits"] = {
        schema = header_based_rate_limits_schema,
        methods = {
            POST = function(self, db, helpers)
                self.args.post = encode_header_composition(self.args.post)
                return endpoints.post_collection_endpoint(header_based_rate_limits_schema)(self, db, helpers, decode_header_composition)
            end,
            GET = function(self, db, helpers)
                return get_collection_endpoint_with_post_process(header_based_rate_limits_schema)(self, db, helpers, decode_header_composition)
            end,
            DELETE = function(self, db, helpers)
                db.header_based_rate_limits:truncate()
                return kong.response.exit(200)
            end
        }
    },

    ["/header-based-rate-limits/:header_based_rate_limits"] = {
        schema = header_based_rate_limits_schema,
        methods = {
            before = function(self, db, helpers)
                local header_based_rate_limit, _, err_t = endpoints.select_entity(self, db, header_based_rate_limits_schema)
                if err_t then
                    return endpoints.handle_error(err_t)
                end
                if not header_based_rate_limit then
                    return kong.response.exit(404, { message = "Resource does not exist" })
                end
            end,
            DELETE = function(self, db, helpers)
                return endpoints.delete_entity_endpoint(header_based_rate_limits_schema)(self, db, helpers)
            end
        }
    }
}
