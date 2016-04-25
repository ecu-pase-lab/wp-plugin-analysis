module lang::php::experiments::plugins::Abstractions

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::experiments::plugins::Guard;
import lang::php::experiments::plugins::Utils;

import Node;
import Traversal;
import Set;
import List;

@doc{A relation from function names to the location of the function declaration}
alias FRel = rel[str fname, loc at, Guard pathGuard];

@doc{A relation from class names to the location of the class declaration}
alias CRel = rel[str cname, loc at, Guard pathGuard];

@doc{A relation from class x method names to the location of the method declaration}
alias MRel = rel[str cname, str mname, loc at, bool isPublic, Guard pathGuard];

@doc{The location of the constants defined in the plugin}
alias ConstRel = rel[str constName, loc at, Expr constExpr, Guard pathGuard];

@doc{The location of the class constants defined in the plugin}
alias ClassConstRel = rel[str cname, str constName, loc at, Expr constExpr, Guard pathGuard];

@doc{Extract the information on declared functions for the given system}
public FRel definedFunctions(System s) {
	FRel res = { };
	visit(s.files) {
		case f:function(fname,_,_,_) : {
			guardList = buildGuardPath(getTraversalContext());
			if (isEmpty(guardList)) {
				res = res + < fname, f@at, notGuarded() >;
			} else {
				res = res + < fname, f@at, guardedBy(guardList) >;
			}
		}
	}
    return res;
}

@doc{Extract the information on declared classes for the given system}
public CRel definedClasses(System s) {
	CRel res = { };
	visit(s.files) {
		case c:class(cname,_,_,_,members) : {
			guardList = buildGuardPath(getTraversalContext());
			if (isEmpty(guardList)) {
				res = res + < cname, c@at, notGuarded() >;
			} else {
				res = res + < cname, c@at, guardedBy(guardList) >;
			}
		}
	}
    return res;
}

@doc{Extract the information on declared methods for the given system}
public MRel definedMethods(System s) {
	MRel res = { };
	visit(s.files) {
		case c:class(cname,_,_,_,members) : {
			guardList = buildGuardPath(getTraversalContext());
			if (isEmpty(guardList)) {
				res = res + { < cname, mname, m@at, (\public() in mods || !(\private() in mods || \protected() in mods)), notGuarded() > | m:method(mname,mods,_,_,_) <- members };
			} else {
				res = res + { < cname, mname, m@at, (\public() in mods || !(\private() in mods || \protected() in mods)), guardedBy(guardList) > | m:method(mname,mods,_,_,_) <- members };
			}
		}
	}
    return res;
}

@doc{Extract the information on declared constants for the given system}
public ConstRel definedConstants(System s) {
	ConstRel res = { };
	visit(s.files) {
		case c:call(name(name("define")),[actualParameter(scalar(string(cn)),false),actualParameter(e,false)]) : {
			guardList = buildGuardPath(getTraversalContext());
			if (isEmpty(guardList)) {
				res = res + < cn, c@at, e, notGuarded() >;
			} else {
				res = res + < cn, c@at, e, guardedBy(guardList) >;
			}
		}
	}
	return res;
}

@doc{Extract the information on declared class constants for the given system}
public ClassConstRel definedClassConstants(System s) {
	ClassConstRel res = { };
	visit(s.files) {
		case class(cn,_,_,_,cis) : {
			guardList = buildGuardPath(getTraversalContext());
			if (isEmpty(guardList)) {
				res = res + { < cn, name, cc@at, ce, notGuarded() > | constCI(consts) <- cis, cc:const(name,ce) <- consts };
			} else {
				res = res + { < cn, name, cc@at, ce, guardedBy(guardList) > | constCI(consts) <- cis, cc:const(name,ce) <- consts };
			}
		} 
	}
	return res;
}
