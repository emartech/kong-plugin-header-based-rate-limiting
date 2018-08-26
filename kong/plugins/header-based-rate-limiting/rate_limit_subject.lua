local Object = require "classic"

local function header_content(header)
    if type(header) == "table" then
        return header[#header]
    end

    return header or ""
end

local function identifier_array(identification_headers, request_headers)
    local result = {}

    for _, header_name in ipairs(identification_headers) do
        table.insert(result, header_content(request_headers[header_name]))
    end

    return result
end

local RateLimitSubject = Object:extend()

function RateLimitSubject:new(identification_headers, request_headers)
    self.identification_headers = identification_headers
    self.request_headers = request_headers or {}
end

function RateLimitSubject:identifier()
    local identifier_values = identifier_array(self.identification_headers, self.request_headers)

    return table.concat(identifier_values, ",")
end

return RateLimitSubject
