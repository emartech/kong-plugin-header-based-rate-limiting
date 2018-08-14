package = "kong-plugin-header-based-rate-limiting"
version = "0.1.0-1"
supported_platforms = {"linux", "macosx"}
source = {
  url = "git+https://github.com/emartech/kong-plugin-header-based-rate-limiting.git",
  tag = "0.1.0"
}
description = {
  summary = "Rate limit incoming requests based on its headers.",
  homepage = "https://github.com/emartech/kong-plugin-header-based-rate-limiting",
  license = "MIT"
}
dependencies = {
  "lua ~> 5.1",
  "classic 0.1.0-1",
  "kong-lib-logger >= 0.3.0-1"
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.header-based-rate-limiting.handler"] = "kong/plugins/header-based-rate-limiting/handler.lua",
    ["kong.plugins.header-based-rate-limiting.schema"] = "kong/plugins/header-based-rate-limiting/schema.lua",
  }
}
