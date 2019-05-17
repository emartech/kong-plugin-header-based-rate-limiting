local RateLimitKey = {}

function RateLimitKey.generate(customer_identifier, config, actual_time)
    return ("ratelimit:%s:%s:%s:%s"):format(
        customer_identifier,
        config.service_id or "",
        config.route_id or "",
        os.date("!%Y%m%dT%H%M00Z", actual_time)
    )
end

return RateLimitKey
