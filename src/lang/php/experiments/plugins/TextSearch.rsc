module lang::php::experiments::plugins::TextSearch

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::util::Utils;
import lang::php::util::Corpus;
import lang::php::experiments::plugins::CommentSyntax;
import lang::php::textsearch::Lucene;
import lang::php::pp::PrettyPrinter;

import String;
import util::Math;
import IO;
import ValueIO;

private loc indexBase = |file:///Users/mhills/PHPAnalysis/lucene|;
private loc indexMaps = |file:///Users/mhills/PHPAnalysis/serialized/lucene-indexes|;

public list[Line] getLines(Comment c) {
	list[Line] matchLine(Lines ls) {
		if (ls is singleLine) {
			return [ ls.line ];
		} else if (ls is multipleLines) {
			return [ ls.line ] + matchLine(ls.lines);
		} else {
			println("We have a problem!");
			throw "Problem!";
		}
	}
	return matchLine(c.lines);
}

public str getTextFromTextLines(list[Line] ls) {
	if (size(ls) > 0 && head(ls) is onlyLine) return "<head(ls).text>";
	while (size(ls) > 0 && !(head(ls) is textLine)) ls = tail(ls);
	list[Line] textLines = [ ];
	while (size(ls) > 0 && head(ls) is textLine) { textLines += head(ls); ls = tail(ls); }
	return intercalate(" ", [ "<l.text>" | l <- textLines ] );
}

public str getTextFromTaggedLines(list[Line] ls) {
	if (size(ls) > 0 && head(ls) is onlyTaggedLine) return "<head(ls).text>";
	while (size(ls) > 0 && !(head(ls) is taggedLine || head(ls) is justTaggedLine)) ls = tail(ls);
	return intercalate(" ", [ "<l.text>" | l <- ls, l has text ] );
}

public map[str,str] buildCommentMap(Comment c, map[str,str] commentMap) {
	commentLines = getLines(c);
	text = getTextFromTextLines(commentLines);
	tags = getTextFromTaggedLines(commentLines);
	if (size(trim(text)) > 0) commentMap["text"] = trim(text);
	if (size(trim(tags)) > 0) commentMap["tags"] = trim(tags);
	return commentMap;
}

// Parsing isn't working well, it is generating ambiguities; for now,
// just split on an "@" if we find one.
public map[str,str] buildCommentMap(str c, map[str,str] commentMap, Expr e) {
	commentMap["hook"] = pp(e);
	commentMap["hookparts"] = intercalate(" ", [ p | p <- split("_",pp(e)), p != "wp", size(p) > 2]);
	text = ""; tags = ""; c = trim(c);
	firstAt = findFirst(c,"@");
	if (firstAt > 0) {
		text = c[0..firstAt];
		tags = c[firstAt..];
	} else if (firstAt == -1) {
		text = c;
	} else {
		tags = c;
	}
	commentMap["text"] = text;
	commentMap["tags"] = tags;
	return commentMap;
	//if (size(trim(c)) > 0) {
	//	lastParsed = c;
	//	return buildCommentMap(parse(#Comment,c), commentMap);
	//} else {
	//	return commentMap;
	//}
}

