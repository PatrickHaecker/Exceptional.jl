using Exceptional
using Test

module OnceSites
using Exceptional
import Exceptional: @once as @cached

module Unrelated
macro once(expression)
    return esc(expression)
end
end

struct DeferredMessage <: AbstractString
    value::Base.RefValue{Int}
    conversions::Base.RefValue{Int}
end
function Base.String(message::DeferredMessage)
    message.conversions[] += 1
    return "value $(message.value[])"
end
Base.convert(::Type{String}, message::DeferredMessage) = String(message)
Base.print(io::IO, message::DeferredMessage) = print(io, String(message))
const deferred_message = DeferredMessage(Ref(1), Ref(0))
const message_constructions = Ref(0)

function make_message()
    message_constructions[] += 1
    return "computed message"
end

computed(input) = (@⎋ input > 0 @cached make_message(); input)
deferred(input) = (@⎋ input > 0 @once deferred_message; input)
unrelated(input) = (@⎋ input > 0 Unrelated.@once make_message(); input)
string_returned(input) = (@⏎ input > 0 @once "returned string"; input)
string_standalone() = @once "standalone string"
string_prefix() = @⎋∃ @once "prefix string"
partial(input) = (@⎋ input > 0 string((@once "input: "), input); input)

const constructions = Ref(0)
struct FixedError <: Exception
    message::String
end
mutable struct MutableError <: Exception
    count::Int
end
const mutable_error = MutableError(0)

struct Payload
    number::Float64
    text::String
end
const payload_sink = Ref{Any}()
standalone_payload() = @once Payload(1.25, "payload")
returned_payload() = @Exceptional.⊤ false @once Payload(1.25, "payload")

macro shared_error()
    return esc(:(@once FixedError("composed")))
end

macro shared_message()
    return esc(:(@once "composed message"))
end
composed_message(input) = (@⎋ input > 0 @shared_message; input)

function checked(input)
    @⎋ input > 0 @once begin
        constructions[] += 1
        FixedError("positive required")
    end
    return input
end

returned(input) = (@⊤ input > 0 @once FixedError("positive required"); input)
runtime_checked(input, diagnostic) = (@⎋ input > 0 diagnostic; input)
mutable_checked(input) = (@⎋ input > 0 @once mutable_error; input)
string_checked(input) = (@⎋ input > 0 @once "raw string"; input)
tuple_checked(input) = (@⎋ input > 0 @once (123456789, "payload"); input)
prefix_checked() = @⎋∃ @once FixedError("prefix")
prefix_qualified() = @⎋∃ Exceptional.@once FixedError("qualified prefix")
prefix_alias() = @⎋∃ @cached FixedError("aliased prefix")
prefix_composed() = @⎋∃ @shared_error
prefix_composed_message() = @⎋∃ @shared_message
standalone() = @once Int[]
other() = @once Int[]
qualified(input) = (@⎋ input > 0 Exceptional.@once FixedError("qualified"); input)
composed(input) = (@⎋ input > 0 @shared_error; input)
nothing_checked(input) = (@⎋ input > 0 @once nothing; input)
function hygienic(input)
    getindex = throw_stored = error
    @⎋ input > 0 @once FixedError("hygienic")
    return input
end
end

function once_caught(callable, args...)
    try
        callable(args...)
    catch exception
        return exception
    end
    error("Expected a thrown object")
end

function once_batch(callable, expected, args...)
    for iteration in 1:16
        once_caught(callable, args...) === expected || return false
    end
    return true
end

function once_escape_batch(callable)
    for iteration in 1:16
        OnceSites.payload_sink[] = callable()
    end
    return nothing
end

