module lang::php::experiments::plugins::Shortcodes

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::experiments::plugins::Guard;
import lang::php::experiments::plugins::Utils;

import Node;
import Traversal;
import Set;
import List;

@doc{Shortcode names and definition locations}
alias ShortcodeRel = rel[NameOrExpr scname, loc at];

@doc{Extract the information on declared WordPress shortcodes for the given system}
ShortcodeRel definedShortcodes(System s) {
	return { < wrapExpr(e), c@at > | /c:call(name(name("add_shortcode")),[actualParameter(e,_),actualParameter(cb,_)]) := s };
}

@doc{Shortcode names and definition locations with guard information}
alias ShortcodeWithGuardRel = rel[NameOrExpr scname, loc at, Guard guard];

@doc{Extract the information on declared WordPress shortcodes for the given system, including guards.}
public ShortcodeWithGuardRel definedShortcodesWithGuards(System sys) {
	ShortcodeWithGuardRel res = { };
	for (l <- sys.files, scr := sys.files[l]) {
		visit(scr) {
			case c:call(name(name("add_shortcode")),[actualParameter(e,_),actualParameter(cb,_)]) : { 
				guards = [ g | g:call(name(name("shortcode_exists")),[actualParameter(sn,_)]) <- getTraversalContextNodes() ];
				if (!isEmpty(guards)) {
					matchingGuards = [ g | g <- guards, g == e ];
					if (!isEmpty(matchingGuards)) {
						res = res + < wrapExpr(e), c@at, Guarded() >;
					} else {
						res = res + < wrapExpr(e), c@at, PotentiallyGuarded(guards) >;
					}
				} else {
					res = res + < wrapExpr(e), c@at, NotGuarded() >;
				}
			}
		}
	}
	
	return res;
}