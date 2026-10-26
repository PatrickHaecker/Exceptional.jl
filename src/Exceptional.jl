module Exceptional

export @⏎, @⎋, @⏎⏎, @⏎⎋, @⎋⏎, @⎋⎋
export @∃, @∄, @⊤, @⊥, @■, @□, @✓, @✗, @⦱, @∅
export @∃⏎, @∄⏎, @⊤⏎, @⊥⏎, @■⏎, @□⏎, @✓⏎, @✗⏎, @⦱⏎, @∅⏎
export @∃⎋, @∄⎋, @⊤⎋, @⊥⎋, @■⎋, @□⎋, @✓⎋, @✗⎋, @⦱⎋, @∅⎋
export @⏎∃, @⏎∄, @⏎⊤, @⏎⊥, @⏎■, @⏎□, @⏎✓, @⏎✗, @⏎⦱, @⏎∅
export @⎋∃, @⎋∄, @⎋⊤, @⎋⊥, @⎋■, @⎋□, @⎋✓, @⎋✗, @⎋⦱, @⎋∅
export @⏎∃⏎, @⏎∄⏎, @⏎⊤⏎, @⏎⊥⏎, @⏎■⏎, @⏎□⏎, @⏎✓⏎, @⏎✗⏎, @⏎⦱⏎, @⏎∅⏎
export @⏎∃⎋, @⏎∄⎋, @⏎⊤⎋, @⏎⊥⎋, @⏎■⎋, @⏎□⎋, @⏎✓⎋, @⏎✗⎋, @⏎⦱⎋, @⏎∅⎋
export @⎋∃⏎, @⎋∄⏎, @⎋⊤⏎, @⎋⊥⏎, @⎋■⏎, @⎋□⏎, @⎋✓⏎, @⎋✗⏎, @⎋⦱⏎, @⎋∅⏎
export @⎋∃⎋, @⎋∄⎋, @⎋⊤⎋, @⎋⊥⎋, @⎋■⎋, @⎋□⎋, @⎋✓⎋, @⎋✗⎋, @⎋⦱⎋, @⎋∅⎋

export @once

include("exceptional.jl")
include("once.jl")

const affixes = ("", "⏎", "⎋")

for check in (
	Check(:∃, :(!isnothing(value)), nothing),
	Check(:∄, :(isnothing(value)), nothing),
	Check(:⊤, :value, nothing),
	Check(:⊥, :(value ? false : true), nothing),
	Check(:■, :(!ismissing(value)), missing),
	Check(:□, :(ismissing(value)), missing),
	Check(:✓, :(!(value isa Exception)), ReuseValue()),
	Check(:✗, :(value isa Exception), ReuseValue()),
	Check(:⦱, :(!isempty(value)), ReuseValue()),
	Check(:∅, :(isempty(value)), ReuseValue()),
)
	for prefix in affixes, suffix in affixes
		define_macros(check, prefix, suffix)
	end
end

for regular in (Symbol, Expr), default in (QuoteNode, ReuseValue, Nothing, Symbol, Expr, String, Bool, Int)
	precompile(control_flow, (regular, default, Check, ControlFlowAction, ControlFlowAction, Module))
end

for expression in (Expr, Symbol, String, Int)
	precompile(once_slot, (Module, expression))
end
precompile(getindex, (OnceSlot,))

for expression in (Symbol, Expr)
	precompile(Core.kwcall, (NamedTuple{(:diagnostic,), Tuple{Bool}}, typeof(expand_with_storage), expression, Module))
end

precompile.(prepare_diagnostic, ((String,), (DomainError,)))
precompile(throw_stored, (Base.RefValue{Any},))
precompile(throw_stored_diagnostic, (Base.RefValue{Any},))
precompile.(throw_diagnostic, ((Any,), (String,), (SubString{String},)))

for value in (Bool, Nothing, Missing)
	precompile(throw_default, (String, String, value))
end

end
