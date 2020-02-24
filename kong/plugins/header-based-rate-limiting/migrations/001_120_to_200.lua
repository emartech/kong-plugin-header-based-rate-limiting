return {
    postgres = {
        up = [[
            DO $$
            BEGIN
            ALTER TABLE IF EXISTS ONLY "header_based_rate_limits" ADD "cache_key" TEXT UNIQUE;
            EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
            END;
            $$;
        ]]
    },
    cassandra = {
        up = [[
            ALTER TABLE header_based_rate_limits ADD cache_key text;
            CREATE INDEX IF NOT EXISTS ON header_based_rate_limits (cache_key);
        ]]
    }
}