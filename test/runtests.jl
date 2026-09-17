using Exceptional
using Test

include("automatic_storage.jl")
include("shorthands.jl")
include("once.jl")

struct AbsentValue end
Base.isnothing(::AbsentValue) = true

struct UnknownValue end
Base.ismissing(::UnknownValue) = true

struct CustomException <: Exception
    value::Int
end

const families = (
    ("∃", 42, nothing, nothing),
    ("∄", nothing, 42, nothing),
    ("⊤", true, false, nothing),
    ("⊥", false, true, nothing),
    ("✓", 42, missing, missing),
    ("⍰", missing, 42, missing),
)

const spellings = (
    ("", "", :continue_value, :return_exceptional),
    ("", "⏎", :continue_value, :return_exceptional),
    ("", "⎋", :continue_value, :throw),
    ("⏎", "", :return_value, :continue_exceptional),
    ("⎋", "", :throw_value, :continue_exceptional),
    ("⏎", "⏎", :return_value, :return_exceptional),
    ("⏎", "⎋", :return_value, :throw),
    ("⎋", "⏎", :throw_value, :return_exceptional),
    ("⎋", "⎋", :throw_value, :throw),
)

function outcome(callable, args...)
    try
        return :returned, callable(args...)
    catch exception
        return :thrown, exception
    end
end

function expectedoutcome(action, input, exceptional)
    action === :throw && return :thrown, exceptional
    action === :throw_value && return :thrown, input
    action === :return_value && return :returned, input
    action === :return_exceptional && return :returned, exceptional
    return :returned, (:continued, action === :continue_value ? input : exceptional)
end

@testset "Original examples" begin
    @test !isnothing(@∃ 42)
    @test !isnothing(@⊤ true)
    @test !isnothing(@⊥ false)
    @test !ismissing(@✓ 42)
    @test ismissing(@⍰ missing)
end

@testset "Control-flow contract" begin
    for (stem, accepted, rejected, sentinel) in families
        for (prefix, suffix, matching, nonmatching) in spellings
            name = Symbol("@", prefix, stem, suffix)
            explicit = Expr(:macrocall, name, LineNumberNode(@__LINE__), :input, :exceptional)
            omitted = Expr(:macrocall, name, LineNumberNode(@__LINE__), :input)
            explicit_function = @eval (input, exceptional) -> begin
                result = $explicit
                return (:continued, result)
            end
            default_function = @eval input -> begin
                result = $omitted
                return (:continued, result)
            end
            for (input, action) in ((accepted, matching), (rejected, nonmatching))
                if action === :throw
                    for message in ("failure", SubString("failure!", 1, 7))
                        @test_throws ArgumentError("failure") explicit_function(input, message)
                    end
                    status, caught = outcome(default_function, input)
                    @test status === :thrown
                    @test caught isa ArgumentError
                    for fragment in ("failed", "input", repr(input))
                        @test occursin(fragment, caught.msg)
                    end
                    for exceptional in (DomainError(7, "failure"), CustomException(7))
                        @test outcome(explicit_function, input, exceptional) === (:thrown, exceptional)
                    end
                else
                    for exceptional in (nothing, missing, "failure", DomainError(7, "failure"), CustomException(7), [1, 2])
                        @test outcome(explicit_function, input, exceptional) === expectedoutcome(action, input, exceptional)
                    end
                    @test outcome(default_function, input) === expectedoutcome(action, input, sentinel)
                end
            end
        end
    end
end

