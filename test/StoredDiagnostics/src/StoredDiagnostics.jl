module StoredDiagnostics

using Exceptional

const once_constructions = Ref(0)

function once_checked(input)
    @⎋ input > 0 @once begin
        once_constructions[] += 1
        DomainError(-1, "precompiled once")
    end
    return input
end

function once_roundtrip()
    try
        once_checked(-1)
    catch exception
        return exception isa DomainError && exception.msg == "precompiled once"
    end
    return false
end

function checked(input)
    @⊤⎋ input > 0 "precompiled message"
    return input
end

function roundtrip()
    try
        checked(-1)
    catch exception
        showerror(devnull, exception)
        return exception.msg == "precompiled message"
    end
    return false
end

end