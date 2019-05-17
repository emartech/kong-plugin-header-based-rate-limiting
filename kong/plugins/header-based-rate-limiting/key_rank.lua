local Object = require "classic"

local KeyRank = Object:extend()

function KeyRank:new(key)
    self.key = key
end

local function count_occurrences(pattern, subject)
    return select(2, subject:gsub(pattern, ""))
end

function KeyRank:count_length()
    return count_occurrences(",", self.key) + 1
end

function KeyRank:count_wildcards()
    return count_occurrences("%*", self.key)
end

function KeyRank:__lt(other)
    local self_length = self:count_length()
    local other_length = other:count_length()

    if self_length == other_length then
        return self:count_wildcards() > other:count_wildcards()
    end

    return self_length < other_length
end

function KeyRank:__eq(other)
    return self:count_length() == other:count_length() and self:count_wildcards() == other:count_wildcards()
end

function KeyRank:__le(other)
    local self_length = self:count_length()
    local other_length = other:count_length()

    if self_length == other_length then
        return self:count_wildcards() >= other:count_wildcards()
    end

    return self_length <= other_length
end

return KeyRank
