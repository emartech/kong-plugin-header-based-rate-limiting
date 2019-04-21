local null_uuid_per_db_type = {
    cassandra = "00000000-0000-0000-0000-000000000000",
    postgres = nil
}

local function get_null_uuid(db_type)
    return null_uuid_per_db_type[db_type]
end

return get_null_uuid
