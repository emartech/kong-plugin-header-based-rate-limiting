local RateLimitPool = require "kong.plugins.header-based-rate-limiting.rate_limit_pool"

describe("#request_count", function()
    it("should raise error when redis does not respond a correctly", function()
        local redis = {
            get = function(self, key)
                return nil, 'error message'
            end
        }

        local ngx = {
            null = 'null',
            ctx = {},
            var = {},
            log = function() end,
        }

        local rate_limit_pool = RateLimitPool(redis, ngx)

        assert.has_error(function() rate_limit_pool:request_count('some_key') end, 'error message')
    end)

end)