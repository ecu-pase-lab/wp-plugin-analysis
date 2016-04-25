module lang::php::experiments::plugins::Options

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::experiments::plugins::Guard;
import lang::php::experiments::plugins::Utils;

import Node;
import Traversal;
import Set;
import List;

//@doc{Option names or expressions with the locations where they are introduced}
//alias OptionRel = rel[NameOrExpr optName, loc at];
//
//@doc{Extract the information on declared admin options for WordPress plugins for the given system}
//OptionRel definedOptions(System sys) {
//	OptionRel res = { };
//	visit(sys) {
//		case c:call(name(name("add_option")),[actualParameter(e,_),_*]) : {
//			res = res + < wrapExpr(e), c@at >;
//		}
//
//		case c:call(name(name("update_option")),[actualParameter(e,_),_*]) : {
//			res = res + < wrapExpr(e), c@at >;
//		}
//	}
//	return res;
//}

@doc{Option names or expressions with the locations where they are introduced and an indication of whether they are guarded}
alias OptionRel = rel[NameOrExpr optName, loc at, Guard apiGuard, Guard pathGuard];

@doc{Extract the information on declared admin options for WordPress plugins for the given system}
public OptionRel definedOptions(System sys) {
	OptionRel res = { };
	visit(sys) {
		case c:call(name(name("add_option")),[actualParameter(e,_),_*]) : {
			guards = [ gn | gn <- getTraversalContextNodes() ];
			guardList = buildGuardPath(getTraversalContext());
			pathGuard = isEmpty(guardList) ? notGuarded() : guardedBy(guardList);
			
			if (size(guards) > 1) {
				// If we are capturing or negating the return value, assume we are guarding
				// this since we are least keeping track of whether it succeeded
				if (unaryOperation(c,booleanNot()) := guards[1]) {
					res = res + < wrapExpr(e), c@at, guarded(), pathGuard >;
				} else if (assign(_,c) := guards[1]) {
					res = res + < wrapExpr(e), c@at, guarded(), pathGuard >;
				} else {
					// We may have a more complicated check, but it's safer to assume
					// it isn't guarded since that allows a conflict to be detected
					res = res + < wrapExpr(e), c@at, notGuarded(), pathGuard >;
				}
			}
			// If there are no guards, it could definitely conflict
			res = res + < wrapExpr(e), c@at, notGuarded(), pathGuard >;
		}

		case c:call(name(name("update_option")),[actualParameter(e,_),_*]) : {
			// update_option will ALWAYS do the update (unless the option itself is not updateable)
			guardList = buildGuardPath(getTraversalContext());
			pathGuard = isEmpty(guardList) ? notGuarded() : guardedBy(guardList);
			res = res + < wrapExpr(e), c@at, notGuarded(), pathGuard >;
		}
	}
	return res;
}
