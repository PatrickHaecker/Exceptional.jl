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
throw_diagnostic(exception::Exception) = throw(exception)

throw_default(requirement, source, value) =
	throw(ArgumentError(string("Check ", requirement, " failed", " for `", source, "`, got ", repr(value))))

function diagnostic(regular, exceptional, check::Check)
	isnothing(exceptional) && return :(throw_default($(check.requirement), $(string(regular)), value))
	return :(throw_diagnostic($(esc(exceptional))))
end

function failure(regular, exceptional, check::Check, action::ControlFlowAction)
	action === ReturnValue && return :(return $(esc(exceptional)))
	action === ThrowValue && return diagnostic(regular, exceptional, check)
	return esc(exceptional)
end

function control_flow(regular, exceptional, check::Check, on_success::ControlFlowAction, on_failure::ControlFlowAction)
	success = if on_success === ReturnValue
		:(return value)
	elseif on_success === ThrowValue
		:(throw(value))
	else
		:value
	end
	failure_branch = failure(regular, exceptional, check, on_failure)
	return quote
		local value = $(esc(regular))
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

function documentation(name, check::Check, on_success::ControlFlowAction, on_failure::ControlFlowAction)
	(; requirement, sentinel) = check
	throwing = on_failure === ThrowValue
	fallback = on_failure === ContinueValue
	action_description = action(on_success, on_failure, requirement)
	details = if throwing
		"A string diagnostic becomes an `ArgumentError`; an `Exception` is thrown unchanged.\nWithout a diagnostic, report the tested source expression and result in an `ArgumentError`."
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
	return "    $signature\n\n$action_description\n\n$details\nThe tested expression is evaluated once. $evaluation\nContinuing with a value means evaluating to it without exiting the enclosing function.\nA prefix acts when the check holds; a suffix acts when it fails. An omitted suffix continues with a fallback when a prefix is present, otherwise it returns the exceptional value."
end