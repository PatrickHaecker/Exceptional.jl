module Exceptional

export @∃, @∄, @⊤, @⊥, @✓, @⍰
export @∃⏎, @∄⏎, @⊤⏎, @⊥⏎, @✓⏎, @⍰⏎
export @∃⎋, @∄⎋, @⊤⎋, @⊥⎋, @✓⎋, @⍰⎋
export @⏎∃, @⏎∄, @⏎⊤, @⏎⊥, @⏎✓, @⏎⍰
export @⎋∃, @⎋∄, @⎋⊤, @⎋⊥, @⎋✓, @⎋⍰
export @⏎∃⏎, @⏎∄⏎, @⏎⊤⏎, @⏎⊥⏎, @⏎✓⏎, @⏎⍰⏎
export @⏎∃⎋, @⏎∄⎋, @⏎⊤⎋, @⏎⊥⎋, @⏎✓⎋, @⏎⍰⎋
export @⎋∃⏎, @⎋∄⏎, @⎋⊤⏎, @⎋⊥⏎, @⎋✓⏎, @⎋⍰⏎
export @⎋∃⎋, @⎋∄⎋, @⎋⊤⎋, @⎋⊥⎋, @⎋✓⎋, @⎋⍰⎋

include("exceptional.jl")

const affixes = ("", "⏎", "⎋")

for check in (
	Check(:∃, :(!isnothing(value)), nothing),
	Check(:∄, :(isnothing(value)), nothing),
	Check(:⊤, :value, nothing),
	Check(:⊥, :(value ? false : true), nothing),
	Check(:✓, :(!ismissing(value)), missing),
	Check(:⍰, :(ismissing(value)), missing),
)
	for prefix in affixes, suffix in affixes
		success = flowaction(prefix)
		failure = flowaction(suffix, isempty(prefix) ? ReturnValue : ContinueValue)
		name = Symbol(prefix, check.symbol, suffix)
		default = failure === ThrowValue ? nothing : QuoteNode(check.sentinel)
		@eval begin
			@doc $(documentation(name, check, success, failure))
			macro $name(regular, exceptional=$(QuoteNode(default)))
				return control_flow(regular, exceptional, $check, $success, $failure)
			end
		end
	end
end

end