@testset "Evaluation and unevaluated branches" begin
    for (stem, accepted, rejected, _) in families
        for (prefix, suffix, matching, nonmatching) in spellings
            name = Symbol("@", prefix, stem, suffix)
            invocation = Expr(:macrocall, name, LineNumberNode(@__LINE__),
                              :(tested()), :(diagnostic()))
            run = @eval (tested, diagnostic) -> begin
                value = :caller_value
                isnothing = ismissing = throw = throw_diagnostic = throw_default = error
                result = $invocation
                return (:continued, result)
            end
            exception = CustomException(2)
            @test outcome(run, () -> throw(exception), () -> error("unreachable")) === (:thrown, exception)
            for (input, action) in ((accepted, matching), (rejected, nonmatching))
                events = Symbol[]
                tested = () -> (push!(events, :tested); input)
                exception = CustomException(1)
                diagnostic = () -> (push!(events, :diagnostic); exception)
                @test outcome(run, tested, diagnostic) === expectedoutcome(action, input, exception)
                evaluates_diagnostic = action in (:throw, :return_exceptional, :continue_exceptional)
                @test events == (evaluates_diagnostic ? [:tested, :diagnostic] : [:tested])
            end
            unbound = Expr(:macrocall, name, LineNumberNode(@__LINE__), :input,
                           :undefined_exceptional_binding)
            accepted_function = @eval input -> begin
                result = $unbound
                return (:continued, result)
            end
            @test outcome(accepted_function, accepted) === expectedoutcome(matching, accepted, nothing)
        end
    end
end

@testset "Preserve predicate-matching objects" begin
    for (stem, input, matches) in (
        ("∄", AbsentValue(), true), ("∃", AbsentValue(), false),
        ("⍰", UnknownValue(), true), ("✓", UnknownValue(), false),
        ("∃", [1, 2], true), ("∄", [1, 2], false),
        ("✓", [1, 2], true), ("⍰", [1, 2], false),
    )
        for (prefix, suffix, matching, nonmatching) in spellings
            invocation = Expr(:macrocall, Symbol("@", prefix, stem, suffix),
                              LineNumberNode(@__LINE__), :input, :exceptional)
            run = @eval (input, exceptional) -> begin
                result = $invocation
                return (:continued, result)
            end
            exceptional = CustomException(1)
            action = matches ? matching : nonmatching
            @test outcome(run, input, exceptional) === expectedoutcome(action, input, exceptional)
        end
    end
    input = [1, 2]
    @test (@⎋∄ input) === nothing
    @test (@⎋⍰ input) === missing
    @test (@⎋∃ AbsentValue()) === nothing
    @test (@⎋✓ UnknownValue()) === missing
    @test (@⎋∄ input input) === input
end

@testset "Boolean conditions" begin
    for stem in ("⊤", "⊥"), (prefix, suffix, _, _) in spellings
        invocation = Expr(:macrocall, Symbol("@", prefix, stem, suffix),
                          LineNumberNode(@__LINE__), :input, :(error("unreachable")))
        run = @eval input -> $invocation
        for input in (0, 1, nothing, missing, "true")
            @test_throws TypeError run(input)
        end
    end
    for (stem, accepted) in (("⊤", true), ("⊥", false)), (prefix, suffix, matching, nonmatching) in spellings
        for operator in (:&&, :||)
            condition = Expr(operator, :(left()), :(right()))
            invocation = Expr(:macrocall, Symbol("@", prefix, stem, suffix),
                              LineNumberNode(@__LINE__), condition, :exceptional)
            run = @eval (left, right, exceptional) -> begin
                result = $invocation
                return (:continued, result)
            end
            for left_value in (false, true), right_value in (false, true)
                events = Symbol[]
                left = () -> (push!(events, :left); left_value)
                right = () -> (push!(events, :right); right_value)
                evaluates_right = operator === :&& ? left_value : !left_value
                input = evaluates_right ? right_value : left_value
                action = input === accepted ? matching : nonmatching
                exceptional = CustomException(1)
                @test outcome(run, left, right, exceptional) === expectedoutcome(action, input, exceptional)
                @test events == (evaluates_right ? [:left, :right] : [:left])
            end
        end
    end
end

