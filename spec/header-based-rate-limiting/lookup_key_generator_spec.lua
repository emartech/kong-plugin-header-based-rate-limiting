local subject = require "kong.plugins.header-based-rate-limiting.lookup_key_generator"
local tablex = require "pl.tablex"

local function is_composition_included(needle, haystack)
    return tablex.find(haystack, needle) ~= nil
end

describe("LookupKeyGenerator", function()
    describe(".from_list", function()
        it("should return the only element in an array", function()
            assert.are.same({"a"}, subject.from_list({"a"}))
        end)

        it("should generate fallback compositions", function()
            local compositions_with_fallback = subject.from_list({'a', 'b'})

            assert.is_truthy(is_composition_included('a,b', compositions_with_fallback))
            assert.is_truthy(is_composition_included('a', compositions_with_fallback))
        end)

        it("should generate suffix match keys", function()
            local compositions_with_fallback = subject.from_list({'a', 'b'})

            assert.is_truthy(is_composition_included('*,b', compositions_with_fallback))
        end)
    end)
end)
