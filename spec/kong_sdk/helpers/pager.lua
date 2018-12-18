local Object = require "classic"

local Pager = Object:extend()

function Pager:new(page_reader)
    self.page_reader = page_reader
end

local function call_on_array(callback, array)
    for _, item in ipairs(array) do
        callback(item)
    end
end

function Pager:each(callback)
    local offset

    repeat
        local response = self.page_reader(offset)

        offset = response.offset

        call_on_array(callback, response.data or {})
    until not offset
end

return Pager