public void buildPluginIndexes() {
	for (v <- sortedWPVersionsWithPlugins()) {
		println("Building index for WordPress <v>");
		indexLoc = indexBase + "wordpress-<v>";
		openIndex(indexLoc);

		pt = normalizeComments(loadBinary("WordPress", v));
		map[int,Expr] idMap = ( );
		int id = 1;
		
		for (/f:call(name(name("do_action")),[actualParameter(e,_),_*]) := pt) {
			if ( (f@phpdoc)? ) {
				idMap[id] = e;
				addDocument( buildCommentMap(f@phpdoc, ("id" : "<id>", "type" : "action"), e) );		
			} else {
				addDocument( buildCommentMap("", ("id" : "<id>", "type" : "action"), e) );
			}
			id += 1;
		}

		for (/f:call(name(name("do_action_ref_array")),[actualParameter(e,_),_*]) := pt) {
			if ( (f@phpdoc)? ) {
				idMap[id] = e;
				addDocument( buildCommentMap(f@phpdoc, ("id" : "<id>", "type" : "action"), e) );		
			} else {
				addDocument( buildCommentMap("", ("id" : "<id>", "type" : "action"), e) );
			}
			id += 1;
		}

		for (/f:call(name(name("apply_filters")),[actualParameter(e,_),_*]) := pt) {
			if ( (f@phpdoc)? ) {
				idMap[id] = e;
				addDocument( buildCommentMap(f@phpdoc, ("id" : "<id>", "type" : "filter"), e) );		
			} else {
				addDocument( buildCommentMap("", ("id" : "<id>", "type" : "filter"), e) );
			}
			id += 1;
		}

		for (/f:call(name(name("apply_filters_ref_array")),[actualParameter(e,_),_*]) := pt) {
			if ( (f@phpdoc)? ) {
				idMap[id] = e;
				addDocument( buildCommentMap(f@phpdoc, ("id" : "<id>", "type" : "filter"), e) );		
			} else {
				addDocument( buildCommentMap("", ("id" : "<id>", "type" : "filter"), e) );
			}
			id += 1;
		}
		
		closeIndex();
		saveIndexMap(idMap,v);
	}	
}

public void checkCommentParser() {
	for (v <- sortedWPVersionsWithPlugins()) {
		checkCommentParser(v);
	}
}

public str lastParsed = "";

