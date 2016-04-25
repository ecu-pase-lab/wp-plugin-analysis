module lang::php::experiments::plugins::Includes

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::util::Utils;
import lang::php::util::Corpus;
import lang::php::experiments::plugins::Guard;
import lang::php::experiments::plugins::Summary;

import Node;
import Traversal;
import List;
import Set;
import IO;
import Map;
import Relation;

alias IRel = rel[Expr expr, loc at, Guard pathGuard];

public IRel includeGuards(System sys) {
	IRel res = { };
	bottom-up visit(sys) {
		case i:include(_,_) : {
			guardList = buildGuardPath(getTraversalContext());
			if (isEmpty(guardList)) {
				res = res + < i, i@at, notGuarded() >;
			} else {
				res = res + < i, i@at, guardedBy(guardList) >;
			}
		}
	}
	
	return res;
}

alias QRRel = rel[loc file, loc source, loc target];

alias GuardedQRRel = rel[loc file, loc source, loc target, Guard guard];

public GuardedQRRel buildGuardedIncludesRel(QRRel qr, IRel ir) {
	map[loc,set[Guard]] irmap = Relation::index(ir<1,2>);
	return { < f, s, t, v > | < f, s, t > <- qr, s in irmap, v <- irmap[s] }; 
}
