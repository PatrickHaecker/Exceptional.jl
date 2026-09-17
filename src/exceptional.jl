@enum ControlFlowAction ContinueValue ReturnValue ThrowValue

function flowaction(affix, default=ContinueValue)
	affix == "⏎" && return ReturnValue
	affix == "⎋" && return ThrowValue
	return default
end

struct Check
	symbol::Symbol
	condition::Union{Symbol,Expr}
	sentinel::Union{Nothing,Missing}
	requirement::String
end

function Check(symbol::Symbol, condition::Union{Symbol,Expr}, sentinel::Union{Nothing,Missing})
	requirement = symbol === :⊤ ? "the tested value is `true`" : symbol === :⊥ ? "the tested value is `false`" : "`$(string(condition))` is true"
	return Check(symbol, condition, sentinel, requirement)
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

function diagnostic(regular, exceptional, check::Check, caller::Module)
	isnothing(exceptional) && return :(throw_default($(check.requirement), $(string(regular)), value))
	if exceptional isa String
		slot = once_slot(caller, QuoteNode(ArgumentError(exceptional)))
		return :(throw_stored_diagnostic($(esc(:($slot.holder)))))
	end
	expanded, holder = expand_with_storage(exceptional, caller; diagnostic=true)
	isnothing(holder) || return :(throw_stored_diagnostic($(esc(holder))))
	return :(throw_diagnostic($(esc(expanded))))
end

function failure(regular, exceptional, check::Check, action::ControlFlowAction, caller::Module)
	action === ReturnValue && return :(return $(esc(exceptional)))
	action === ThrowValue && return diagnostic(regular, exceptional, check, caller)
	return esc(exceptional)
end

function control_flow(regular, exceptional, check::Check, on_success::ControlFlowAction, on_failure::ControlFlowAction, caller::Module)
	expanded, holder = expand_with_storage(regular, caller)
	success = if on_success === ReturnValue
		:(return value)
	elseif on_success === ThrowValue
		isnothing(holder) ? :(throw(value)) : :(throw_stored($(esc(holder))))
	else
		:value
	end
	failure_branch = failure(regular, exceptional, check, on_failure, caller)
	return quote
		local value = $(esc(expanded))
        # `condition` uses `value` from the local scope.
		$(check.condition) ? $success : $failure_branch
	end
end

function action(on_success::ControlFlowAction, on_failure::ControlFlowAction, requirement)
	success = on_success === ReturnValue ? "Return the tested value from the enclosing function" :
		on_success === ThrowValue ? "Throw the tested value" : "Continue with the tested value"
	failure = on_failure === ReturnValue ? "return `exceptional` from the enclosing function" :
		on_failure === ThrowValue ? "throw an exception" : "continue with `fallback`"
	return "$success when $requirement, otherwise $failure."
end

function define_macros(check::Check, prefix, suffix)
	success = flowaction(prefix)
	failure = flowaction(suffix, isempty(prefix) ? ReturnValue : ContinueValue)
	name = Symbol(prefix, check.symbol, suffix)
	default = failure === ThrowValue ? nothing : QuoteNode(check.sentinel)
	names = check.symbol !== :⊤ || isempty(suffix) ? (name,) : (name, Symbol(prefix, suffix))
	for spelling in names
		@eval begin
			@doc $(documentation(spelling, check, success, failure))
			macro $spelling(regular, exceptional=$(QuoteNode(default)))
				return control_flow(regular, exceptional, $check, $success, $failure, __module__)
			end
		end
	end
	return nothing
end

function documentation(name, check::Check, on_success::ControlFlowAction, on_failure::ControlFlowAction)
	(; requirement, sentinel) = check
	throwing = on_failure === ThrowValue
	fallback = on_failure === ContinueValue
	action_description = action(on_success, on_failure, requirement)
	details = if throwing
		"A string diagnostic becomes an `ArgumentError`; any other value is thrown unchanged. Literal string diagnostics reuse a hidden, preinitialized exception per macro expansion.\nWithout a diagnostic, report the tested source expression and result in an `ArgumentError`."
	elseif fallback
		"The fallback defaults to `$sentinel` and is never implicitly thrown."
	else
		"The exceptional value defaults to `$sentinel` and is never implicitly thrown."
	end
	if on_success === ThrowValue
		details = "The tested value is passed directly to `throw`, including strings and non-exception objects.\n" * details
	end
	signature = "@$name regular " * (throwing ? "[diagnostic]" : fallback ? "fallback=$sentinel" : "exceptional=$sentinel")
	evaluation = throwing ? "The diagnostic expression is evaluated only when the check fails." : fallback ? "The fallback expression is evaluated only when the check fails." : "The exceptional expression is evaluated only when the check fails."
	return "    $signature\n\n$action_description\n\n$details\nThe tested expression is evaluated once. $evaluation\nAn explicit `@once` initializer instead runs in the caller's module during macro expansion. Throw suffixes cache an `ArgumentError` for a stored `String`, wrap other `AbstractString` values on failure, and throw other stored objects unchanged. Returns and throw prefixes preserve the stored value.\nContinuing with a value means evaluating to it without exiting the enclosing function.\nA prefix acts when the check holds; a suffix acts when it fails. An omitted suffix continues with a fallback when a prefix is present, otherwise it returns the exceptional value."
end