local RateLimitKey = {}

function RateLimitKey.generate(customer_identifier, config)
    return "ratelimit:" .. customer_identifier .. ":" .. (config.service_id or "") .. ":" .. (config.route_id or "") .. ":"
end

return RateLimitKey
