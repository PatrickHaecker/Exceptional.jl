module Exceptional

export @⏎, @⎋, @⏎⏎, @⏎⎋, @⎋⏎, @⎋⎋
export @∃, @∄, @⊤, @⊥, @✓, @⍰
export @∃⏎, @∄⏎, @⊤⏎, @⊥⏎, @✓⏎, @⍰⏎
export @∃⎋, @∄⎋, @⊤⎋, @⊥⎋, @✓⎋, @⍰⎋
export @⏎∃, @⏎∄, @⏎⊤, @⏎⊥, @⏎✓, @⏎⍰
export @⎋∃, @⎋∄, @⎋⊤, @⎋⊥, @⎋✓, @⎋⍰
export @⏎∃⏎, @⏎∄⏎, @⏎⊤⏎, @⏎⊥⏎, @⏎✓⏎, @⏎⍰⏎
export @⏎∃⎋, @⏎∄⎋, @⏎⊤⎋, @⏎⊥⎋, @⏎✓⎋, @⏎⍰⎋
export @⎋∃⏎, @⎋∄⏎, @⎋⊤⏎, @⎋⊥⏎, @⎋✓⏎, @⎋⍰⏎
export @⎋∃⎋, @⎋∄⎋, @⎋⊤⎋, @⎋⊥⎋, @⎋✓⎋, @⎋⍰⎋

export @once

include("exceptional.jl")
include("once.jl")

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
		define_macros(check, prefix, suffix)
	end
end

end