@testset "Hygiene and nesting" begin
    function shadowed(input)
        value = :caller_value
        temp = :caller_temp
        isnothing = ismissing = throw_diagnostic = throw_default = error
        result = @∃⎋ (@✓⎋ input)
        return result, value, temp
    end
    @test shadowed(42) === (42, :caller_value, :caller_temp)
    @test_throws ArgumentError shadowed(nothing)
    @test_throws ArgumentError shadowed(missing)

    function nested(input)
        result = @∃ (@✓ input :inner) :outer
        return (:continued, result)
    end
    @test nested(42) === (:continued, 42)
    @test nested(nothing) === :outer
    @test nested(missing) === :inner

    function nested_return(input)
        result = @∃ (@⏎✓ input nothing) :outer
        return (:continued, result)
    end
    @test nested_return(42) === 42
    @test nested_return(missing) === :outer

    function assigns_in_caller()
        assigned = nothing
        @∃⎋ (assigned = 42)
        return assigned
    end
    @test assigns_in_caller() === 42

    function nested_throw(input)
        value = :caller_value
        isnothing = ismissing = throw_default = throw = error
        result = @⎋∄ (@⎋⍰ input input) input
        return result, value
    end
    @test nested_throw(42) === (42, :caller_value)
    @test outcome(nested_throw, nothing) === (:thrown, nothing)
    @test outcome(nested_throw, missing) === (:thrown, missing)

    for (stem, accepted, rejected, _) in families, (prefix, suffix, matching, _) in spellings
        invocation = Expr(:macrocall, Symbol("@", prefix, stem, suffix),
                          LineNumberNode(@__LINE__), :input, :(return :from_exceptional))
        run = @eval input -> begin
            result = $invocation
            return (:continued, result)
        end
        @test outcome(run, accepted) === expectedoutcome(matching, accepted, nothing)
        @test run(rejected) === :from_exceptional
    end
end

@testset "Diagnostics" begin
    captured = try
        @⊤⎋ 2 < 1
    catch exception
        exception
    end
    @test captured isa ArgumentError
    @test occursin("2 < 1", captured.msg)
    @test occursin("false", captured.msg)
    @test occursin("true", captured.msg)

    @test_throws ArgumentError("custom message") (@∃⎋ nothing "custom message")
    @test_throws DomainError(7, "invalid") (@∃⎋ nothing DomainError(7, "invalid"))
    calls = Ref(0)
    diagnostic() = (calls[] += 1; "computed")
    @test (@∃⎋ 42 "message: $(diagnostic())") === 42
    @test calls[] == 0
    @test_throws ArgumentError("message: computed") (@∃⎋ nothing "message: $(diagnostic())")
    @test calls[] == 1
    @test (@⎋∄ 42 "message: $(diagnostic())") == "message: computed"
    @test calls[] == 2
    @test outcome(() -> (@⎋∃ 42 "message: $(diagnostic())")) === (:thrown, 42)
    @test calls[] == 2
    for value in ("literal message", DomainError(7, "invalid"), CustomException(7), [1, 2])
        @test outcome(() -> (@⎋∃ value error("unused fallback"))) === (:thrown, value)
        @test outcome(() -> (@⎋✓ value)) === (:thrown, value)
        @test (@⎋∃ nothing value) === value
        @test (@⎋✓ missing value) === value
    end
end

@testset "Conditional return example" begin
    function invalid_bounds(ll, lr, rl, rr, events)
        lteq(left, right) = (push!(events, (left, right)); left <= right)
        result = @⏎⊤ !lteq(ll, lr) || !lteq(rl, rr)
        return (:continued, result)
    end
    for (bounds, expected, comparisons) in (
        ((2, 1, 3, 4), true, [(2, 1)]),
        ((1, 2, 4, 3), true, [(1, 2), (4, 3)]),
        ((1, 2, 3, 4), (:continued, nothing), [(1, 2), (3, 4)]),
    )
        events = Tuple{Int,Int}[]
        @test invalid_bounds(bounds..., events) === expected
        @test events == comparisons
    end
end

@testset "Macro spelling and documentation" begin
    for (check, _, _, _) in families, (prefix, suffix, _, _) in spellings
        name = Symbol("@", prefix, check, suffix)
        @test Base.isexported(Exceptional, name)
        for source in ("$name input", "$name(input)")
            parsed = Meta.parse(source)
            @test parsed.head === :macrocall
            @test parsed.args[1] === name
        end
        @test Docs.hasdoc(Exceptional, name) skip=(VERSION < v"1.11")
    end
end