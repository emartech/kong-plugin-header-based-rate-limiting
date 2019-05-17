local LookupKeyGenerator = require "kong.plugins.header-based-rate-limiting.lookup_key_generator"

local function is_composition_included(needle, haystack)
    for _, current_composition in pairs(haystack) do
        if current_composition == needle then
            return true
        end
    end

    return false
end

describe("LookupKeyGenerator", function()

    describe(".from_list", function()

        it("should return the only element in an array", function()
            assert.are.same({"a"}, LookupKeyGenerator.from_list({"a"}))
        end)

        it("should generate fallback compositions", function()
            local compositions_with_fallback = LookupKeyGenerator.from_list({"a", "b"})

            assert.is_true(is_composition_included("a,b", compositions_with_fallback))
            assert.is_true(is_composition_included("a", compositions_with_fallback))
        end)

        it("should generate suffix match keys", function()
            local compositions_with_fallback = LookupKeyGenerator.from_list({"a", "b"})

            assert.is_true(is_composition_included("*,b", compositions_with_fallback))
        end)

        it("should generate all possible matches", function()
            local compositions_with_fallback = LookupKeyGenerator.from_list({"a", "b", "c"})

            local all_matchers = {
                "a",
                "a,b",
                "*,b",
                "a,b,c",
                "*,b,c",
                "*,*,c"
            }

            assert.are.same(all_matchers, compositions_with_fallback)
        end)

    end)

end)
