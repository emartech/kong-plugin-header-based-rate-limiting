return {
    {
        name = "2018-08-22-153000_init_header_based_rate_limiting",
        up = [[
              CREATE TABLE IF NOT EXISTS header_based_rate_limits(
                id uuid,
                service_id uuid REFERENCES services(id) ON DELETE CASCADE,
                route_id uuid REFERENCES routes(id) ON DELETE CASCADE,
                header_composition text,
                rate_limit integer,
                PRIMARY KEY (id),
                UNIQUE (service_id, route_id, header_composition)
              );
              CREATE INDEX IF NOT EXISTS header_based_rate_limits_header_composition_idx ON header_based_rate_limits(header_composition);
              CREATE INDEX IF NOT EXISTS header_based_rate_limits_service_id_idx ON header_based_rate_limits(service_id);
              CREATE INDEX IF NOT EXISTS header_based_rate_limits_route_id_idx ON header_based_rate_limits(route_id);
            ]],
        down = [[
              DROP TABLE header_based_rate_limits;
            ]]
    }
}
