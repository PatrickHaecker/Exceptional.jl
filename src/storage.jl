struct DiagnosticSlot
	# `Any` preserves the exception's existing box for allocation-free throwing.
	holder::Base.RefValue{Any}
	DiagnosticSlot(message::String) = new(Ref{Any}(ArgumentError(message)))
end

Base.@noinline throw_stored(holder::Base.RefValue{Any}) = throw(holder[])

function diagnostic_slot(caller::Module, message::String)
	name = gensym(:exceptional_diagnostic)
	slot = DiagnosticSlot(message)
	Core.eval(caller, Expr(:const, Expr(:(=), name, QuoteNode(slot))))
	return GlobalRef(caller, name)
end