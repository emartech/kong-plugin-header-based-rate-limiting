local plugin_handler = require "kong.plugins.header-based-rate-limiting.handler"

describe("header-based-rate-limiting plugin", function()
    local old_ngx = _G.ngx
    local mock_config
    local handler

    before_each(function()
        local stubbed_ngx = {
            ERR = "ERROR:",
            header = {},
            log = function() end,
            say = function() end,
            exit = function() end
        }

        _G.ngx = stubbed_ngx

        stub(stubbed_ngx, "say")
        stub(stubbed_ngx, "exit")
        stub(stubbed_ngx, "log")

        handler = plugin_handler()
    end)

    after_each(function()
        _G.ngx = old_ngx
    end)

    describe("#access", function()
        it("should ...", function()
        end)
    end)
end)
