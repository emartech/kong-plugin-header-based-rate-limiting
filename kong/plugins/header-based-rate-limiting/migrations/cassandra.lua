return {
    {
        name = "2018-08-22-153000_init_header_based_rate_limiting",
        up = [[
              CREATE TABLE IF NOT EXISTS header_based_rate_limits(
                id uuid,
                service_id uuid,
                route_id uuid,
                header_composition text,
                rate_limit int,
                PRIMARY KEY (service_id, route_id, header_composition)
              );

              CREATE INDEX ON header_based_rate_limits (id);
            ]],
        down = [[
              DROP TABLE header_based_rate_limits;
            ]]
    }
}