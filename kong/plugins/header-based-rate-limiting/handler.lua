local BasePlugin = require "kong.plugins.base_plugin"

local HeaderBasedRateLimitingHandler = BasePlugin:extend()

HeaderBasedRateLimitingHandler.PRIORITY = 2000

function HeaderBasedRateLimitingHandler:new()
    HeaderBasedRateLimitingHandler.super.new(self, "header-based-rate-limiting")
end

function HeaderBasedRateLimitingHandler:access(conf)
    HeaderBasedRateLimitingHandler.super.access(self)

    if conf.say_hello then
        ngx.log(ngx.ERR, "============ Hey World! ============")
        ngx.header["Hello-World"] = "Hey!"
    else
        ngx.log(ngx.ERR, "============ Bye World! ============")
        ngx.header["Hello-World"] = "Bye!"
    end
end

return HeaderBasedRateLimitingHandler
