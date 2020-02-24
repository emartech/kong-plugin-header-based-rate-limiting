local postgres = require "kong.plugins.header-based-rate-limiting.migrations.postgres"
local cassandra = require "kong.plugins.header-based-rate-limiting.migrations.cassandra"

return {
    postgres = {
        up = postgres[1]["up"],
    },
    cassandra = {
        up = cassandra[1]["up"],
    },
}