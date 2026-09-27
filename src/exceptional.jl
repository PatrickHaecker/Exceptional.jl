@enum ControlFlowAction ContinueValue ReturnValue ThrowValue

function flowaction(affix, default=ContinueValue)
	affix == "⏎" && return ReturnValue
	affix == "⎋" && return ThrowValue
	return default
end

# Mark a default that reuses the already evaluated value during macro expansion.
struct ReuseValue end

struct Check
	symbol::Symbol
	condition::Union{Symbol, Expr}
	default::Union{Nothing, Missing, ReuseValue}
	requirement::String
end

function Check(symbol::Symbol, condition::Union{Symbol,Expr}, default::Union{Nothing, Missing, ReuseValue})
	requirement = symbol === :⊤ ? "the tested value is `true`" : symbol === :⊥ ? "the tested value is `false`" : "`$(string(condition))` is true"
	return Check(symbol, condition, default, requirement)
end

throw_diagnostic(message::AbstractString) = throw(ArgumentError(message))
throw_diagnostic(Base.@nospecialize(value)) = throw(value)

prepare_diagnostic(value) = value
prepare_diagnostic(message::String) = ArgumentError(message)

throw_stored_diagnostic(holder::Base.RefValue{Any}) = throw_diagnostic(holder[])

function expand_with_storage(expression, caller::Module; diagnostic=false)
	if Meta.isexpr(expression, :escape, 1)
		expanded, holder = expand_with_storage(expression.args[1], caller; diagnostic)
		return esc(expanded), isnothing(holder) ? nothing : esc(holder)
	elseif Meta.isexpr(expression, :macrocall)
		if length(expression.args) == 3 && Core.eval(caller, expression.args[1]) === var"@once"
			initializer = diagnostic ? Expr(:call, GlobalRef(@__MODULE__, :prepare_diagnostic), expression.args[3]) : expression.args[3]
			slot = once_slot(caller, initializer)
			return :($slot[]), :($slot.holder)
		end
		return expand_with_storage(macroexpand(caller, expression; recursive=false), caller; diagnostic)
	end
	return macroexpand(caller, expression), nothing
end

throw_default(requirement, source, value) =
	throw(ArgumentError(string("Check ", requirement, " failed", " for `", source, "`, got ", repr(value))))

function diagnostic(regular, default, check::Check, caller::Module)
	isnothing(default) && return :(throw_default($(check.requirement), $(string(regular)), value))
	if default isa String
		slot = once_slot(caller, QuoteNode(ArgumentError(default)))
		return :(throw_stored_diagnostic($(esc(:($slot.holder)))))
	end
	expanded, holder = expand_with_storage(default, caller; diagnostic=true)
	isnothing(holder) || return :(throw_stored_diagnostic($(esc(holder))))
	return :(throw_diagnostic($(esc(expanded))))
end

function failure(regular, default, check::Check, action::ControlFlowAction, caller::Module)
	action === ThrowValue && return diagnostic(regular, default, check, caller)
	expression = default isa ReuseValue ? :value : esc(default)
	return action === ReturnValue ? :(return $expression) : expression
end

function control_flow(regular, default, check::Check, on_success::ControlFlowAction, on_failure::ControlFlowAction, caller::Module)
	expanded, holder = expand_with_storage(regular, caller)
	success = if on_success === ReturnValue
		:(return value)
	elseif on_success === ThrowValue
		isnothing(holder) ? :(throw(value)) : :(throw_stored($(esc(holder))))
	else
		:value
	end
	failure_branch = failure(regular, default, check, on_failure, caller)
	return quote
		local value = $(esc(expanded))
        # `condition` uses `value` from the local scope.
		$(check.condition) ? $success : $failure_branch
	end
end

function action(on_success::ControlFlowAction, on_failure::ControlFlowAction, requirement)
	success = on_success === ReturnValue ? "Return the tested value from the enclosing function" :
		on_success === ThrowValue ? "Throw the tested value" : "Continue with the tested value"
	failure = on_failure === ReturnValue ? "return the default from the function" :
		on_failure === ThrowValue ? "throw the default (or a generated `ArgumentError` when it is `nothing`)" : "continue with the default"
	return "$success when $requirement, otherwise $failure."
end

function define_macros(check::Check, prefix, suffix)
	success = flowaction(prefix)
	failure = flowaction(suffix, isempty(prefix) ? ReturnValue : ContinueValue)
	name = Symbol(prefix, check.symbol, suffix)
	argument_default = failure === ThrowValue ? nothing : check.default isa ReuseValue ? check.default : QuoteNode(check.default)
	names = check.symbol !== :⊤ || isempty(suffix) ? (name,) : (name, Symbol(prefix, suffix))
	for spelling in names
		@eval begin
			@doc $(documentation(spelling, check, success, failure))
			macro $spelling(regular, default=$(QuoteNode(argument_default)))
				return control_flow(regular, default, $check, $success, $failure, __module__)
			end
		end
	end
	return nothing
end

function documentation(name, check::Check, on_success::ControlFlowAction, on_failure::ControlFlowAction)
	(; requirement, default) = check
	default_description = default isa ReuseValue ? "the tested value" : "`$default`"
	throwing = on_failure === ThrowValue
	continuing = on_failure === ContinueValue
	action_description = action(on_success, on_failure, requirement)
	details = if throwing
		"An `AbstractString` default becomes an `ArgumentError`; every other non-`nothing` default is thrown unchanged. Literal string defaults reuse a hidden, preinitialized exception per macro expansion.\nWith a `nothing` default, an `ArgumentError` describes the failed check, tested source expression, and result."
	elseif continuing
		"On failure, continue with the default, which defaults to $default_description. It is never thrown implicitly."
	else
		"On failure, return the default from the function, which defaults to $default_description."
	end
	if on_success === ThrowValue
		details = "The tested value is passed directly to `throw`, including strings and non-exception objects.\n" * details
	end
	signature = "@$name regular [default]"
	evaluation = "The optional default is evaluated only when the check fails."
	return "    $signature\n\n$action_description\n\n$details\nThe tested expression is evaluated once. $evaluation\nAn explicit `@once` initializer instead runs in the caller's module during macro expansion. Throw suffixes cache an `ArgumentError` for a stored `String`, wrap other `AbstractString` defaults on failure, and throw other stored objects unchanged. Returns and throw prefixes preserve the stored value.\nContinuing with a value means evaluating to it without exiting the enclosing function.\nA prefix acts when the check holds; a suffix acts when it fails. With no suffix, a prefix continues with the default; without a prefix, the default is returned."
end