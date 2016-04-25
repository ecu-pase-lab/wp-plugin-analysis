module lang::php::experiments::plugins::Guard

import lang::php::ast::AbstractSyntax;

import IO;
import Set;
import List;

@doc{Is the definition definitely guarded, definitely not guarded, or maybe guarded}
data Guard = guarded() | guardedBy(list[Expr] exprs) | potentiallyGuarded(list[Expr] exprs) | notGuarded();

public list[Expr] extractGuardPath(value v, value child, list[value] parents, list[Expr] guards) {
	switch(v) {
		case Stmt i:\if(Expr cond, list[Stmt] body, list[ElseIf] elseIfs, OptionElse elseClause) : {
			// If the current node is a conditional, see what the child is. If the child
			// is the body, that means this was along the true path, so we add cond as
			// a guard. If the child is not the body, then this was below the elseif or
			// else nodes. This means the condition is false, we we add the negation as
			// the guard.
			if (child := body) {
				return cond + guards;
			} else {
				return unaryOperation(cond,booleanNot())[@at=cond@at] + guards;
			}
		}
		
		case ElseIf ei:elseIf(Expr cond, list[Stmt] body) : {
			// If the current node is an elseif, this means we were in the body, so
			// the condition must have been true. Add the condition to the guard.
			return cond + guards;
		}
		
		case Stmt d:do(Expr cond, list[Stmt] body) : {
			// If the current node is a do loop, that doesn't really tell us anything,
			// since the body is always executed first. This means the guard could be
			// either true or false when we reach the include. So, this is essentially
			// unguarded, and we treat it as such.
			return guards;
		}
		
		case Stmt fe:foreach(Expr arrayExpr, OptionExpr keyvar, bool byRef, Expr asVar, list[Stmt] body) : {
			// This is a loop, but the only condition to reach this is that the
			// array not be empty, which doesn't seem helpful in guarding the file
			// inclusion. So, don't use this to alter the guard.
			return guards;
		}
		
		case Stmt f:function(str fname, bool byRef, list[Param] params, list[Stmt] body) : {
			// If this is inside a function, it means that function must be called
			// to perform the include. We should record that fact. The parameters
			// don't matter, given that functions/methods cannot be overloaded in
			// PHP (so any call to this name is handled by this function).
			return call(name(name(fname)),[])[@at=f@at] + guards;
		}
		
		case Case c:\case(OptionExpr cond, list[Stmt] body) : {
			if (someExpr(condExpr) := cond) {
				// Find first switch in the parents
				switchParents = [ p | p <- parents, \switch(Expr _, list[Case] _) := p ];
				if (size(switchParents) > 0 && \switch(Expr swCond, list[Case] cases) := switchParents[0]) {
					// TODO: Add in fall-through information
					return binaryOperation(swCond, condExpr, equal())[@at=c@at] + guards;
				} else {
					println("Cannot find parent, so cannot use case: <c@at>");
				}
			} else {
				return fetchConst(name("true"))[@at=c@at] + guards;
			}
		}
		
		case Stmt w:\while(Expr cond, list[Stmt] body) : {
			// The condition must be true for the include to be performed.
			// This would be a very unusual scenario, though...
			return cond + guards;
		}
		
		case ClassItem m:method(str mname, set[Modifier] modifiers, bool byRef, list[Param] params, list[Stmt] body) : {
			return methodCall(var(name(name("any"))), name(name(mname)), [])[@at=m@at] + guards;
		}
		
		case Expr t:ternary(Expr cond, OptionExpr ifBranch, Expr elseBranch) : {
			if (someExpr(child) := ifBranch) {
				return cond + guards;
			} else {
				return unaryOperation(cond,booleanNot())[@at=t@at] + guards;
			}
		}
	}
	
	return guards;
}

public list[Expr] buildGuardPath(list[value] context) {
	child = context[0];
	context = context[1..];
	list[Expr] guardsSoFar = [ ];
	while (!isEmpty(context)) {
		guardsSoFar = extractGuardPath(context[0], child, context[1..], guardsSoFar);
		child = context[0];
		context = context[1..];
	}
	return guardsSoFar;
}

public map[str,int] guardingCallCounts(set[Guard] guards) {
	map[str,int] res = ( );
	for (g <- guards, guardedBy(lexp) := g, unaryOperation(call(name(name(cn)),_),booleanNot()) := lexp[0] || call(name(name(cn)),_) := lexp[0]) {
		if (cn in res) {
			res[cn] = res[cn] + 1;
		} else {
			res[cn] = 1;
		}
	}
	return res;
}