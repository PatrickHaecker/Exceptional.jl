# Exceptional.jl

Structured control flow functionality to conditionally leave the method.

The macro names consist of
- a prefix (optional)
- a check (`⊤` can be omitted when a suffix is present)
- a suffix (optional)

| Prefix | When the check holds | LaTeX completion |
| --- | --- | --- |
| (none) | Continue with `value` | (not applicable) |
| `⏎` | Return `value` from the function | `\varcarriagereturn` |
| `⎋` | Throw `value` | `\escape` |

| Check | Meaning | Default on failure | LaTeX completion |
| --- | --- | --- | --- |
| `∃` | `!isnothing(value)` | `nothing` | `\exists` |
| `∄` | `isnothing(value)` | `nothing` | `\nexists` |
| `⊤` | The value is `true` | `nothing` | `\top` |
| `⊥` | The value is `false` | `nothing` | `\bot` |
| `■` | `!ismissing(value)` | `missing` | `\blacksquare` |
| `□` | `ismissing(value)` | `missing` | `\square` |
| `✓` | `!(value isa Exception)` | `value` | `\checkmark` |
| `✗` | `value isa Exception` | `value` | `\xmark` |
| `⦱` | `!isempty(value)` | `value` | `\emptysetobar` |
| `∅` | `isempty(value)` | `value` | `\emptyset` |

The optional second argument, `default`, is evaluated only when the check fails.

| Suffix | When the check fails |
| --- | --- |
| `⏎` / (none, without a prefix) | Return `default` from the function |
| `⎋` | Throw `default`; generate `ArgumentError` if omitted |
| (none, with a prefix) | Continue with `default` |

All nine forms support each check. So in the following, you can replace `∃` by any other check.

| Form | Check holds | Check fails |
| --- | --- | --- |
| `@∃ value default` | Continue with `value` | Return `default` |
| `@∃⏎ value default` | Continue with `value` | Return `default` |
| `@∃⎋ value default` | Continue with `value` | Throw `default` |
| `@⏎∃ value default` | Return `value` | Continue with `default` |
| `@⎋∃ value default` | Throw `value` | Continue with `default` |
| `@⏎∃⏎ value default` | Return `value` | Return `default` |
| `@⏎∃⎋ value default` | Return `value` | Throw `default` |
| `@⎋∃⏎ value default` | Throw `value` | Return `default` |
| `@⎋∃⎋ value default` | Throw `value` | Throw `default` |

Type a listed LaTeX sequence followed by Tab in Julia's REPL to insert the symbol.
The LaTeX completions for `⎋` and `✗` need at least Julia 1.14.

Continuing means evaluating to a value without exiting the enclosing function.
The tested expression is evaluated once, preserving short-circuit behavior.
An explicit `@once` initializer instead runs during macro expansion (see below).

Tested values are preserved, including custom objects recognized by `isnothing`,
`ismissing`, or `isempty`. Boolean checks require a `Bool` and raise `TypeError` otherwise.

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
continue with the default listed in the table when the check fails. The default is
never implicitly thrown by the prefix.
For example, `@⎋∃ validation_error` throws a present error object and continues
with `nothing` when it is absent.

Throw suffixes use the default only on the throwing branch. An `AbstractString`
default becomes an `ArgumentError`; every other non-`nothing` value is thrown
unchanged. With a `nothing` default, the generated error reports the failed check,
tested source expression, and evaluated result.

For example, `@⏎∃⎋ lookup(key) "not found"` returns a present result and throws an
`ArgumentError` otherwise. `@⎋∃⏎ validation_error false` throws a present error object
and returns `false` otherwise.

## Empty Collections

Use `@⦱` to continue with a nonempty value or return the original empty value
from the enclosing function:

```julia
function process_items(items)
    values = @⦱ items
    return map(process, values)
end
```

Use `@∅` for the complementary workflow: continue with an empty value or return
the original nonempty value. An explicit second argument replaces the default,
for example `@⦱ items nothing` returns `nothing` when `items` is empty.

These checks call `isempty` once and preserve the already evaluated value without
copying or constructing an empty replacement. They support strings, tuples,
collections, and custom types implementing `isempty`. They do not treat `nothing`
or `missing` as empty sentinels. Any errors or iteration side effects from the
type's `isempty` implementation are preserved.

All nine affix combinations are available. A throw suffix can be given a message,
for example `@⦱⎋ items "items must not be empty"`.

