local BasePlugin = require "kong.plugins.base_plugin"

local MypluginHandler = BasePlugin:extend()

MypluginHandler.PRIORITY = 2000

function MypluginHandler:new()
  MypluginHandler.super.new(self, "myplugin")
end

function MypluginHandler:access(conf)
  MypluginHandler.super.access(self)

  if conf.say_hello then
    ngx.log(ngx.ERR, "============ Hey World! ============")
    ngx.header["Hello-World"] = "Hey!"
  else
    ngx.log(ngx.ERR, "============ Bye World! ============")
    ngx.header["Hello-World"] = "Bye!"
  end

end

return MypluginHandler
