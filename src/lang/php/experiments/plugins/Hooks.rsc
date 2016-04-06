module lang::php::experiments::plugins::Hooks

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::experiments::plugins::Guard;
import lang::php::experiments::plugins::Utils;

import Node;
import Traversal;
import Set;
import List;

@doc{The location of the hooks used inside the plugin}
alias HRel = rel[NameOrExpr hookName, loc at, int priority, Expr regExpr];

@doc{Locations of registered hooks}
alias RHRel = rel[NameOrExpr hookName, loc at];

@doc{Extract the information on declared filters for the given system}
HRel definedFilters(System s) {
    HRel res = { };
    
    for (/c:call(name(name("add_filter")), plist) := s, size(plist) >= 2) {
        if (actualParameter(te:scalar(string(tagname)),_) := plist[0]) {
            if (size(plist) > 2 && actualParameter(scalar(integer(priority)),_) := plist[2]) {
                res = res + < name(name(tagname)), c@at, priority, c >;
            } else {
                res = res + < name(name(tagname)), c@at, 10, c >; // 10 is the default priority
            }
        } else if (actualParameter(te,_) := plist[0]) {
			if (size(plist) > 2 && actualParameter(scalar(integer(priority)),_) := plist[2]) {
			    res = res + < expr(te), c@at, priority, c >;
			} else {
			    res = res + < expr(te), c@at, 10, c >; // 10 is the default priority
			}
		}
    }
    
    return res;
}

@doc{Extract the information on declared actions for the given system}
HRel definedActions(System s) {
    HRel res = { };
    
    for (/c:call(name(name("add_action")), plist) := s, size(plist) >= 2) {
        if (actualParameter(ae:scalar(string(actionName)),_) := plist[0]) {
            if (size(plist) > 2 && actualParameter(scalar(integer(priority)),_) := plist[2]) {
                res = res + < name(name(actionName)), c@at, priority, c >;
            } else {
                res = res + < name(name(actionName)), c@at, 10, c >; // 10 is the default priority
            }
        } else if (actualParameter(ae,_) := plist[0]) {
            if (size(plist) > 2 && actualParameter(scalar(integer(priority)),_) := plist[2]) {
                res = res + < expr(ae), c@at, priority, c >;
            } else {
                res = res + < expr(ae), c@at, 10, c >; // 10 is the default priority
            }
        }
    }
    
    return res;
}

@doc{Find action hooks with computed names defined in the given system}
RHRel findDerivedActionHooksWithLocs(System sys) = 
	{ < expr(e), f@at > | /f:call(name(name("do_action")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e } +
	{ < expr(e), f@at > | /f:call(name(name("do_action_ref_array")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e };

@doc{Find action hooks with literal names defined in the given system}
RHRel findSimpleActionHooksWithLocs(System sys) =
	{ < name(name(e)), f@at > | /f:call(name(name("do_action")),[actualParameter(scalar(string(e)),_),_*]) := sys } +
	{ < name(name(e)), f@at > | /f:call(name(name("do_action_ref_array")),[actualParameter(scalar(string(e)),_),_*]) := sys };

@doc{Find filter hooks with computed names defined in the given system}
RHRel findDerivedFilterHooksWithLocs(System sys) = 
	{ < expr(e), f@at > | /f:call(name(name("apply_filters")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e } +
	{ < expr(e), f@at > | /f:call(name(name("apply_filters_ref_array")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e };

@doc{Find filter hooks with literal names defined in the given system}
RHRel findSimpleFilterHooksWithLocs(System sys) =
	{ < name(name(e)), f@at > | /f:call(name(name("apply_filters")),[actualParameter(scalar(string(e)),_),_*]) := sys } +
	{ < name(name(e)), f@at > | /f:call(name(name("apply_filters_ref_array")),[actualParameter(scalar(string(e)),_),_*]) := sys };

@doc{Find action hooks with computed names defined in the given system}
set[Expr] findDerivedActionHooks(System sys) = 
	{ e | /f:call(name(name("do_action")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e } +
	{ e | /f:call(name(name("do_action_ref_array")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e };

@doc{Find action hooks with literal names defined in the given system}
set[str] findSimpleActionHooks(System sys) =
	{ e | /f:call(name(name("do_action")),[actualParameter(scalar(string(e)),_),_*]) := sys } +
	{ e | /f:call(name(name("do_action_ref_array")),[actualParameter(scalar(string(e)),_),_*]) := sys };
	
@doc{Find filter hooks with computed names defined in the given system}
set[Expr] findDerivedFilterHooks(System sys) = 
	{ e | /f:call(name(name("apply_filters")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e } + 
	{ e | /f:call(name(name("apply_filters_ref_array")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e };

@doc{Find filter hooks with literal names defined in the given system}
set[str] findSimpleFilterHooks(System sys) =
	{ e | /f:call(name(name("apply_filters")),[actualParameter(scalar(string(e)),_),_*]) := sys } +
	{ e | /f:call(name(name("apply_filters_ref_array")),[actualParameter(scalar(string(e)),_),_*]) := sys };