## Returned Exceptions

Use `@✓` to continue with a non-exception result or return the original exception
from the enclosing function:

```julia
function process_input(input)
    value = @✓ compute(input)
    return transform(value)
end
```

Use `@✗` for the complementary workflow: continue with an exception to handle it,
or return the successful result unchanged:

```julia
function recover_input(input)
    exception = @✗ compute(input)
    return recover(exception)
end
```

Both checks evaluate the tested expression once. Without a second argument, their
default is that already evaluated value. An explicit second argument replaces the
default, for example `@✓ compute(input) nothing` returns `nothing` on failure.
These checks inspect returned objects with `isa Exception`; they do not catch
thrown exceptions. `nothing` and `missing` are non-exception results.

All nine affix combinations are available. For example, `@⎋✗ result` throws the
tested value if it is an `Exception` and continues with it unchanged otherwise.

## Boolean Shorthands

Omitting `⊤` gives these equivalent spellings:

| Shorthand | Explicit form | On `true` | On `false` |
| --- | --- | --- | --- |
| `@⏎` | `@⊤⏎` | Continue with `true` | Return `default` |
| `@⎋` | `@⊤⎋` | Continue with `true` | Throw `default` |
| `@⏎⏎` | `@⏎⊤⏎` | Return `true` | Return `default` |
| `@⏎⎋` | `@⏎⊤⎋` | Return `true` | Throw `default` |
| `@⎋⏎` | `@⎋⊤⏎` | Throw `true` | Return `default` |
| `@⎋⎋` | `@⎋⊤⎋` | Throw `true` | Throw `default` |

A single affix is always a suffix and acts on `false`. With two affixes, the
first acts on `true` and the second on `false`. Prefix-only forms still require
the check: `@⏎⊤` returns on `true`, whereas `@⏎` returns on `false`. Likewise,
`@⎋⊤` throws on `true`, whereas `@⎋` throws on `false`. There is no bare `@`
shorthand for `@⊤`.

The condition must be a `Bool` and is evaluated once. The optional second
argument is evaluated only on `false`. Return suffixes default to `nothing`.
Without a second argument, throw suffixes generate an `ArgumentError` describing
the failed check.

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

Literal string defaults use the same automatic exception storage as the explicit
forms.

## Allocation-free Exceptions

Use a literal string as the second argument to throw an `ArgumentError` without
allocating a new exception or message on each failure. Exceptional prepares the
exception once at compile-time and reuses it at run-time:

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

Use `@once` for other exception types or arbitrary objects:

```julia
function checked_domain(input)
    @⎋ input > 0 @once DomainError(-1, "input must be positive")
    return input
end
```

`@once` evaluates its expression in the caller's module during macro expansion,
once per annotated call site, and reuses the object across calls and method
specializations. It can use existing module globals, not function locals.
`@once` preserves its result without conversion. A string default on a throw suffix,
as in `@⎋ condition @once "message"`, throws a cached `ArgumentError`. Only
concrete `String` messages get cached wrappers. Other `AbstractString` defaults are
wrapped on failure without forcing their text during macro expansion. Returns and
throw prefixes preserve the stored value.
Mutable objects are shared without copying or
synchronization, so callers must coordinate mutation and concurrent use.

### Throwing Versus Returning

Returning an exception avoids stack unwinding and backtrace recording. For an
expected failure, use `@⊤` to return the exception when the check fails:

```julia
using Exceptional

function checked_input_return(input)
    @⊤ input > 0 @once ArgumentError("input must be positive")
    return input
end

checked_input_return(-5) # ArgumentError("input must be positive")
checked_input_return(5)  # 5
```

`@once` reuses the exception without allocating on each return. Returning an
exception does not throw it: callers must inspect and handle the returned value.

Example timings on Julia 1.13.0:

| Failure path | Median time per call | Warmed allocated bytes per call |
| --- | ---: | ---: |
| Throw and catch the cached `ArgumentError` | 4.6 **μ**s | 0 |
| Return the preboxed `ArgumentError` | 2.8 **n**s | 0 |

Avoiding allocations does not remove the cost of throwing.

Throwing can still allocate during compilation, when Julia grows its exception
stack or collects backtraces, or when a handler formats or prints the error.
Exception reuse applies to literal string defaults and explicit `@once` expressions.
Other defaults can still allocate when thrown.