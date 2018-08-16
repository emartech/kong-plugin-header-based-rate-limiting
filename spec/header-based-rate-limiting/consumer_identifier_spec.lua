local ConsumerIdentifier = require "kong.plugins.header-based-rate-limiting.consumer_identifier"

describe("#generate", function()
    context("when only one header is used", function()
        it("should return the content of the header", function()
            local headers = {
                ["x-some-header"] = "some_consumer"
            }
            assert.are.equal("some_consumer", ConsumerIdentifier.generate({ "x-some-header" }, headers))
        end)

        context("when no identification header is present", function()
            it("should return empty string", function()
                assert.are.equal("", ConsumerIdentifier.generate({ "x-some-header" }, {}))
            end)
        end)
    end)

    context("when multiple headers are used", function()
        it("should compose an identifier from the given headers", function()
            local headers = {
                ["x-some-header"] = "some_consumer",
                ["x-another-header"] = "some_additional_data"
            }
            assert.are.equal(
                "some_consumer,some_additional_data",
                ConsumerIdentifier.generate({ "x-some-header", "x-another-header" }, headers)
            )
        end)

        context("when one or more identifier headers are missing", function()
            it("should use empty string instead of them", function()
                local headers = {
                    ["x-some-header"] = "some_consumer",
                    ["x-another-header"] = "some_additional_data"
                }
                assert.are.equal(
                    "some_consumer,some_additional_data,",
                    ConsumerIdentifier.generate({ "x-some-header", "x-another-header", "x-yet-another-header" }, headers)
                )
            end)
        end)
    end)

    context("when an identifier header is present multiple times", function()
        it("should add all occurances to the composition", function()
            local headers = {
                ["x-some-header"] = "some_consumer",
                ["x-another-header"] = { "some_additional_data", "yet_another_additional_data" }
            }
            assert.are.equal(
                "some_consumer,some_additional_data,yet_another_additional_data",
                ConsumerIdentifier.generate({ "x-some-header", "x-another-header" }, headers)
            )
        end)
    end)

    context("when there are no request headers", function()
        it("should return an empty string", function()
            assert.are.equal("", ConsumerIdentifier.generate({ "x-some-header" }, nil))
        end)
    end)
end)
