local LookupKeyGenerator = {}

function LookupKeyGenerator.from_list(list)
    local compositions = {}
    local included_components = {}

    for _, header in ipairs(list) do
        table.insert(included_components, header)
        table.insert(compositions, table.concat(included_components, ","))

        if #included_components > 1 then
            local fallbacks_with_wildcards = { table.unpack(included_components) }

            for i = 1, #fallbacks_with_wildcards - 1 do
                fallbacks_with_wildcards[i] = "*"

                table.insert(compositions, table.concat(fallbacks_with_wildcards, ","))
            end
        end
    end

    return compositions
end

return LookupKeyGenerator
