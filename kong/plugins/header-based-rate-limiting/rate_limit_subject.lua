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
    local identifiers = identifier_array(self.identification_headers, self.request_headers)

    return table.concat(identifiers, ",")
end

function RateLimitSubject:encoded_identifier_array()
    local identifiers = identifier_array(self.identification_headers, self.request_headers)
    local encoded_identifiers = {}

    for _, identifier in ipairs(identifiers) do
        table.insert(encoded_identifiers, ngx.encode_base64(identifier))
    end

    return encoded_identifiers
end

return RateLimitSubject