public void checkCommentParser(str v) {
	println("Parsing comments for WordPress <v>");

	pt = normalizeComments(loadBinary("WordPress", v));
	
	for (/f:call(name(name("do_action")),[actualParameter(e,_),_*]) := pt) {
		if ( (f@phpdoc)? ) {
			println("Checking at location <f@at>");
			lastParsed = f@phpdoc;
			cpt = parse(#Comment,f@phpdoc);
		}
	}

	for (/f:call(name(name("do_action_ref_array")),[actualParameter(e,_),_*]) := pt) {
		if ( (f@phpdoc)? ) {
			println("Checking at location <f@at>");
			lastParsed = f@phpdoc;
			cpt = parse(#Comment,f@phpdoc);
		}
	}

	for (/f:call(name(name("apply_filters")),[actualParameter(e,_),_*]) := pt) {
		if ( (f@phpdoc)? ) {
			println("Checking at location <f@at>");
			lastParsed = f@phpdoc;
			cpt = parse(#Comment,f@phpdoc);
		}
	}

	for (/f:call(name(name("apply_filters_ref_array")),[actualParameter(e,_),_*]) := pt) {
		if ( (f@phpdoc)? ) {
			println("Checking at location <f@at>");
			lastParsed = f@phpdoc;
			cpt = parse(#Comment,f@phpdoc);
		}
	}
}

public System normalizeComments(System sys) {
	return ( l : normalizeComments(sys[l]) | l <- sys.files );
}

public list[Stmt] lastList = [ ];

public Script normalizeComments(Script s) {
	s = bottom-up visit(s) {
		case f:call(name(name("do_action")), _) : {
			if ( (f@phpdoc)? && size(trim(f@phpdoc)) > 0) {
				; // this is fine
			} else {
				tc = getTraversalContext();
				// Look back up through the context to find the containing statement, we may have the call as a standalone
				// expression or it may be nested inside other expressions, inside strings, etc.
				while (size(tc) >= 1 && Stmt stmt !:= head(tc)) tc = tail(tc);
				if (size(tc) >= 1 && Stmt stmt := head(tc)) {
					// If we found it, check to see if it has a doc comment. If so, use that one.
					if ( (stmt@phpdoc)? && size(trim(stmt@phpdoc)) > 0) {
						insert(f[@phpdoc=stmt@phpdoc]);
					} else {
						// If it doesn't, it may be the case that this statement is one of a list of statements.
						// Check here to see if that is true.
						tc = tail(tc);
						if (size(tc) >= 1 && list[Stmt] slist := head(tc)) {
							// If that is true, we want to look at the elements in the list before this one; if one
							// of them has a doc comment, we will use that, assuming it is a reasonable distance
							// away.
							sIndex = indexOf(slist, stmt);
							if (sIndex == -1) {
								println("Error, statement not found but should be present");
							} else {
								if (sIndex > 0) {
									if (f@at.begin.line == 291) {
										lastList = slist;
									}
									listToSearch = [ li | li <- reverse(slist[0..sIndex]), li is inlineHTML, (li@phpdoc)? && (size(trim(li@phpdoc)) > 0) ];
									if (size(listToSearch) > 0) {
										foundIndex = indexOf(slist, head(listToSearch));
										if (sIndex - foundIndex <= 2) {
											// This is arbitrary, but is says that, if the first statement with a doc comment is
											// one of the prior 3, use that. Normally it will be just one, but this gives us a
											// bit of play without allowing truly distant comments to be used instead.
											insert(f[@phpdoc=head(listToSearch)@phpdoc]);
										}
									}									
								}
							}
						} else {
							println("Unhandled case, statement was not in a list");
						}
					}
				}
			}
		}

		case f:call(name(name("do_action_ref_array")), _) : {
			if ( (f@phpdoc)? && size(trim(f@phpdoc)) > 0) {
				; // this is fine
			} else {
				tc = getTraversalContext();
				// Look back up through the context to find the containing statement, we may have the call as a standalone
				// expression or it may be nested inside other expressions, inside strings, etc.
				while (size(tc) >= 1 && Stmt stmt !:= head(tc)) tc = tail(tc);
				if (size(tc) >= 1 && Stmt stmt := head(tc)) {
					// If we found it, check to see if it has a doc comment. If so, use that one.
					if ( (stmt@phpdoc)? && size(trim(stmt@phpdoc)) > 0) {
						insert(f[@phpdoc=stmt@phpdoc]);
					} else {
						// If it doesn't, it may be the case that this statement is one of a list of statements.
						// Check here to see if that is true.
						tc = tail(tc);
						if (size(tc) >= 1 && list[Stmt] slist := head(tc)) {
							// If that is true, we want to look at the elements in the list before this one; if one
							// of them has a doc comment, we will use that, assuming it is a reasonable distance
							// away.
							sIndex = indexOf(slist, stmt);
							if (sIndex == -1) {
								println("Error, statement not found but should be present");
							} else {
								if (sIndex > 0) {
									listToSearch = [ li | li <- reverse(slist[0..sIndex]), li is inlineHTML, (li@phpdoc)? && (size(trim(li@phpdoc)) > 0) ];
									if (size(listToSearch) > 0) {
										foundIndex = indexOf(slist, head(listToSearch));
										if (sIndex - foundIndex <= 2) {
											// This is arbitrary, but is says that, if the first statement with a doc comment is
											// one of the prior 3, use that. Normally it will be just one, but this gives us a
											// bit of play without allowing truly distant comments to be used instead.
											insert(f[@phpdoc=head(listToSearch)@phpdoc]);
										}
									}									
								}
							}
						} else {
							println("Unhandled case, statement was not in a list");
						}
					}
				}
			}
		}
		
		case f:call(name(name("apply_filters")), _)  : {
			if ( (f@phpdoc)? && size(trim(f@phpdoc)) > 0) {
				; // this is fine
			} else {
				tc = getTraversalContext();
				// Look back up through the context to find the containing statement, we may have the call as a standalone
				// expression or it may be nested inside other expressions, inside strings, etc.
				while (size(tc) >= 1 && Stmt stmt !:= head(tc)) tc = tail(tc);
				if (size(tc) >= 1 && Stmt stmt := head(tc)) {
					// If we found it, check to see if it has a doc comment. If so, use that one.
					if ( (stmt@phpdoc)? && size(trim(stmt@phpdoc)) > 0) {
						insert(f[@phpdoc=stmt@phpdoc]);
					} else {
						// If it doesn't, it may be the case that this statement is one of a list of statements.
						// Check here to see if that is true.
						tc = tail(tc);
						if (size(tc) >= 1 && list[Stmt] slist := head(tc)) {
							// If that is true, we want to look at the elements in the list before this one; if one
							// of them has a doc comment, we will use that, assuming it is a reasonable distance
							// away.
							sIndex = indexOf(slist, stmt);
							if (sIndex == -1) {
								println("Error, statement not found but should be present");
							} else {
								if (sIndex > 0) {
									listToSearch = [ li | li <- reverse(slist[0..sIndex]), li is inlineHTML, (li@phpdoc)? && (size(trim(li@phpdoc)) > 0) ];
									if (size(listToSearch) > 0) {
										foundIndex = indexOf(slist, head(listToSearch));
										if (sIndex - foundIndex <= 2) {
											// This is arbitrary, but is says that, if the first statement with a doc comment is
											// one of the prior 3, use that. Normally it will be just one, but this gives us a
											// bit of play without allowing truly distant comments to be used instead.
											insert(f[@phpdoc=head(listToSearch)@phpdoc]);
										}
									}									
								}
							}
						} else {
							println("Unhandled case, statement was not in a list");
						}
					}
				}
			}
		}
		
		case f:call(name(name("apply_filters_ref_array")), _)  : {
			if ( (f@phpdoc)? && size(trim(f@phpdoc)) > 0) {
				; // this is fine
			} else {
				tc = getTraversalContext();
				// Look back up through the context to find the containing statement, we may have the call as a standalone
				// expression or it may be nested inside other expressions, inside strings, etc.
				while (size(tc) >= 1 && Stmt stmt !:= head(tc)) tc = tail(tc);
				if (size(tc) >= 1 && Stmt stmt := head(tc)) {
					// If we found it, check to see if it has a doc comment. If so, use that one.
					if ( (stmt@phpdoc)? && size(trim(stmt@phpdoc)) > 0) {
						insert(f[@phpdoc=stmt@phpdoc]);
					} else {
						// If it doesn't, it may be the case that this statement is one of a list of statements.
						// Check here to see if that is true.
						tc = tail(tc);
						if (size(tc) >= 1 && list[Stmt] slist := head(tc)) {
							// If that is true, we want to look at the elements in the list before this one; if one
							// of them has a doc comment, we will use that, assuming it is a reasonable distance
							// away.
							sIndex = indexOf(slist, stmt);
							if (sIndex == -1) {
								println("Error, statement not found but should be present");
							} else {
								if (sIndex > 0) {
									listToSearch = [ li | li <- reverse(slist[0..sIndex]), li is inlineHTML, (li@phpdoc)? && (size(trim(li@phpdoc)) > 0) ];
									if (size(listToSearch) > 0) {
										foundIndex = indexOf(slist, head(listToSearch));
										if (sIndex - foundIndex <= 2) {
											// This is arbitrary, but is says that, if the first statement with a doc comment is
											// one of the prior 3, use that. Normally it will be just one, but this gives us a
											// bit of play without allowing truly distant comments to be used instead.
											insert(f[@phpdoc=head(listToSearch)@phpdoc]);
										}
									}									
								}
							}
						} else {
							println("Unhandled case, statement was not in a list");
						}
					}
				}
			}
		}
	}
	
	return s;
}

public void saveIndexMap(map[int,Expr] imap, str version) {
	writeBinaryValueFile(indexMaps + "wordpress-<version>.bin", imap);
}

public map[int,Expr] loadIndexMap(str version) {
	return readBinaryValueFile(#map[int,Expr], indexMaps + "wordpress-<version>.bin");
}

public lrel[int,str,loc]  queryPluginIndex(str queryTerm, str version) {
	indexLoc = indexBase + "wordpress-<version>";
	prepareQueryEngine(indexLoc);
	ids = [ toInt(i) | i <- runQuery(queryTerm) ];
	imap = loadIndexMap(version);
	return [ < i, pp(imap[i]), imap[i]@at > | i <- ids ]; 
}

public lrel[int,str,loc] searchForAction(str queryTerm, str version="4.3.1") {
	return queryPluginIndex("type:action <queryTerm>", version);
}

public lrel[int,str,loc] searchForFilter(str queryTerm, str version="4.3.1") {
	return queryPluginIndex("type:filter <queryTerm>", version);
}

public lrel[int,str,loc] searchForHookName(str hookname, bool partial=true, str version="4.3.1") {
	if (partial) {
		return queryPluginIndex("hookparts:<hookname>", version);
	} else {
		return queryPluginIndex("hook:<hookname>", version);
	}
}

public void displaySearchResults(lrel[int,str,loc] res) {
	for (<id,hook,at> <- res) {
		println("<id>: <hook> at location <at>");
	}
}
