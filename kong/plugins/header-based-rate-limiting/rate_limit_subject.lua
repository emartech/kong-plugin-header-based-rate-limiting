local Object = require "classic"

local encode_base64 = ngx.encode_base64

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

function RateLimitSubject.from_request_headers(identification_headers, request_headers)
    local identifiers = identifier_array(
        identification_headers,
        request_headers or {}
    )

    return RateLimitSubject(identifiers)
end

function RateLimitSubject:new(identifiers)
    self.identifiers = identifiers
end

function RateLimitSubject:identifier()
    return table.concat(self.identifiers, ",")
end

function RateLimitSubject:encoded_identifier_array()
    local encoded_identifiers = {}

    for _, identifier in ipairs(self.identifiers) do
        table.insert(encoded_identifiers, encode_base64(identifier))
    end

    return encoded_identifiers
end

function RateLimitSubject:encoded_identifier()
    local encoded_identifiers = self:encoded_identifier_array()

    return table.concat(encoded_identifiers, ",")
end

return RateLimitSubject
