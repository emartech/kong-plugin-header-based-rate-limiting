local helpers = require "spec.helpers"
local cjson = require "cjson"
local TestHelper = require "spec.test_helper"

local function get_response_body(response)
  local body = assert.res_status(201, response)
  return cjson.decode(body)
end

local function setup_test_env()
  helpers.dao:truncate_tables()

  local service = get_response_body(TestHelper.setup_service())
  local route = get_response_body(TestHelper.setup_route_for_service(service.id))
  local plugin = get_response_body(TestHelper.setup_plugin_for_service(service.id, 'myplugin'))
  local consumer = get_response_body(TestHelper.setup_consumer('TestUser'))
  return service, route, plugin, consumer
end

describe("Plugin: myplugin (access)", function()

  setup(function()
    helpers.start_kong({ custom_plugins = 'myplugin' })
  end)

  teardown(function()
    helpers.stop_kong(nil)
  end)

  describe("Admin API", function()
    local service, route, plugin, consumer

    before_each(function()
      service, route, plugin, consumer = setup_test_env()
    end)

    it("registered the plugin globally", function()
      local res = assert(helpers.admin_client():send {
        method = "GET",
        path = "/plugins/" .. plugin.id,
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.is_table(json)
      assert.is_not.falsy(json.enabled)
    end)

    it("registered the plugin for the api", function()
      local res = assert(helpers.admin_client():send {
        method = "GET",
        path = "/plugins/" ..plugin.id,
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_equal(api_id, json.api_id)
    end)
  end)

  describe("Response", function()
    local service, route, plugin, consumer

    before_each(function()
      service, route, plugin, consumer = setup_test_env()
    end)

    it("added the header", function()
      local res = assert(helpers.proxy_client():send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "test1.com"
        }
      })

      assert.res_status(200, res)
      assert.response(res).has.header("Hello-World")
      local header_value = res.headers["Hello-World"]
      assert.is_equal("Hey!", header_value)
    end)
  end)

end)
