# Exceptional.jl

Structured control flow functionality to conditionally leave the method.

The macro names consist of
- a prefix (optional)
- a check (`⊤` can be omitted when a suffix is present)
- a suffix (optional)

| Prefix | When the check holds |
| --- | --- |
| (none) | Continue with the tested value |
| `⏎` | Return the tested value from the enclosing function |
| `⎋` | Throw the tested value |

| Check | Meaning | Default exceptional value or fallback |
| --- | --- | --- |
| `∃` | `!isnothing(value)` | `nothing` |
| `∄` | `isnothing(value)` | `nothing` |
| `⊤` | The value is `true` | `nothing` |
| `⊥` | The value is `false` | `nothing` |
| `✓` | `!ismissing(value)` | `missing` |
| `⍰` | `ismissing(value)` | `missing` |

| Suffix | When the check fails |
| --- | --- |
| `⏎` / (none, without a prefix) | Return the exceptional value from the enclosing function |
| `⎋` | Throw the diagnostic, converting a message to an `ArgumentError` |
| (none, with a prefix) | Continue with the fallback |

All nine forms support each check. So in the following, you can replace `∃` by any other check.

| Form | Check holds | Check fails |
| --- | --- | --- |
| `@∃ value exceptional` | Continue with `value` | Return `exceptional` |
| `@∃⏎ value exceptional` | Continue with `value` | Return `exceptional` |
| `@∃⎋ value diagnostic` | Continue with `value` | Throw diagnostic |
| `@⏎∃ value fallback` | Return `value` | Continue with `fallback` |
| `@⎋∃ value fallback` | Throw `value` | Continue with `fallback` |
| `@⏎∃⏎ value exceptional` | Return `value` | Return `exceptional` |
| `@⏎∃⎋ value diagnostic` | Return `value` | Throw diagnostic |
| `@⎋∃⏎ value exceptional` | Throw `value` | Return `exceptional` |
| `@⎋∃⎋ value diagnostic` | Throw `value` | Throw diagnostic |

Continuing means evaluating to a value without exiting the enclosing function.
The tested expression is evaluated once, preserving short-circuit behavior.
The second argument is evaluated only when the check fails.

Tested values are preserved, including custom objects recognized by `isnothing`
or `ismissing`. Boolean checks require a `Bool` and raise `TypeError` otherwise.

```julia
using Exceptional

function required_result(key)
    result = @∃ lookup(key)
    return process(result)
end

function checked_result(key)
    result = @∃⎋ lookup(key) "not found"
    return process(result)
end

function invalid_bounds(ll, lr, rl, rr)
    @⏎⊤ ll > lr || rl > rr
    return false
end
```

Return actions do not implicitly throw exception objects or strings.

Throw prefixes pass the tested value directly to `throw` when the check holds,
including strings, Booleans, and other non-exception objects. Without a suffix, they
evaluate to the fallback, which defaults to the sentinel in the table above.
The fallback is evaluated only when the check fails and is never implicitly thrown.
For example, `@⎋∃ validation_error` throws a present error object and continues
with `nothing` when it is absent.

Throw suffixes evaluate diagnostics only on the throwing branch. A message
becomes an `ArgumentError`, while an `Exception` value is thrown unchanged.
With no diagnostic, the error reports the failed check, tested source expression,
and evaluated result.

For example, `@⏎∃⎋ lookup(key) "not found"` returns a present result and throws an
`ArgumentError` otherwise. `@⎋∃⏎ validation_error false` throws a present error object
and returns `false` otherwise.

## Boolean Shorthands

Omitting `⊤` gives these equivalent spellings:

| Shorthand | Explicit form | On `true` | On `false` |
| --- | --- | --- | --- |
| `@⏎` | `@⊤⏎` | Continue with `true` | Return exceptional value |
| `@⎋` | `@⊤⎋` | Continue with `true` | Throw diagnostic |
| `@⏎⏎` | `@⏎⊤⏎` | Return `true` | Return exceptional value |
| `@⏎⎋` | `@⏎⊤⎋` | Return `true` | Throw diagnostic |
| `@⎋⏎` | `@⎋⊤⏎` | Throw `true` | Return exceptional value |
| `@⎋⎋` | `@⎋⊤⎋` | Throw `true` | Throw diagnostic |

A single affix is always a suffix and acts on `false`. With two affixes, the
first acts on `true` and the second on `false`. Prefix-only forms still require
the check: `@⏎⊤` returns on `true`, whereas `@⏎` returns on `false`. Likewise,
`@⎋⊤` throws on `true`, whereas `@⎋` throws on `false`. There is no bare `@`
shorthand for `@⊤`.

The condition must be a `Bool` and is evaluated once. The optional second
argument is evaluated only on `false`. Return suffixes default to `nothing`.
Throw suffixes default to a diagnostic describing the failed check.

```julia
using Exceptional

function positive_or_nothing(input)
    @⏎ input > 0
    return input
end

function require_positive(input)
    @⎋ input > 0 "input must be positive"
    return input
end
```

Literal string diagnostics use the same automatic exception storage as the
explicit forms.

## Allocation-free Exceptions

Use a literal string diagnostic to throw an `ArgumentError` without allocating a
new exception or message on each failure. Exceptional prepares the exception
once at compile-time and reuses it at run-time:

```julia
using Exceptional

function checked_input(input)
    @⎋ input > 0 "input must be positive"
    return input
end

try
    checked_input(-1)
catch e
    showerror(devnull, e)
end
```

### Throwing Versus Returning

Returning an exception avoids stack unwinding and backtrace recording. For an
expected failure, use `@⊤` to return the exception when the check fails:

```julia
using Exceptional

const input_error = Ref{Any}(ArgumentError("input must be positive"))

function checked_input_return(input)
    @⊤ input > 0 input_error[]
    return input
end

result = checked_input_return(-5)
@assert result === input_error[]
@assert checked_input_return(5) == 5
```

The `Ref{Any}` holds a preallocated exception for reuse without allocating on
each return. Returning an exception does not throw it: callers must inspect and
handle the returned value.

Example timings on Julia 1.13.0:

| Failure path | Median time per call | Warmed allocated bytes per call |
| --- | ---: | ---: |
| Throw and catch the cached `ArgumentError` | 4.6 **μ**s | 0 |
| Return the preboxed `ArgumentError` | 2.8 **n**s | 0 |

Avoiding allocations does not remove the cost of throwing.

Throwing can still allocate during compilation, when Julia grows its exception
stack or collects backtraces, or when a handler formats or prints the error.
Automatic exception reuse applies only to literal string diagnostics.
Interpolated strings, runtime messages, supplied exception objects, and default
diagnostics can still allocate on failure.