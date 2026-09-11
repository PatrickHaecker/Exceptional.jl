# Exceptional.jl

Structured control flow functionality to conditionally leave the method.

The macro names consist of
- a prefix (optional)
- a check
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