@testset "Once storage" begin
    slot = Exceptional.OnceSlot(OnceSites.mutable_error)
    @test slot[] === OnceSites.mutable_error
    @test_throws MethodError setindex!(slot, nothing)
    expanded, holder = Exceptional.expand_with_storage(:(@once mutable_error), OnceSites)
    @test Core.eval(OnceSites, expanded) === OnceSites.mutable_error
    @test Core.eval(OnceSites, holder)[] === OnceSites.mutable_error
    @test isnothing(last(Exceptional.expand_with_storage(:(local_ref[]), OnceSites)))
    @test isnothing(last(Exceptional.expand_with_storage(:($(GlobalRef(OnceSites, :constructions))[]), OnceSites)))
    @test isnothing(last(Exceptional.expand_with_storage(:($(GlobalRef(OnceSites, :unavailable_binding))[]), OnceSites)))
    @test OnceSites.constructions[] == 1
    @test OnceSites.checked(1) == 1
    @test OnceSites.checked(1.0) == 1.0
    for diagnostic in (42, (123456789, "payload"), nothing, Ref(42), OnceSites.mutable_error)
        @test OnceSites.runtime_checked(1, diagnostic) == 1
        @test once_caught(OnceSites.runtime_checked, -1, diagnostic) === diagnostic
    end
    @test once_caught(OnceSites.runtime_checked, -1, "raw string") isa ArgumentError
    @test once_caught(OnceSites.runtime_checked, -1, "raw string").msg == "raw string"
    for callable in (OnceSites.checked, OnceSites.mutable_checked,
                     OnceSites.string_checked, OnceSites.tuple_checked, OnceSites.qualified,
                     OnceSites.composed, OnceSites.nothing_checked, OnceSites.hygienic,
                     OnceSites.computed, OnceSites.composed_message)
        expected = once_caught(callable, -1)
        @test once_batch(callable, expected, -1)
        @test (@allocated once_batch(callable, expected, -1)) == 0
    end
    @test once_caught(OnceSites.checked, -1) isa OnceSites.FixedError
    @test once_caught(OnceSites.checked, -1.0) === once_caught(OnceSites.checked, -1)
    @test once_caught(OnceSites.nothing_checked, -1) === nothing
    @test once_caught(OnceSites.composed, -1).message == "composed"
    @test once_caught(OnceSites.mutable_checked, -1) === OnceSites.mutable_error
    OnceSites.mutable_error.count = 3
    @test once_caught(OnceSites.mutable_checked, -1).count == 3
    @test once_caught(OnceSites.string_checked, -1) isa ArgumentError
    @test once_caught(OnceSites.string_checked, -1).msg == "raw string"
    @test once_caught(OnceSites.composed_message, -1).msg == "composed message"
    @test OnceSites.message_constructions[] == 1
    @test once_caught(OnceSites.computed, -1).msg == "computed message"
    @test OnceSites.unrelated(1) == 1
    @test OnceSites.message_constructions[] == 1
    @test once_caught(OnceSites.unrelated, -1).msg == "computed message"
    @test once_caught(OnceSites.unrelated, -2).msg == "computed message"
    @test OnceSites.message_constructions[] == 3
    @test OnceSites.deferred_message.conversions[] == 0
    @test OnceSites.deferred(1) == 1
    @test OnceSites.deferred_message.conversions[] == 0
    @test sprint(showerror, once_caught(OnceSites.deferred, -1)) == "ArgumentError: value 1"
    OnceSites.deferred_message.value[] = 2
    @test sprint(showerror, once_caught(OnceSites.deferred, -1)) == "ArgumentError: value 2"
    @test OnceSites.deferred_message.conversions[] == 2
    @test OnceSites.string_returned(-1) === "returned string"
    @test OnceSites.string_standalone() === "standalone string"
    @test once_caught(OnceSites.string_prefix) === "prefix string"
    @test once_caught(OnceSites.prefix_composed).message == "composed"
    @test once_caught(OnceSites.prefix_composed_message) === "composed message"
    @test once_caught(OnceSites.partial, -1).msg == "input: -1"
    @test once_caught(OnceSites.partial, -2).msg == "input: -2"
    @test once_caught(OnceSites.tuple_checked, -1) === (123456789, "payload")
    for callable in (OnceSites.prefix_checked, OnceSites.prefix_qualified,
                     OnceSites.prefix_alias, OnceSites.prefix_composed, OnceSites.prefix_composed_message)
        expected = once_caught(callable)
        @test once_batch(callable, expected)
        @test (@allocated once_batch(callable, expected)) == 0
    end
    @test OnceSites.returned(-1) isa OnceSites.FixedError
    @test OnceSites.returned(1) == 1
    @test (@allocated OnceSites.returned(-1)) == 0
    for callable in (OnceSites.standalone_payload, OnceSites.returned_payload)
        once_escape_batch(callable)
        @test OnceSites.payload_sink[] === OnceSites.Payload(1.25, "payload")
        @test (@allocated once_escape_batch(callable)) == 0
    end
    @test OnceSites.standalone() === OnceSites.standalone()
    @test OnceSites.standalone() !== OnceSites.other()
    @test OnceSites.constructions[] == 1
    tasks = [Threads.@spawn once_caught(OnceSites.checked, -1) for attempt in 1:8]
    @test all(exception -> exception === once_caught(OnceSites.checked, -1), fetch.(tasks))
    @test_throws UndefVarError macroexpand(OnceSites, :(@once unavailable_function_local))
    @test_throws MethodError macroexpand(OnceSites, :(@⎋ false @once("message", "extra")))
    @test Base.isexported(Exceptional, Symbol("@once"))
    @test Docs.hasdoc(Exceptional, Symbol("@once")) skip=(VERSION < v"1.11")
end