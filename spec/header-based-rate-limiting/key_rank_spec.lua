local KeyRank = require "kong.plugins.header-based-rate-limiting.key_rank"

describe("KeyRank", function()
    describe("#for_length", function()
        it("should return number items", function()
            local subject = KeyRank("a,b,c")
            assert.are.equal(3, subject:for_length())
        end)
    end)

    describe("#for_wildcards", function()
        it("should return number items", function()
            local subject = KeyRank("*,*,c")
            assert.are.equal(-2, subject:for_wildcards())
        end)

        it("should ignore non-wildcard segments", function()
            local subject = KeyRank("**,*,c")
            assert.are.equal(-1, subject:for_wildcards())
        end)
    end)

    describe("#<", function()
        context("when rule lenghts are different", function()
            it("should return true when the RHS is longer", function()
                local shorter = KeyRank("a,b,c")
                local longer = KeyRank("a,b,c,d")

                assert.is_truthy(shorter < longer)
            end)

            it("should return false when the LHS is longer", function()
                local shorter = KeyRank("a,b,c")
                local longer = KeyRank("a,b,c,d")

                assert.is_falsy(longer < shorter)
            end)
        end)

        context("when rules are equally long", function()
            it("should consider the one with more wildcards less specific", function()
                local more_wildcards = KeyRank("*,*,*,d")
                local less_wildcards = KeyRank("*,*,c,d")

                assert.is_truthy(more_wildcards < less_wildcards)
            end)

            it("should consider rules with the same amount of wildcards equally specific", function()
                local one = KeyRank("*,*,c,d")
                local other = KeyRank("*,*,e,f")

                assert.is_falsy(one < other)
            end)
        end)
    end)

    describe("#==", function()
        it("should return false when the both sides aren't equally long", function()
            local shorter = KeyRank("a,b,c")
            local longer = KeyRank("a,b,c,d")

            assert.is_falsy(shorter == longer)
        end)

        it("should return false when they contain different amount of wildcards", function()
            local one = KeyRank("*,*,c,d")
            local other = KeyRank("*,e,f,g")

            assert.is_falsy(one == other)
        end)

        it("should return true when they contain the same amount of wildcards and are equally long", function()
            local one = KeyRank("*,*,c,d")
            local other = KeyRank("*,*,e,f")

            assert.is_truthy(one == other)
        end)
    end)

    describe("#<=", function()
        context("when rule lenghts are different", function()
            it("should return true when the RHS is longer", function()
                local shorter = KeyRank("a,b,c")
                local longer = KeyRank("a,b,c,d")

                assert.is_truthy(shorter <= longer)
            end)

            it("should return false when the LHS is longer", function()
                local shorter = KeyRank("a,b,c")
                local longer = KeyRank("a,b,c,d")

                assert.is_falsy(longer <= shorter)
            end)
        end)

        context("when rules are equally long", function()
            it("should consider the one with more wildcards less specific", function()
                local more_wildcards = KeyRank("*,*,*,d")
                local less_wildcards = KeyRank("*,*,c,d")

                assert.is_truthy(more_wildcards <= less_wildcards)
            end)

            it("should consider rules with the same amount of wildcards equally specific", function()
                local one = KeyRank("*,*,c,d")
                local other = KeyRank("*,*,c,d")

                assert.is_truthy(one <= other)
            end)
        end)
    end)
end)
