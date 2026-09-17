using Exceptional
using Test

module ReturnedExceptionSites
using Exceptional

struct Payload
    number::Float64
    text::String
end
mutable struct MutableError <: Exception
    count::Int
end
const sink = Ref{Any}()

function stored_exception()
    @✓ @once ArgumentError("stored failure")
    return :unexpected
end

function stored_success()
    @✗ @once Payload(1.25, "stored success")
    return :unexpected
end

function escape_batch(callable)
    for iteration in 1:16
        sink[] = callable()
    end
    return nothing
end

const parse_error = ArgumentError("Expected an integer")
const positive_error = DomainError(-1, "Expected a positive integer")
const even_error = ArgumentError("Expected an even integer")

function parse_integer(text, visits)
    visits[1] += 1
    value = tryparse(Int, text)
    return isnothing(value) ? parse_error : value
end

function require_positive(value, visits)
    visits[2] += 1
    return value > 0 ? value : positive_error
end

function halve_even(value, visits)
    visits[3] += 1
    return iseven(value) ? div(value, 2) : even_error
end

function pipeline(text, visits)
    parsed = @✓ parse_integer(text, visits)
    positive = @✓ require_positive(parsed, visits)
    halved = @✓ halve_even(positive, visits)
    return halved + 1
end

function manual_pipeline(text, visits)
    parsed = parse_integer(text, visits)
    parsed isa Exception && return parsed
    positive = require_positive(parsed, visits)
    positive isa Exception && return positive
    halved = halve_even(positive, visits)
    halved isa Exception && return halved
    return halved + 1
end

function pipeline_batch(callable, inputs, visits, checksum, failure_count, last_error)
    total = 0
    failures = 0
    for text in inputs
        result = callable(text, visits)
        if result isa Exception
            failures += 1
            last_error[] = result
        else
            total += result
        end
    end
    checksum[] = total
    failure_count[] = failures
    return nothing
end
end

@testset "Returned exception checks" begin
    propagate(input) = (result = @✓ input; (:continued, result))
    handle(input) = (result = @✗ input; (:continued, result))
    exception = ArgumentError("returned failure")
    @test propagate(exception) === exception
    @test handle(exception) === (:continued, exception)
    mutable_exception = ReturnedExceptionSites.MutableError(1)
    @test propagate(mutable_exception) === mutable_exception
    @test handle(mutable_exception) === (:continued, mutable_exception)
    for input in (42, nothing, missing, "value", Ref(1), Exception)
        @test propagate(input) === (:continued, input)
        @test handle(input) === input
    end
    fallback(input, value) = (@✓ input value; :continued)
    @test fallback(exception, nothing) === nothing
    @test fallback(42, nothing) === :continued
    calls = Ref(0)
    function hygienic(input)
        value = :caller_value
        Exception = Nothing
        result = @✓ (calls[] += 1; input)
        return result, value, Exception
    end
    @test hygienic(exception) === exception
    @test calls[] == 1
    @test hygienic(42) === (42, :caller_value, Nothing)
    @test calls[] == 2
    throws() = (@✓ throw(ArgumentError("thrown failure")); :unexpected)
    @test_throws ArgumentError("thrown failure") throws()
    reverse_calls = Ref(0)
    function reverse_hygienic(input)
        value = :caller_value
        Exception = Nothing
        result = @✗ (reverse_calls[] += 1; input)
        return result, value, Exception
    end
    @test reverse_hygienic(42) === 42
    @test reverse_calls[] == 1
    @test reverse_hygienic(exception) === (exception, :caller_value, Nothing)
    @test reverse_calls[] == 2
    for callable in (ReturnedExceptionSites.stored_exception, ReturnedExceptionSites.stored_success)
        expected = callable()
        ReturnedExceptionSites.escape_batch(callable)
        @test ReturnedExceptionSites.sink[] === expected
        @test (@allocated ReturnedExceptionSites.escape_batch(callable)) == 0
    end
    @test ReturnedExceptionSites.stored_exception() isa ArgumentError
    @test ReturnedExceptionSites.stored_success() === ReturnedExceptionSites.Payload(1.25, "stored success")
end

@testset "Returned exception pipeline" begin
    sites = ReturnedExceptionSites
    visits = zeros(Int, 3)
    result_type = Union{Int,ArgumentError,DomainError}
    @test only(Base.return_types(sites.parse_integer, Tuple{String,Vector{Int}})) == Union{Int,ArgumentError}
    @test only(Base.return_types(sites.require_positive, Tuple{Int,Vector{Int}})) == Union{Int,DomainError}
    @test only(Base.return_types(sites.halve_even, Tuple{Int,Vector{Int}})) == Union{Int,ArgumentError}
    @test only(Base.return_types(sites.pipeline, Tuple{String,Vector{Int}})) == result_type
    @test only(Base.return_types(sites.manual_pipeline, Tuple{String,Vector{Int}})) == result_type
    for (text, expected, expected_visits) in (
        ("42", 22, [1, 1, 1]),
        ("invalid", sites.parse_error, [1, 0, 0]),
        ("-8", sites.positive_error, [1, 1, 0]),
        ("7", sites.even_error, [1, 1, 1]),
    )
        fill!(visits, 0)
        @test (@inferred Union{Int,ArgumentError,DomainError} sites.pipeline(text, visits)) === expected
        @test visits == expected_visits
    end
    checksum = Ref(0)
    failure_count = Ref(0)
    last_error = Ref{Any}(nothing)
    for (inputs, expected_sum, expected_failures, expected_error, expected_visits) in (
        (["2", "4", "42", "100"], 78, 0, nothing, [4, 4, 4]),
        (["bad", "invalid", "?", ""], 0, 4, sites.parse_error, [4, 0, 0]),
        (["-2", "0", "-8", "-100"], 0, 4, sites.positive_error, [4, 4, 0]),
        (["1", "3", "7", "99"], 0, 4, sites.even_error, [4, 4, 4]),
        (["2", "bad", "-8", "7", "42", "100"], 75, 3, sites.even_error, [6, 5, 4]),
    )
        allocations = map((sites.pipeline, sites.manual_pipeline)) do callable
            @test (@inferred sites.pipeline_batch(callable, inputs, visits, checksum, failure_count, last_error)) === nothing
            fill!(visits, 0)
            last_error[] = nothing
            bytes = @allocated sites.pipeline_batch(callable, inputs, visits, checksum, failure_count, last_error)
            @test checksum[] == expected_sum
            @test failure_count[] == expected_failures
            @test last_error[] === expected_error
            @test visits == expected_visits
            return bytes
        end
        @test allocations[1] <= allocations[2]
        if expected_failures == 0
            @test allocations == (0, 0)
        end
    end
end