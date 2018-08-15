return {
    no_consumer = true,
    fields = {
        redis = {
            type = "table",
            schema = {
                fields = {
                    host = { type = "string", required = true },
                    port = { type = "number", required = true, default = 6379 },
                    db = { type = "number", required = true, default = 0 }
                }
            }
        },
        default_rate_limit = { type = "number", required = true },
        log_only = { type = "boolean", required = true, default = false }
    }
}
