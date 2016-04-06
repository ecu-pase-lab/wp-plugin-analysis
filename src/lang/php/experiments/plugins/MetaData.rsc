module lang::php::experiments::plugins::MetaData

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::experiments::plugins::Guard;
import lang::php::experiments::plugins::Utils;

import Set;
import List;

@doc{Locations of uses of add_post_meta}
alias PostMetaRel = rel[NameOrExpr postMetaKey, loc at];

@doc{Locations of uses of add_user_meta}
alias UserMetaRel = rel[NameOrExpr userMetaKey, loc at];

@doc{Locations of uses of add_comment_meta}
alias CommentMetaRel = rel[NameOrExpr commentMetaKey, loc at];

@doc{Extract the information on declared post metadata keys for the given system}
PostMetaRel definedPostMetaKeys(System s) {
	return { < wrapExpr(e), c@at > | /c:call(name(name("add_post_meta")),[_,actualParameter(e,_),_*]) := s };
}

@doc{Extract the information on declared user metadata keys for the given system}
UserMetaRel definedUserMetaKeys(System s) {
	return { < wrapExpr(e), c@at > | /c:call(name(name("add_user_meta")),[_,actualParameter(e,_),_*]) := s };
}

@doc{Extract the information on declared comment metadata keys for the given system}
CommentMetaRel definedCommentMetaKeys(System s) {
	return { < wrapExpr(e), c@at > | /c:call(name(name("add_comment_meta")),[_,actualParameter(e,_),_*]) := s };
}
