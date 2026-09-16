module StoredDiagnostics

using Exceptional

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