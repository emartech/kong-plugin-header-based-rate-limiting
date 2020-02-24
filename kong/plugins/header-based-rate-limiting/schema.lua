local typedefs = require "kong.db.schema.typedefs"

return {
    name = "header-based-rate-limiting",
    fields = {
        {
            consumer = typedefs.no_consumer
        },
        {
            config = {
                type = "record",
                fields = {
                    { redis = {
                        type = "record",
                        fields = {
                            { host = { type = "string", required = true } },
                            { port = { type = "number", required = true, default = 6379 } },
                            { db = { type = "number", required = true, default = 0 } },
                            { timeout_in_milliseconds = { type = "number", required = true, default = 1000 } },
                            { max_idle_timeout_in_milliseconds = { type = "number", required = true, default = 1000 } },
                            { pool_size = { type = "number", required = true, default = 10 } }
                        }
                    } },
                    { default_rate_limit = { type = "number", required = true } },
                    { log_only = { type = "boolean", required = true, default = false } },
                    { identification_headers = {
                        type = "array",
                        required = true,
                        elements = {
                            type = "string"
                        }
                    } },
                    { forward_headers_to_upstream = { type = "boolean", default = false } }
                }
            }
        }
    }
}
