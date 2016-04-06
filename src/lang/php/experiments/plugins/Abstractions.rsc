module lang::php::experiments::plugins::Abstractions

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::experiments::plugins::Guard;
import lang::php::experiments::plugins::Utils;

@doc{A relation from function names to the location of the function declaration}
alias FRel = rel[str fname, loc at];

@doc{A relation from class names to the location of the class declaration}
alias CRel = rel[str cname, loc at];

@doc{A relation from class x method names to the location of the method declaration}
alias MRel = rel[str cname, str mname, loc at, bool isPublic];

@doc{The location of the constants defined in the plugin}
alias ConstRel = rel[str constName, loc at, Expr constExpr];

@doc{The location of the class constants defined in the plugin}
alias ClassConstRel = rel[str cname, str constName, loc at, Expr constExpr];

@doc{Extract the information on declared functions for the given system}
FRel definedFunctions(System s) {
    return { < fname, f@at > | /f:function(fname,_,_,_) := s };
}

@doc{Extract the information on declared classes for the given system}
CRel definedClasses(System s) {
    return { < cname, c@at > | /c:class(cname,_,_,_,members) := s };
}

@doc{Extract the information on declared methods for the given system}
MRel definedMethods(System s) {
    return { < cname, mname, m@at, (\public() in mods || !(\private() in mods || \protected() in mods)) > | /c:class(cname,_,_,_,members) := s, m:method(mname,mods,_,_,_) <- members };
}

@doc{Extract the information on declared constants for the given system}
ConstRel definedConstants(System s) {
	return { < cn, c@at, e > | /c:call(name(name("define")),[actualParameter(scalar(string(cn)),false),actualParameter(e,false)]) := s };
}

@doc{Extract the information on declared class constants for the given system}
ClassConstRel definedClassConstants(System s) {
	return { < cn, name, cc@at, ce > | /class(cn,_,_,_,cis) := s, constCI(consts) <- cis, cc:const(name,ce) <- consts };
}
