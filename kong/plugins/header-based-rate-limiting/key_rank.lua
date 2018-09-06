local Object = require "classic"

local separator = ","

local function pattern_count(pattern, string)
    local _, count = string.gsub(string, pattern, "")

    return count
end

local KeyRank = Object:extend()

function KeyRank:new(key)
    self.key = key
end

function KeyRank:for_length()
    return pattern_count(separator, self.key) + 1
end

function KeyRank:for_wildcards()
    return pattern_count("%f[%*]%*%f[^%*],", self.key) * -1
end

function KeyRank:__lt(other)
    if self:for_length() == other:for_length() then
        return self:for_wildcards() < other:for_wildcards()
    end

    return self:for_length() < other:for_length()
end

function KeyRank:__le(other)
    if self:for_length() == other:for_length() then
        return self:for_wildcards() <= other:for_wildcards()
    end

    return self:for_length() <= other:for_length()
end

function KeyRank:__eq(other)
    if self:for_length() == other:for_length() then
        return self:for_wildcards() == other:for_wildcards()
    end

    return self:for_length() == other:for_length()
end

return KeyRank
