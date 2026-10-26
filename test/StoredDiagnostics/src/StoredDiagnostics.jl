module StoredDiagnostics

using Exceptional

const once_constructions = Ref(0)

function stored_error()
    return @once begin
        once_constructions[] += 1
        DomainError(-1, "precompiled once")
    end
end

end