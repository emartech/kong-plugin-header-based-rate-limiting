local ConsumerIdentifier = {}

local function header_content(header)
    if type(header) == "table" then
        return table.concat(header, ",")
    end

    return header or ""
end

function ConsumerIdentifier.generate(identifier_keys, request_headers)
    request_headers = request_headers or {}
    local identifier_values = {}

    for _, value in ipairs(identifier_keys) do
        table.insert(identifier_values, header_content(request_headers[value]))
    end

    return table.concat(identifier_values, ",")
end

return ConsumerIdentifier
