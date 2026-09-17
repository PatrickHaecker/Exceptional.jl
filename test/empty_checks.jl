using Exceptional
using Test

module EmptyCheckSites
using Exceptional

struct ObservedCollection
    empty::Bool
    calls::Base.RefValue{Int}
end

function Base.isempty(collection::ObservedCollection)
    collection.calls[] += 1
    return collection.empty
end

nonempty(collection) = (result = @⦱ collection; (:continued, result))
empty(collection) = (result = @∅ collection; (:continued, result))
nonempty_fallback(collection, fallback) = (result = @⦱ collection fallback; (:continued, result))
empty_fallback(collection, fallback) = (result = @∅ collection fallback; (:continued, result))

function observed_nonempty(collection, evaluations)
    value = :caller_value
    isempty = error
    result = @⦱ (evaluations[] += 1; collection)
    return result, value
end

function observed_empty(collection, evaluations)
    value = :caller_value
    isempty = error
    result = @∅ (evaluations[] += 1; collection)
    return result, value
end

function nonempty_length(collection)
    result = @⦱ collection 0
    return length(result)
end
end

@testset "Empty collection checks" begin
    sites = EmptyCheckSites
    for (empty_collection, nonempty_collection) in (
        (Int[], [1, 2]), ("", "text"), ((), (1,)),
        (Set{Int}(), Set([1])), (Dict{Int,Int}(), Dict(1 => 2)),
    )
        @test sites.nonempty(empty_collection) === empty_collection
        @test sites.nonempty(nonempty_collection) === (:continued, nonempty_collection)
        @test sites.empty(empty_collection) === (:continued, empty_collection)
        @test sites.empty(nonempty_collection) === nonempty_collection
        @test sites.nonempty_fallback(empty_collection, nothing) === nothing
        @test sites.nonempty_fallback(nonempty_collection, nothing) === (:continued, nonempty_collection)
        @test sites.empty_fallback(nonempty_collection, missing) === missing
        @test sites.empty_fallback(empty_collection, missing) === (:continued, empty_collection)
    end
    for (callable, accepts_empty) in ((sites.observed_nonempty, false), (sites.observed_empty, true))
        for empty in (false, true)
            calls = Ref(0)
            evaluations = Ref(0)
            collection = sites.ObservedCollection(empty, calls)
            expected = empty == accepts_empty ? (collection, :caller_value) : collection
            @test callable(collection, evaluations) === expected
            @test calls[] == 1
            @test evaluations[] == 1
        end
    end
    for collection in (Int[], [1, 2])
        @test (@inferred sites.nonempty_length(collection)) == length(collection)
        @test (@allocated sites.nonempty_length(collection)) == 0
    end
    @test_throws MethodError sites.nonempty(nothing)
    @test_throws MethodError sites.empty(nothing)
end