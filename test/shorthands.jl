using Exceptional
using Test

function shorthand_outcome(callable, args...)
    try
        return :returned, Base.invokelatest(callable, args...)
    catch exception
        return :thrown, exception
    end
end

@testset "Boolean shorthands" begin
    positive_or_nothing(input) = (@⏎ input > 0; input)
    require_positive(input) = (@⎋ input > 0 "input must be positive"; input)
    @test positive_or_nothing(2) === 2
    @test positive_or_nothing(-2) === nothing
    @test require_positive(2) === 2
    @test_throws ArgumentError("input must be positive") require_positive(-2)
    @test_throws TypeError (@⎋ 1)
    @test_throws TypeError (@⏎ 1)

    for (short, explicit) in (("⏎", "⊤⏎"), ("⎋", "⊤⎋"),
                               ("⏎⏎", "⏎⊤⏎"), ("⏎⎋", "⏎⊤⎋"),
                               ("⎋⏎", "⎋⊤⏎"), ("⎋⎋", "⎋⊤⎋"))
        name = Symbol("@", short)
        @test Base.isexported(Exceptional, name)
        @test Docs.hasdoc(Exceptional, name) skip=(VERSION < v"1.11")
        for source in ("$name input", "$name(input)")
            @test Meta.parse(source).args[1] === name
        end
        for diagnostic in ((), (:exceptional,), ("literal diagnostic",))
            functions = map((name, Symbol("@", explicit))) do macro_name
                invocation = Expr(:macrocall, macro_name, LineNumberNode(@__LINE__), :input, diagnostic...)
                @eval (input, exceptional) -> begin
                    value = $invocation
                    return (:continued, value)
                end
            end
            for input in (true, false, 1, nothing), exceptional in (nothing, "message", ArgumentError("existing"))
                actual = shorthand_outcome(functions[1], input, exceptional)
                expected = shorthand_outcome(functions[2], input, exceptional)
                @test actual[1] === expected[1]
                if expected[1] === :thrown && expected[2] isa Exception
                    @test typeof(actual[2]) === typeof(expected[2])
                    @test sprint(showerror, actual[2]) == sprint(showerror, expected[2])
                else
                    @test actual[2] === expected[2]
                end
            end
        end

        invocation = Expr(:macrocall, name, LineNumberNode(@__LINE__), :(tested()), :(diagnostic()))
        run = @eval (tested, diagnostic) -> begin
            throw = throw_default = throw_diagnostic = throw_stored = error
            value = $invocation
            return value
        end
        for input in (true, false)
            events = Symbol[]
            tested = () -> (push!(events, :tested); input)
            diagnostic = () -> (push!(events, :diagnostic); ArgumentError("failure"))
            shorthand_outcome(run, tested, diagnostic)
            @test events == (input ? [:tested] : [:tested, :diagnostic])
        end
    end
end