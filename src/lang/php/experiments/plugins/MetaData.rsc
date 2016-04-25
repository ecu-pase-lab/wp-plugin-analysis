module lang::php::experiments::plugins::MetaData

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::experiments::plugins::Guard;
import lang::php::experiments::plugins::Utils;

import Set;
import List;
import Node;
import Traversal;

@doc{Locations of uses of add_post_meta}
alias PostMetaRel = rel[NameOrExpr postMetaKey, loc at, Guard pathGuard];

@doc{Locations of uses of add_user_meta}
alias UserMetaRel = rel[NameOrExpr userMetaKey, loc at, Guard pathGuard];

@doc{Locations of uses of add_comment_meta}
alias CommentMetaRel = rel[NameOrExpr commentMetaKey, loc at, Guard pathGuard];

@doc{Extract the information on declared post metadata keys for the given system}
public PostMetaRel definedPostMetaKeys(System s) {
	PostMetaRel res = { };
	visit(s.files) {
		case c:call(name(name("add_post_meta")),[_,actualParameter(e,_),_*]) : {
			guardList = buildGuardPath(getTraversalContext());
			pathGuard = isEmpty(guardList) ? notGuarded() : guardedBy(guardList);
			res = res + < wrapExpr(e), c@at, pathGuard >;
		}
	}
	return res;
}

@doc{Extract the information on declared user metadata keys for the given system}
public UserMetaRel definedUserMetaKeys(System s) {
	UserMetaRel res = { };
	visit(s.files) {
		case c:call(name(name("add_user_meta")),[_,actualParameter(e,_),_*]) : {
			guardList = buildGuardPath(getTraversalContext());
			pathGuard = isEmpty(guardList) ? notGuarded() : guardedBy(guardList);
			res = res + < wrapExpr(e), c@at, pathGuard >;
		}
	}
	return res;
}

@doc{Extract the information on declared comment metadata keys for the given system}
public CommentMetaRel definedCommentMetaKeys(System s) {
	CommentMetaRel res = { };
	visit(s.files) {
		case c:call(name(name("add_comment_meta")),[_,actualParameter(e,_),_*]) : {
			guardList = buildGuardPath(getTraversalContext());
			pathGuard = isEmpty(guardList) ? notGuarded() : guardedBy(guardList);
			res = res + < wrapExpr(e), c@at, pathGuard >;
		}
	}
	return res;
}
