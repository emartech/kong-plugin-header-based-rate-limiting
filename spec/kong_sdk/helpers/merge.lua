local function copy_fields_to(target, original)
    for key, value in pairs(original) do
        target[key] = value
    end
end

local function shallow_merge(target, ...)
    for _, object in ipairs({...}) do
        if object then
            copy_fields_to(target, object)
        end
    end

    return target
end

return {
    shallow_merge = shallow_merge
}
