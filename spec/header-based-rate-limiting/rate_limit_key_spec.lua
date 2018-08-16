local RateLimitKey = require "kong.plugins.header-based-rate-limiting.rate_limit_key"

describe("#generate", function()
    it("should generate a key starting with 'ratelimit'", function()
        assert.has_match("^ratelimit:", RateLimitKey.generate("", {}))
    end)

    it("should generate a key containing customer identifier'", function()
        local consumer_identifier = "test_user"

        assert.has_match(":" .. consumer_identifier .. ":", RateLimitKey.generate(consumer_identifier, {}))
    end)

    it("should generate a key containing the route and service, the plugin is attached to", function()
        local plugin_config = {
            route_id = "route",
            service_id = "service"
        }

        assert.has_match(":service:route:", RateLimitKey.generate("", plugin_config))
    end)

    context("when the plugin is attached to a service", function()
        it("should leave the route ID blank", function()
            local plugin_config = {
                service_id = "service"
            }

            assert.has_match(":service::", RateLimitKey.generate("", plugin_config))
        end)
    end)

    context("when the plugin is attached to a route", function()
        it("should leave the service ID blank", function()
            local plugin_config = {
                route_id = "route"
            }

            assert.has_match("::route:", RateLimitKey.generate("", plugin_config))
        end)
    end)

    it("should generate a key containing part in the rigth order", function()
        local plugin_config = {
            route_id = "route",
            service_id = "service"
        }

        local consumer_identifier = 'test_user'

        assert.has_match("ratelimit:" .. consumer_identifier .. ":service:route:", RateLimitKey.generate(consumer_identifier, plugin_config))
    end)

    it("should generate a key containing the actual time with minute precision", function()

        local actual_time = os.time()
        local formatted_time = os.date("!%Y%m%dT%H%M00Z", actual_time)

        assert.has_match("ratelimit::::" .. formatted_time, RateLimitKey.generate('', {}, actual_time))
    end)

end)
