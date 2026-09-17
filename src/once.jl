struct OnceSlot
	# `Any` preserves the value's existing box for allocation-free reuse.
	holder::Base.RefValue{Any}
	OnceSlot(value) = new(Ref{Any}(value))
end

throw_stored(holder::Base.RefValue{Any}) = throw(holder[])
Base.getindex(slot::OnceSlot) = slot.holder[]

function once_slot(caller::Module, expression)
	value = Core.eval(caller, expression)
	name = gensym(:once_slot)
	slot = OnceSlot(value)
	Core.eval(caller, Expr(:const, Expr(:(=), name, QuoteNode(slot))))
	return GlobalRef(caller, name)
end

"""
    @once expression

Evaluate `expression` once in the caller's module during macro expansion and reuse its result.

Each macro expansion owns separate storage, shared across calls and method
specializations. The expression can use existing module globals, but not function
locals. Initialization happens even if the runtime branch is never taken.
Precompilation preserves the stored object instead of rerunning initialization
on package load. Redefinition or a separate `macroexpand` creates new storage.

Evaluate to the stored object without conversion. Reusing an object does not
freeze computations deferred by that object. Operations on the result can still
allocate.

Mutable objects are shared without copying, resetting, or synchronization.
Callers must coordinate mutation and concurrent use, including mutable fields of
immutable objects. Expansion requires permission to define globals and is not
supported inside generated-function generators.
"""
macro once(expression)
	slot = once_slot(__module__, expression)
	return :($slot[])
end