local Object = require "classic"
local kong_helpers = require "spec.helpers"
local cjson = require "cjson"

local Service = require "spec.kong_sdk.service"
local Route = require "spec.kong_sdk.route"
local Plugin = require "spec.kong_sdk.plugin"
local Consumer = require "spec.kong_sdk.consumer"

local KongSdk = Object:extend()

local function patch_http_client(http_client, transform_response)
    local new_http_client = {}

    function new_http_client:send(request)
        local response, err = http_client:send(request)

        if transform_response then
            return transform_response(request, response, err)
        end

        return response, err
    end

    return new_http_client
end

function KongSdk:new(config)
    self.http_client = patch_http_client(config.http_client, config.transform_response)

    self.services = Service(self.http_client)
    self.routes = Route(self.http_client)
    self.plugins = Plugin(self.http_client)
    self.consumers = Consumer(self.http_client)
end

local function is_error(response)
    return response.status >= 400 or response.status < 100
end

local function try_decode(raw_body)
    local parsed_body = {}

    if #raw_body > 0 then
        parsed_body = cjson.decode(raw_body)
    end

    return parsed_body
end

local function handle_admin_client_response(request, response, err)
    assert(response, err)

    local raw_body = assert(response:read_body())

    if is_error(response) then
        error(table.concat({ request.method, request.path, response.status, raw_body }, " "))
    end

    return try_decode(raw_body)
end

function KongSdk.from_admin_client()
    return KongSdk({
        http_client = kong_helpers.admin_client(),
        transform_response = handle_admin_client_response
    })
end

return KongSdk
