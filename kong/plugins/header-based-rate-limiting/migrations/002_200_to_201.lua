return {
    postgres = {
        up = [[
            DO $$
            BEGIN
            UPDATE header_based_rate_limits SET cache_key = CONCAT('header_based_rate_limits', ':', service_id, ':', route_id, ':', header_composition, ':', ':') WHERE cache_key is null;
            END;
            $$;
        ]]
    },
    cassandra = {
        up = [[
            UPDATE header_based_rate_limits SET cache_key = CONCAT('header_based_rate_limits', ':', service_id, ':', route_id, ':', header_composition, ':', ':') WHERE cache_key is null;
        ]]
    }
}