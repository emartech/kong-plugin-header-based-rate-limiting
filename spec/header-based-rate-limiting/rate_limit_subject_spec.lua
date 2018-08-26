local RateLimitSubject = require "kong.plugins.header-based-rate-limiting.rate_limit_subject"

describe("RateLimitSubject", function()
    describe("#identifier", function()
        context("when only one header is used", function()
            it("should return the content of the header", function()
                local headers = {
                    ["x-some-header"] = "some_consumer",
                    ["x-unused-headr"] = "some_irrelevant_value"
                }

                local subject = RateLimitSubject({ "x-some-header" }, headers)
                assert.are.equal("some_consumer", subject:identifier())
            end)

            context("when no identification header is present", function()
                it("should return empty string", function()
                    local subject = RateLimitSubject({ "x-some-header" }, {})
                    assert.are.equal("", subject:identifier())
                end)
            end)
        end)

        context("when multiple headers are used", function()
            it("should compose an identifier from the given headers", function()
                local headers = {
                    ["x-some-header"] = "some_consumer",
                    ["x-another-header"] = "some_additional_data"
                }

                local subject = RateLimitSubject({ "x-some-header", "x-another-header" }, headers)

                assert.are.equal(
                    "some_consumer,some_additional_data",
                    subject:identifier()
                )
            end)

            context("when one or more identifier headers are missing", function()
                it("should use empty string instead of them", function()
                    local headers = {
                        ["x-some-header"] = "some_consumer",
                        ["x-another-header"] = "some_additional_data"
                    }

                    local subject = RateLimitSubject({ "x-some-header", "x-another-header", "x-yet-another-header" }, headers)

                    assert.are.equal(
                        "some_consumer,some_additional_data,",
                        subject:identifier()
                    )
                end)
            end)
        end)

        context("when an identifier header is present multiple times", function()
            it("should add the last occurence to the composition", function()
                local headers = {
                    ["x-some-header"] = "some_consumer",
                    ["x-another-header"] = { "some_additional_data", "yet_another_additional_data" }
                }

                local subject = RateLimitSubject({ "x-some-header", "x-another-header" }, headers)

                assert.are.equal(
                    "some_consumer,yet_another_additional_data",
                    subject:identifier()
                )
            end)
        end)

        context("when there are no request headers", function()
            it("should return an empty string", function()
                local subject = RateLimitSubject({ "x-some-header" }, nil)

                assert.are.equal("", subject:identifier())
            end)
        end)
    end)

    describe("#encoded_identifier_array", function()
        context("when only one header is used", function()
            it("should return the content of the header", function()
                local headers = {
                    ["x-some-header"] = "some_consumer",
                    ["x-unused-headr"] = "some_irrelevant_value"
                }

                local subject = RateLimitSubject({ "x-some-header" }, headers)

                assert.are.same({ ngx.encode_base64("some_consumer") }, subject:encoded_identifier_array())
            end)

            context("when no identification header is present", function()
                it("should return empty string", function()
                    local subject = RateLimitSubject({ "x-some-header" }, {})

                    assert.are.same({ "" }, subject:encoded_identifier_array())
                end)
            end)
        end)

        context("when multiple headers are used", function()
            it("should compose an identifier from the given headers", function()
                local headers = {
                    ["x-some-header"] = "some_consumer",
                    ["x-another-header"] = "some_additional_data"
                }

                local subject = RateLimitSubject({ "x-some-header", "x-another-header" }, headers)

                assert.are.same(
                    { ngx.encode_base64("some_consumer"), ngx.encode_base64("some_additional_data") },
                    subject:encoded_identifier_array()
                )
            end)

            context("when one or more identifier headers are missing", function()
                it("should use empty string instead of them", function()
                    local headers = {
                        ["x-some-header"] = "some_consumer",
                        ["x-another-header"] = "some_additional_data"
                    }

                    local subject = RateLimitSubject({ "x-some-header", "x-another-header", "x-yet-another-header" }, headers)

                    assert.are.same(
                        { ngx.encode_base64("some_consumer"), ngx.encode_base64("some_additional_data"), "" },
                        subject:encoded_identifier_array()
                    )
                end)
            end)
        end)

        context("when an identifier header is present multiple times", function()
            it("should add the last occurence to the composition", function()
                local headers = {
                    ["x-some-header"] = "some_consumer",
                    ["x-another-header"] = { "some_additional_data", "yet_another_additional_data" }
                }

                local subject = RateLimitSubject({ "x-some-header", "x-another-header" }, headers)

                assert.are.same(
                    { ngx.encode_base64("some_consumer"), ngx.encode_base64("yet_another_additional_data") },
                    subject:encoded_identifier_array()
                )
            end)
        end)

        context("when there are no request headers", function()
            it("should return an empty string", function()
                local subject = RateLimitSubject({ "x-some-header" }, nil)

                assert.are.same({ "" }, subject:encoded_identifier_array())
            end)
        end)
    end)
end)
