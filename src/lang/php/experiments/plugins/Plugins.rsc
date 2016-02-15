module lang::php::experiments::plugins::Plugins

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::pp::PrettyPrinter;
import lang::php::textsearch::Lucene;
import lang::php::experiments::plugins::CommentSyntax;
import lang::php::analysis::evaluators::AlgebraicSimplification;
import lang::php::analysis::evaluators::SimulateCalls;

import Set;
import Relation;
import List;
import IO;
import ValueIO;
import String;
import util::Math;
import Map;
import DateTime;
import ParseTree;
import Traversal;

private loc pluginDir = baseLoc + "plugins";
private loc pluginBin = baseLoc + "serialized/plugins";
private loc infoBin = baseLoc + "serialized/hook-info";
private loc pluginInfoBin = baseLoc + "serialized/plugin-info";
private loc pluginAnalysisInfoBin = baseLoc + "serialized/plugin-analysis-info";
private loc sqlDir = baseLoc + "generated/plugin-sql";
private loc wpAsPluginBin = baseLoc + "serialized/plugin-wp-info";

@doc{Build serialized ASTs for the given plugin.}
public void buildPluginBinary(str s, loc l, bool overwrite = true, set[str] skip = { }) {
	if (s in skip) {
		return;
	}

    loc binLoc = pluginBin + "<s>.pt";
    if (exists(binLoc) && !overwrite) {
		return;
	}
	
    logMessage("Parsing <s>. \>\> Location: <l>.", 1);
    files = loadPHPFiles(l, addLocationAnnotations=true);
    
    logMessage("Now writing file: <binLoc>...", 2);
    if (!exists(pluginBin)) {
        mkDirectory(pluginBin);
    }
    writeBinaryValueFile(binLoc, files, compression=false);
    logMessage("... done.", 2);
}

@doc{Build serialized ASTs for all plugins.}
public void buildPluginBinaries(bool overwrite = true, set[str] skip = { }) {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    int i = 0;
    for (l <- pluginDirs, l.file notin skip, l.file == "wp-survey-and-poll") {
    	i += 1;
    	println("Building binary #<i> for <l.file>");
        buildPluginBinary(l.file,l,overwrite=overwrite,skip=skip);
    }
}

public void convertPluginBinaries() {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, l.file > "wp-survey-and-poll") {
    	println("Converting binary for <l.file>");
    	loc binLoc = pluginBin + "<l.file>.pt";
    	writeBinaryValueFile(binLoc, convertSystem(readBinaryValueFile(#value, binLoc)), compression=false);
    }
}

@doc{Get the source location for the directory containing the plugin source code}
public loc getPluginSrcLoc(str s) {
    return pluginDir + s;
}

@doc{Get the location for the serialized ASTs for the given plugin}
public loc getPluginBinLoc(str s) {
    return pluginBin + "<s>.pt";
}

@doc{Load the serialized ASTs for the given plugin}
public System loadPluginBinary(str s) {
    loc binLoc = getPluginBinLoc(s);
    if (exists(binLoc)) {
        return readBinaryValueFile(#System, binLoc);
    } else {
        throw "No binary for plugin <s> is available at location <binLoc.path>";
    }
}

@doc{Option type for strings}
data MaybeStr = nothing() | just(str val);

@doc{High-level info for the plugin, stored in the plugin readme}
data PluginInfo = noInfo() | pluginInfo(MaybeStr pluginName, MaybeStr testedUpTo, MaybeStr stableTag, MaybeStr requiresAtLeast);

@doc{Extract high-level info on the plugin from the readme file}
public PluginInfo readPluginInfo(str s) {
    loc srcLoc = getPluginSrcLoc(s);
    if (exists(srcLoc+"readme.txt")) {
        fileContents = readFile(srcLoc+"readme.txt");
        pluginName = (/===<v:.*>===\s+/i := fileContents) ? just(trim(v)) : nothing();
        testedUpTo = (/Tested up to: <v:.*>\s+/i := fileContents) ? just(trim(v)) : nothing();
        stableTag = (/Stable tag: <v:.*>\s+/i := fileContents) ? just(trim(v)) : nothing(); 
        requiresAtLeast = (/Requires at least: <v:.*>\s+/i := fileContents) ? just(trim(v)) : nothing(); 
        return pluginInfo(pluginName, testedUpTo, stableTag, requiresAtLeast);
    } else {
        println("readme.txt not found for plugin <s>");
        return noInfo();
    }
}

@doc{A relation from function names to the location of the function declaration}
alias FRel = rel[str fname, loc at];
@doc{A relation from class names to the location of the class declaration}
alias CRel = rel[str cname, loc at];
@doc{A relation from class x method names to the location of the method declaration}
alias MRel = rel[str cname, str mname, loc at, bool isPublic];
@doc{The location of the hooks used inside the plugin}
alias HRel = rel[NameOrExpr hookName, loc at, int priority, Expr regExpr];
@doc{The location of the constants defined in the plugin}
alias ConstRel = rel[str constName, loc at, Expr constExpr];
@doc{The location of the class constants defined in the plugin}
alias ClassConstRel = rel[str cname, str constName, loc at, Expr constExpr];
@doc{The location of shortcode registrations}
alias ShortcodeRel = rel[NameOrExpr scname, loc at];
@doc{Locations of uses of add_option}
alias OptionRel = rel[NameOrExpr optName, loc at];
@doc{Locations of uses of add_post_meta}
alias PostMetaRel = rel[NameOrExpr postMetaKey, loc at];
@doc{Locations of uses of add_user_meta}
alias UserMetaRel = rel[NameOrExpr userMetaKey, loc at];
@doc{Locations of uses of add_comment_meta}
alias CommentMetaRel = rel[NameOrExpr commentMetaKey, loc at];
@doc{Locations of registered hooks}
alias RHRel = rel[NameOrExpr hookName, loc at];

@doc{The plugin summary, containing extracted information about the plugin.}
data PluginSummary = summary(PluginInfo pInfo, FRel functions, CRel classes, MRel methods, HRel filters, HRel actions, ConstRel consts, ClassConstRel classConsts, ShortcodeRel shortcodes, OptionRel options, PostMetaRel postMetaKeys, UserMetaRel userMetaKeys, CommentMetaRel commentMetaKeys, RHRel providedActionHooks, RHRel providedFilterHooks);

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

@doc{Extract the information on declared WordPress shortcodes for the given system}
ShortcodeRel definedShortcodes(System s) {
	return { < (scalar(string(sn)) := e) ? name(name(sn)) : expr(e), c@at > | /c:call(name(name("add_shortcode")),[actualParameter(e,_),actualParameter(cb,_)]) := s };
}

@doc{Extract the information on declared admin options for WordPress plugins for the given system}
OptionRel definedOptions(System s) {
	return { < (scalar(string(sn)) := e) ? name(name(sn)) : expr(e), c@at > | /c:call(name(name("add_option")),[actualParameter(e,_),_*]) := s };
}

@doc{Extract the information on declared post metadata keys for the given system}
PostMetaRel definedPostMetaKeys(System s) {
	return { < (scalar(string(sn)) := e) ? name(name(sn)) : expr(e), c@at > | /c:call(name(name("add_post_meta")),[_,actualParameter(e,_),_*]) := s };
}

@doc{Extract the information on declared user metadata keys for the given system}
UserMetaRel definedUserMetaKeys(System s) {
	return { < (scalar(string(sn)) := e) ? name(name(sn)) : expr(e), c@at > | /c:call(name(name("add_user_meta")),[_,actualParameter(e,_),_*]) := s };
}

@doc{Extract the information on declared comment metadata keys for the given system}
CommentMetaRel definedCommentMetaKeys(System s) {
	return { < (scalar(string(sn)) := e) ? name(name(sn)) : expr(e), c@at > | /c:call(name(name("add_comment_meta")),[_,actualParameter(e,_),_*]) := s };
}

// TODO: Include file resolution won't work for plugins, that would have to be done over
// specific combinations

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

@doc{Extract a relational summary of the given plugin, passed as a System}
public PluginSummary extractPluginSummary(System pt) {
	return summary(
		noInfo(), 
		definedFunctions(pt),
		definedClasses(pt), 
		definedMethods(pt), 
		definedFilters(pt), 
		definedActions(pt), 
		definedConstants(pt), 
		definedClassConstants(pt), 
		definedShortcodes(pt), 
		definedOptions(pt), 
		definedPostMetaKeys(pt), 
		definedUserMetaKeys(pt), 
		definedCommentMetaKeys(pt), 
		findSimpleActionHooksWithLocs(pt) + findDerivedActionHooksWithLocs(pt), 
		findSimpleFilterHooksWithLocs(pt) + findDerivedFilterHooksWithLocs(pt));
}

@doc{Extract a relational summary of the given plugin from a pre-parsed plugin binary}
public void extractPluginSummary(str pluginName) {
    pt = loadPluginBinary(pluginName);
	s = summary(
		readPluginInfo(pluginName), 
		definedFunctions(pt),
		definedClasses(pt),
		definedMethods(pt), 
		definedFilters(pt), 
		definedActions(pt), 
		definedConstants(pt), 
		definedClassConstants(pt), 
		definedShortcodes(pt), 
		definedOptions(pt), 
		definedPostMetaKeys(pt), 
		definedUserMetaKeys(pt), 
		definedCommentMetaKeys(pt), 
		findSimpleActionHooksWithLocs(pt) + findDerivedActionHooksWithLocs(pt), 
		findSimpleFilterHooksWithLocs(pt) + findDerivedFilterHooksWithLocs(pt));
    if (!exists(pluginInfoBin)) mkDirectory(pluginInfoBin);
    writeBinaryValueFile(pluginInfoBin + "<pluginName>-summary.bin", s);   
}

@doc{Extract plugin summaries for all pre-parsed plugin binaries}
public void extractPluginSummary(bool overwrite = true) {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file))) {
    	if ( (overwrite && exists(pluginInfoBin+"<l.file>-info.bin")) || !exists(pluginInfoBin+"<l.file>-info.bin")) { 
	        println("Extracting info for plugin: <l.file>");
	        extractPluginSummary(l.file);
		} else {
			println("Already extracted info for plugin: <l.file>");
		}
    }
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
	
@doc{Find all derived action hooks defined across all versions of WordPress}
rel[str,Expr] findDerivedActionHooks() {
	return { < v, e > | v <- getVersions("WordPress"), pt := loadBinary("WordPress",v), e <- findDerivedActionHooks(pt) };
}

@doc{Find all simple action hooks defined across all versions of WordPress}
rel[str,str] findSimpleActionHooks() {
	return { < v, e > | v <- getVersions("WordPress"), pt := loadBinary("WordPress",v), e <- findSimpleActionHooks(pt) };
}

@doc{Find filter hooks with computed names defined in the given system}
set[Expr] findDerivedFilterHooks(System sys) = 
	{ e | /f:call(name(name("apply_filters")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e } + 
	{ e | /f:call(name(name("apply_filters_ref_array")),[actualParameter(e,_),_*]) := sys, scalar(string(_)) !:= e };

@doc{Find filter hooks with literal names defined in the given system}
set[str] findSimpleFilterHooks(System sys) =
	{ e | /f:call(name(name("apply_filters")),[actualParameter(scalar(string(e)),_),_*]) := sys } +
	{ e | /f:call(name(name("apply_filters_ref_array")),[actualParameter(scalar(string(e)),_),_*]) := sys };
	
@doc{Find all derived filter hooks defined across all versions of WordPress}
rel[str,Expr] findDerivedFilterHooks() {
	return { < v, e > | v <- getVersions("WordPress"), pt := loadBinary("WordPress",v), e <- findDerivedFilterHooks(pt) };
}

@doc{Find all simple filter hooks defined across all versions of WordPress}
rel[str,str] findSimpleFilterHooks() {
	return { < v, e > | v <- getVersions("WordPress"), pt := loadBinary("WordPress",v), e <- findSimpleFilterHooks(pt) };
}

@doc{Show changes in defined hooks across WordPress versions}
void showSimpleHookChanges(rel[str,str] simpleHooks) {
	sv = getSortedVersions("WordPress");
	for (idx <- index(sv)) {
		if (idx == 0) {
			println("Version <sv[idx]> has <size(simpleHooks[sv[idx]])> hooks");
		} else {
			newHooks = simpleHooks[sv[idx]] - simpleHooks[sv[idx-1]];
			removedHooks = simpleHooks[sv[idx-1]] - simpleHooks[sv[idx]];
			println("Version <sv[idx]> has <size(simpleHooks[sv[idx]])> hooks");
			if (size(newHooks) > 0) {
				println("\tNew Hooks are <newHooks>");
			}
			if (size(removedHooks) > 0) {
				println("\tRemoved Hooks are <removedHooks>");
			}
		}
	}
}

@doc{Extract information about all defined hooks from all versions of WordPress}
void extractHookInfo() {
	println("Extracting and writing simple filter-related hooks");
	saveSimpleFilterHooks(findSimpleFilterHooks());

	println("Extracting and writing simple action-related hooks");
	saveSimpleActionHooks(findSimpleActionHooks());

	println("Extracting and writing derived filter-related hooks");
	saveDerivedFilterHooks(findDerivedFilterHooks());

	println("Extracting and writing derived filter-related hooks");
	saveDerivedActionHooks(findDerivedActionHooks());
}

@doc{Write information on simple filter hooks defined in all versions of WordPress}
void saveSimpleFilterHooks(rel[str,str] simpleHooks) {
	writeBinaryValueFile(infoBin + "simpleFilterHooks.bin", simpleHooks);		
}

@doc{Write information on simple action hooks defined in all versions of WordPress}
void saveSimpleActionHooks(rel[str,str] simpleHooks) {
	writeBinaryValueFile(infoBin + "simpleActionHooks.bin", simpleHooks);		
}

@doc{Write information on derived filter hooks defined in all versions of WordPress}
void saveDerivedFilterHooks(rel[str,Expr] derivedHooks) {
	writeBinaryValueFile(infoBin + "derivedFilterHooks.bin", derivedHooks);		
}

@doc{Write information on derived action hooks defined in all versions of WordPress}
void saveDerivedActionHooks(rel[str,Expr] derivedHooks) {
	writeBinaryValueFile(infoBin + "derivedActionHooks.bin", derivedHooks);		
}

@doc{Read information on simple filter hooks defined in all versions of WordPress}
rel[str,str] loadSimpleFilterHooks() {
	return readBinaryValueFile(#rel[str,str], infoBin + "simpleFilterHooks.bin");		
}

@doc{Read information on simple action hooks defined in all versions of WordPress}
rel[str,str] loadSimpleActionHooks() {
	return readBinaryValueFile(#rel[str,str], infoBin + "simpleActionHooks.bin");		
}

@doc{Read information on derived filter hooks defined in all versions of WordPress}
rel[str,Expr] loadDerivedFilterHooks() {
	return readBinaryValueFile(#rel[str,Expr], infoBin + "derivedFilterHooks.bin");		
}

@doc{Read information on derived action hooks defined in all versions of WordPress}
rel[str,Expr] loadDerivedActionHooks() {
	return readBinaryValueFile(#rel[str,Expr], infoBin + "derivedActionHooks.bin");		
}

@doc{Load the summary for the given plugin}
PluginSummary loadPluginSummary(str pluginName) {
	return readBinaryValueFile(#PluginSummary, pluginInfoBin + "<pluginName>-summary.bin");
}

@doc{Get the plugin info from an existing plugin summary}
PluginInfo getPluginInfo(str pluginName) {
	psum = loadPluginSummary(pluginName);
	return psum.pInfo;
}

@doc{Return the functions defined in a given plugin.}
rel[str,str] pluginFunctions(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, fname > | <fname, floc> <- psum.functions };
}

@doc{Return the functions defined in a given plugin, including the def location.}
rel[str,str,loc] pluginFunctionsWithLocs(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, fname, floc > | <fname, floc> <- psum.functions };
}

@doc{Return the functions defined in all plugins in the corpus with the plugin name as first projection}
rel[str,str] pluginFunctions() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, fn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn,fn > <- pluginFunctions(l.file) }; 
}

@doc{Return the functions defined in all plugins in the corpus with the plugin name as first projection and including the def loc}
rel[str,str,loc] pluginFunctionsWithLocs() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, fn, fl > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn,fn,fl > <- pluginFunctionsWithLocs(l.file) }; 
}

@doc{Return the classes and methods defined in a given plugin.}
rel[str,str,str] pluginMethods(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, cname, mname > | < cname, mname, mloc > <- psum.methods };
}

@doc{Return the classes and methods defined in a given plugin, including the def location.}
rel[str,str,str,loc] pluginMethodsWithLocs(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, cname, mname, mloc > | < cname, mname, mloc > <- psum.methods };
}

@doc{Return the classes and methods defined in all plugins in the corpus with the plugin name as first projection}
rel[str,str,str] pluginMethods() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, cn, mn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, cn, mn > <- pluginMethods(l.file) }; 
}

@doc{Return the classes and methods defined in all plugins in the corpus with the plugin name as first projection and including the def loc}
rel[str,str,str,loc] pluginMethodsWithLocs() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, cn, mn, ml > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, cn, mn, ml > <- pluginMethodsWithLocs(l.file) }; 
}

@doc{Return the constants defined in a given plugin.}
rel[str,str] pluginConstants(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, cname > | <cname, cloc> <- psum.consts };
}

@doc{Return the constants defined in all plugins in the corpus with the plugin name as first projection}
rel[str,str] pluginConstants() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, cn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn,cn > <- pluginConstants(l.file) }; 
}

@doc{Return the class constants defined in a given plugin.}
rel[str,str,str] pluginClassConstants(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, cname, xname > | <cname, xname, cloc> <- psum.classConsts };
}

@doc{Return the class constants defined in all plugins in the corpus with the plugin name as first projection}
rel[str,str,str] pluginClassConstants() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, cn, xn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn,cn,xn > <- pluginClassConstants(l.file) }; 
}

@doc{Return the shortcodes defined in a given plugin.}
rel[str,NameOrExpr] pluginShortcodes(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, e > | < e, _ > <- psum.shortcodes };
}

@doc{Return the shortcodes defined in all plugins in the corpus with the plugin name as first projection}
rel[str,NameOrExpr] pluginShortcodes() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, sn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, sn > <- pluginShortcodes(l.file) }; 
}

@doc{Return the options defined in a given plugin.}
rel[str,NameOrExpr] pluginOptions(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, e > | < e, _ > <- psum.options };
}

@doc{Return the options defined in all plugins in the corpus with the plugin name as first projection}
rel[str,NameOrExpr] pluginOptions() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, sn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, sn > <- pluginOptions(l.file) }; 
}

@doc{Return the post meta keys defined in a given plugin.}
rel[str,NameOrExpr] pluginPostMetaKeys(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, e > | < e, _ > <- psum.postMetaKeys };
}

@doc{Return the post meta keys defined in all plugins in the corpus with the plugin name as first projection}
rel[str,NameOrExpr] pluginPostMetaKeys() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, sn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, sn > <- pluginPostMetaKeys(l.file) }; 
}

@doc{Return the user meta keys defined in a given plugin.}
rel[str,NameOrExpr] pluginUserMetaKeys(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, e > | < e, _ > <- psum.userMetaKeys };
}

@doc{Return the user meta keys defined in all plugins in the corpus with the plugin name as first projection}
rel[str,NameOrExpr] pluginUserMetaKeys() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, sn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, sn > <- pluginUserMetaKeys(l.file) }; 
}

@doc{Return the comment meta keys defined in a given plugin.}
rel[str,NameOrExpr] pluginCommentMetaKeys(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, e > | < e, _ > <- psum.commentMetaKeys };
}

@doc{Return the comment meta keys defined in all plugins in the corpus with the plugin name as first projection}
rel[str,NameOrExpr] pluginCommentMetaKeys() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, sn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, sn > <- pluginCommentMetaKeys(l.file) }; 
}

@doc{Return the actions defined in a given plugin.}
rel[str,str] pluginActions(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, (name(name(n)) := e) ? n : pp(e) > | < e, _, _ > <- psum.actions };
}

@doc{Return the actions defined in all plugins in the corpus with the plugin name as first projection}
rel[str,str] pluginActions() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, sn > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, sn > <- pluginActions(l.file) }; 
}

@doc{Return the actions defined in a given plugin.}
rel[str,Expr,loc] unresolvedPluginActions(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, en, l > | < e, l, _ > <- psum.actions, expr(en) := e };
}

@doc{Return the actions defined in all plugins in the corpus with the plugin name as first projection}
rel[str,Expr,loc] unresolvedPluginActions() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, sn, el > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, sn, el > <- unresolvedPluginActions(l.file) }; 
}

@doc{Given a rel of plugin x function, return a map that, for each function, gives the plugins where it is defined.}
map[str,set[str]] definingPluginsForFunctions(rel[str,str] pfuns) {
	flipped = invert(pfuns);
	map[str,set[str]] res = ( );
	for (< fn, pn > <- flipped) {
		if (fn in res) {
			res[fn] = res[fn] + pn;
		} else {
			res[fn] = { pn };
		}
	}
	return res;
}

@doc{Given a rel of plugin x class name x method name, return a map that, for each class, gives the plugins where it is defined.}
map[str,set[str]] definingPluginsForClasses(rel[str,str,str] pmethods) {
	flipped = invert(pmethods<0,1>);
	map[str,set[str]] res = ( );
	for (< cn, pn > <- flipped) {
		if (cn in res) {
			res[cn] = res[cn] + pn;
		} else {
			res[cn] = { pn };
		}
	}
	return res;
}

@doc{Given a rel of plugin x class name x method name, return a map that, for each class and method, gives the plugins where it is defined.}
map[tuple[str,str],set[str]] definingPluginsForMethods(rel[str,str,str] pmethods) {
	flipped = { < cn, mn, pn > | < pn, cn, mn > <- pmethods };
	map[tuple[str,str],set[str]] res = ( );
	for (< cn, mn, pn > <- flipped) {
		if ( < cn, mn > in res) {
			res[< cn, mn >] = res[< cn, mn >] + pn;
		} else {
			res[< cn, mn >] = { pn };
		}
	}
	return res;
}

@doc{Given a rel of plugin x const, return a map that, for each const, gives the plugins where it is defined.}
map[str,set[str]] definingPluginsForConstants(rel[str,str] pconsts) {
	flipped = invert(pconsts);
	map[str,set[str]] res = ( );
	for (< cn, pn > <- flipped) {
		if (cn in res) {
			res[cn] = res[cn] + pn;
		} else {
			res[cn] = { pn };
		}
	}
	return res;
}

@doc{Given a rel of plugin x class name x const, return a map that, for each class name x const, gives the plugins where it is defined.}
map[tuple[str,str],set[str]] definingPluginsForClassConstants(rel[str,str,str] pconsts) {
	flipped = { < cn, xn, pn > | < pn, cn, xn > <- pconsts };
	map[tuple[str,str],set[str]] res = ( );
	for (< cn, xn, pn > <- flipped) {
		if ( < cn, xn > in res) {
			res[< cn, xn >] = res[< cn, xn >] + pn;
		} else {
			res[< cn, xn >] = { pn };
		}
	}
	return res;
}

@doc{Given a rel of plugin x shortcode name, return a map that, for each shortcode name, gives the plugins where it is defined.}
map[NameOrExpr,set[str]] definingPluginsForShortcodes(rel[str,NameOrExpr] shortcodes) {
	flipped = { < sn, pn > | < pn, sn > <- shortcodes };
	map[NameOrExpr,set[str]] res = ( );
	for (< sn, pn > <- flipped) {
		if ( sn in res) {
			res[sn] = res[sn] + pn;
		} else {
			res[sn] = { pn };
		}
	}
	return res;
}

@doc{Given a rel of plugin x option name, return a map that, for each option, gives the plugins where it is defined.}
map[NameOrExpr,set[str]] definingPluginsForOptions(rel[str,NameOrExpr] options) {
	flipped = { < sn, pn > | < pn, sn > <- options };
	map[NameOrExpr,set[str]] res = ( );
	for (< sn, pn > <- flipped) {
		if ( sn in res) {
			res[sn] = res[sn] + pn;
		} else {
			res[sn] = { pn };
		}
	}
	return res;
}

@doc{Given a rel of plugin x post/user/comment meta key name, return a map that, for each meta key, gives the plugins where it is defined.}
map[NameOrExpr,set[str]] definingPluginsForMetaKeys(rel[str,NameOrExpr] keys) {
	flipped = { < sn, pn > | < pn, sn > <- keys };
	map[NameOrExpr,set[str]] res = ( );
	for (< sn, pn > <- flipped) {
		if ( sn in res) {
			res[sn] = res[sn] + pn;
		} else {
			res[sn] = { pn };
		}
	}
	return res;
}

@doc{Get the names of any functions defined multiple times}
set[str] multiplyDefinedFunctions(map[str,set[str]] definers) = { f | f <- definers, size(definers[f]) > 1 };

@doc{Get the names of any classes defined multiple times}
set[str] multiplyDefinedClasses(map[str,set[str]] definers) = { c | c <- definers, size(definers[c]) > 1 };

@doc{Get the names of any methods defined multiple times}
rel[str,str] multiplyDefinedMethods(map[tuple[str,str],set[str]] definers) = { cm | cm <- definers, size(definers[cm]) > 1 };

@doc{Get the names of any constants defined multiple times}
set[str] multiplyDefinedConstants(map[str,set[str]] definers) = { f | f <- definers, size(definers[f]) > 1 };

@doc{Get the names of any shortcodes defined multiple times}
set[NameOrExpr] multiplyDefinedShortcodes(map[NameOrExpr,set[str]] definers) = { cm | cm <- definers, size(definers[cm]) > 1 };

@doc{Get the names of any options defined multiple times}
set[NameOrExpr] multiplyDefinedOptions(map[NameOrExpr,set[str]] definers) = { cm | cm <- definers, size(definers[cm]) > 1 };

@doc{Get the names of any keys defined multiple times}
set[NameOrExpr] multiplyDefinedKeys(map[NameOrExpr,set[str]] definers) = { cm | cm <- definers, size(definers[cm]) > 1 };

set[NameOrExpr] multiplyDefinedPostMetaKeys() {
	return multiplyDefinedKeys(definingPluginsForMetaKeys(pluginPostMetaKeys()));
}

set[NameOrExpr] multiplyDefinedUserMetaKeys() {
	return multiplyDefinedKeys(definingPluginsForMetaKeys(pluginUserMetaKeys()));
}

set[NameOrExpr] multiplyDefinedCommentMetaKeys() {
	return multiplyDefinedKeys(definingPluginsForMetaKeys(pluginCommentMetaKeys()));
}

data FunctionInfo = functionInfo(int totalFunctions, int inPlugins, int conflictingFunctions, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data ClassInfo = classInfo(int totalClasses, int inPlugins, int conflictingClasses, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data MethodInfo = methodInfo(int totalMethods, int inPlugins, int conflictingMethods, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data ConstInfo = constInfo(int totalConsts, int conflictingConsts, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data ClassConstInfo = classConstInfo(int totalClassConsts, int conflictingClassConsts, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data MetaKeyInfo = metaKeyInfo(int totalOccurrences, int totalKeysDefined, int conflictingKeys, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data ShortcodeInfo = shortcodeInfo(int totalOccurrences, int totalShortcodesDefined, int conflictingShortcodes, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data OptionInfo = optionInfo(int totalOccurrences, int totalOptionsDefined, int conflictingOptions, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

real intListMedian(list[int] nums) {
	if (size(nums) == 0) throw "Cannot use on empty list!";
	
	if (size(nums) % 2 == 0) {
		idx2 = size(nums) / 2;
		idx1 = idx2 - 1;
		return toReal(nums[idx1] + nums[idx2]) / 2.0;
	} else {
		idx = (size(nums)-1)/2;
		return toReal(nums[idx]);
	}
}

FunctionInfo computeFunctionInfo(rel[str,str] functions) {
	// Upper-case the functions, since they are actually case insensitive
	functions = { < p, toUpperCase(f) > | < p, f > <- functions };
	
	// Next, compute the map for defining plugins
	definingPlugins = definingPluginsForFunctions(functions);
	
	// Now, find out which of these are multiply defined
	multiplyDefined = domainR(definingPlugins,multiplyDefinedFunctions(definingPlugins));
	involvedPlugins = { p | f <- multiplyDefined, p <- multiplyDefined[f] };
	
	// How many conflicts are there? This is the sum of the sets in the multiply defined map
	totalConflicts = size([pn | kn <- multiplyDefined, pn <- multiplyDefined[kn]]);
	
	// What is the smallest conflict set?
	smallestSet = totalConflicts; // We know it's smaller than this...
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) < smallestSet) smallestSet = size(multiplyDefined[kn]);
	
	// What is the largest conflict set?
	biggestSet = 0;
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) > biggestSet) biggestSet = size(multiplyDefined[kn]);
	
	// What is the median conflict set?
	real medianSet = intListMedian(sort([ size(multiplyDefined[kn]) | kn <- multiplyDefined ]));
	
	return functionInfo(size(functions), size(functions<0>), size(multiplyDefined<0>), size(involvedPlugins), totalConflicts, smallestSet, medianSet, biggestSet); 
}

ClassInfo computeClassInfo(rel[str,str,str] methods) {
	// Upper-case the classes and methods, since they are actually case insensitive
	methods = { < p, toUpperCase(c), toUpperCase(m) > | < p, c, m > <- methods };

	// Next, compute the map for defining plugins
	definingPlugins = definingPluginsForClasses(methods);
	
	// Now, find out which of these are multiply defined
	multiplyDefined = domainR(definingPlugins,multiplyDefinedClasses(definingPlugins));
	involvedPlugins = { p | c <- multiplyDefined, p <- multiplyDefined[c] };
	
	// How many conflicts are there? This is the sum of the sets in the multiply defined map
	totalConflicts = size([pn | kn <- multiplyDefined, pn <- multiplyDefined[kn]]);
	
	// What is the smallest conflict set?
	smallestSet = totalConflicts; // We know it's smaller than this...
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) < smallestSet) smallestSet = size(multiplyDefined[kn]);
	
	// What is the largest conflict set?
	biggestSet = 0;
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) > biggestSet) biggestSet = size(multiplyDefined[kn]);
	
	// What is the median conflict set?
	real medianSet = intListMedian(sort([ size(multiplyDefined[kn]) | kn <- multiplyDefined ]));
	
	return classInfo(size(methods<0,1>), size(methods<0>), size(multiplyDefined<0>), size(involvedPlugins), totalConflicts, smallestSet, medianSet, biggestSet); 
}

MethodInfo computeMethodInfo(rel[str,str,str] methods) {
	// Upper-case the classes and methods, since they are actually case insensitive
	methods = { < p, toUpperCase(c), toUpperCase(m) > | < p, c, m > <- methods };

	// Next, compute the map for defining plugins
	definingPlugins = definingPluginsForMethods(methods);
	
	// Now, find out which of these are multiply defined
	multiplyDefined = domainR(definingPlugins,multiplyDefinedMethods(definingPlugins));
	involvedPlugins = { p | cm <- multiplyDefined, p <- multiplyDefined[cm] };
	
	// How many conflicts are there? This is the sum of the sets in the multiply defined map
	totalConflicts = size([pn | kn <- multiplyDefined, pn <- multiplyDefined[kn]]);
	
	// What is the smallest conflict set?
	smallestSet = totalConflicts; // We know it's smaller than this...
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) < smallestSet) smallestSet = size(multiplyDefined[kn]);
	
	// What is the largest conflict set?
	biggestSet = 0;
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) > biggestSet) biggestSet = size(multiplyDefined[kn]);
	
	// What is the median conflict set?
	real medianSet = intListMedian(sort([ size(multiplyDefined[kn]) | kn <- multiplyDefined ]));
	
	return methodInfo(size(methods), size(methods<0>), size(multiplyDefined<0>), size(involvedPlugins), totalConflicts, smallestSet, medianSet, biggestSet); 
}

ConstInfo computeConstantInfo(rel[str,str] consts) {
	// Next, compute the map for defining plugins
	definingPlugins = definingPluginsForConstants(consts);
	
	// Now, find out which of these are multiply defined
	multiplyDefined = domainR(definingPlugins,multiplyDefinedConstants(definingPlugins));
	involvedPlugins = { p | f <- multiplyDefined, p <- multiplyDefined[f] };
	
	// How many conflicts are there? This is the sum of the sets in the multiply defined map
	totalConflicts = size([pn | kn <- multiplyDefined, pn <- multiplyDefined[kn]]);
	
	// What is the smallest conflict set?
	smallestSet = totalConflicts; // We know it's smaller than this...
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) < smallestSet) smallestSet = size(multiplyDefined[kn]);
	
	// What is the largest conflict set?
	biggestSet = 0;
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) > biggestSet) biggestSet = size(multiplyDefined[kn]);
	
	// What is the median conflict set?
	real medianSet = intListMedian(sort([ size(multiplyDefined[kn]) | kn <- multiplyDefined ]));
	
	return constInfo(size(consts), size(multiplyDefined<0>), size(involvedPlugins), totalConflicts, smallestSet, medianSet, biggestSet); 
}

ClassConstInfo computeClassConstantInfo(rel[str,str,str] cconsts) {
	// Next, compute the map for defining plugins
	definingPlugins = definingPluginsForClassConstants(cconsts);
	
	// Now, find out which of these are multiply defined
	multiplyDefined = domainR(definingPlugins,multiplyDefinedMethods(definingPlugins));
	involvedPlugins = { p | cm <- multiplyDefined, p <- multiplyDefined[cm] };
	
	// How many conflicts are there? This is the sum of the sets in the multiply defined map
	totalConflicts = size([pn | kn <- multiplyDefined, pn <- multiplyDefined[kn]]);
	
	// What is the smallest conflict set?
	smallestSet = totalConflicts; // We know it's smaller than this...
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) < smallestSet) smallestSet = size(multiplyDefined[kn]);
	
	// What is the largest conflict set?
	biggestSet = 0;
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) > biggestSet) biggestSet = size(multiplyDefined[kn]);
	
	// What is the median conflict set?
	real medianSet = intListMedian(sort([ size(multiplyDefined[kn]) | kn <- multiplyDefined ]));
	
	return classConstInfo(size(cconsts), size(multiplyDefined<0>), size(involvedPlugins), totalConflicts, smallestSet, medianSet, biggestSet); 
}

MetaKeyInfo computeMetaKeyConflictInfo(rel[str,NameOrExpr] metaKeys) {
	println("Given <size(metaKeys)> occurrences in <size(metaKeys<0>)> plugins");

	// First, filter to just include those that are given as names, not as expressions
	filteredKeys =  { < s, k > | < s, k > <- metaKeys, k is name };
	
	println("After filtering, there are <size(filteredKeys)> occurrences in <size(filteredKeys<0>)> plugins");

	// Next, compute the map for defining plugins
	definingPlugins = definingPluginsForMetaKeys(filteredKeys);
	
	// Now, find out which of these are multiply defined
	multiplyDefined = domainR(definingPlugins,multiplyDefinedKeys(definingPlugins));
	involvedPlugins = { p | cm <- multiplyDefined, p <- multiplyDefined[cm] };
	
	// How many conflicts are there? This is the sum of the sets in the multiply defined map
	totalConflicts = size([pn | kn <- multiplyDefined, pn <- multiplyDefined[kn]]);
	
	// What is the smallest conflict set?
	smallestSet = totalConflicts; // We know it's smaller than this...
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) < smallestSet) smallestSet = size(multiplyDefined[kn]);
	
	// What is the largest conflict set?
	biggestSet = 0;
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) > biggestSet) biggestSet = size(multiplyDefined[kn]);
	
	// What is the median conflict set?
	real medianSet = intListMedian(sort([ size(multiplyDefined[kn]) | kn <- multiplyDefined ]));
	
	return metaKeyInfo(size(metaKeys), size(filteredKeys<1>), size(multiplyDefined<0>), size(involvedPlugins), totalConflicts, smallestSet, medianSet, biggestSet); 
}

ShortcodeInfo computeShortcodeConflictInfo(rel[str,NameOrExpr] shortcodes) {
	println("Given <size(shortcodes)> occurrences in <size(shortcodes<0>)> plugins");
	
	// First, filter to just include those that are given as names, not as expressions
	filteredShortcodes =  { < s, k > | < s, k > <- shortcodes, k is name };
	
	println("After filtering, there are <size(filteredShortcodes)> occurrences in <size(filteredShortcodes<0>)> plugins");
	
	// Next, compute the map for defining plugins
	definingPlugins = definingPluginsForShortcodes(filteredShortcodes);
	
	// Now, find out which of these are multiply defined
	multiplyDefined = domainR(definingPlugins,multiplyDefinedShortcodes(definingPlugins));
	involvedPlugins = { p | cm <- multiplyDefined, p <- multiplyDefined[cm] };
	
	// How many conflicts are there? This is the sum of the sets in the multiply defined map
	totalConflicts = size([pn | kn <- multiplyDefined, pn <- multiplyDefined[kn]]);
	
	// What is the smallest conflict set?
	smallestSet = totalConflicts; // We know it's smaller than this...
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) < smallestSet) smallestSet = size(multiplyDefined[kn]);
	
	// What is the largest conflict set?
	biggestSet = 0;
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) > biggestSet) biggestSet = size(multiplyDefined[kn]);
	
	// What is the median conflict set?
	real medianSet = intListMedian(sort([ size(multiplyDefined[kn]) | kn <- multiplyDefined ]));
	
	return shortcodeInfo(size(shortcodes), size(filteredShortcodes<1>), size(multiplyDefined<0>), size(involvedPlugins), totalConflicts, smallestSet, medianSet, biggestSet); 
}

OptionInfo computeOptionConflictInfo(rel[str,NameOrExpr] options) {
	println("Given <size(options)> occurrences in <size(options<0>)> plugins");

	// First, filter to just include those that are given as names, not as expressions
	filteredOptions =  { < s, k > | < s, k > <- options, k is name };
	
	println("After filtering, there are <size(filteredOptions)> occurrences in <size(filteredOptions<0>)> plugins");
	
	// Next, compute the map for defining plugins
	definingPlugins = definingPluginsForOptions(filteredOptions);
	
	// Now, find out which of these are multiply defined
	multiplyDefined = domainR(definingPlugins,multiplyDefinedOptions(definingPlugins));
	involvedPlugins = { p | cm <- multiplyDefined, p <- multiplyDefined[cm] };
	
	// How many conflicts are there? This is the sum of the sets in the multiply defined map
	totalConflicts = size([pn | kn <- multiplyDefined, pn <- multiplyDefined[kn]]);
	
	// What is the smallest conflict set?
	smallestSet = totalConflicts; // We know it's smaller than this...
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) < smallestSet) smallestSet = size(multiplyDefined[kn]);
	
	// What is the largest conflict set?
	biggestSet = 0;
	for (kn <- multiplyDefined, size(multiplyDefined[kn]) > biggestSet) biggestSet = size(multiplyDefined[kn]);
	
	// What is the median conflict set?
	real medianSet = intListMedian(sort([ size(multiplyDefined[kn]) | kn <- multiplyDefined ]));
	
	return optionInfo(size(options), size(filteredOptions<1>), size(multiplyDefined<0>), size(involvedPlugins), totalConflicts, smallestSet, medianSet, biggestSet); 
}

@doc{For methods with multiple definitions, cluster these so we can see how many different versions exist and which plugins share the same versions}
map[tuple[str,str],set[set[str]]] clusterMultiplyDefinedMethods(rel[str,str] mdMethods, map[tuple[str,str],set[str]] definers) {
	map[tuple[str,str],set[set[str]]] res = ( );
	for ( < cn, mn > <- mdMethods ) {
		println("Clustering plugins for class <cn>, method <mn>");
		defs = { < d, mdef > | d <-  definers[ < cn, mn > ], /mdef:method(mn, mods, byRef, params, body) := loadPluginBinary(d) };
		flipdefs = invert(defs);
		res[<cn,mn>] = { flipdefs[md] | md <- flipdefs<0> };  
	}
	return res;
}

@doc{For classes with multiple definitions, cluster these so we can see how many different versions exist and which plugins share the same versions}
map[str,set[set[str]]] clusterMultiplyDefinedClasses(set[str] mdClasses, map[str,set[str]] definers) {
	map[str,set[set[str]]] res = ( );
	for ( cn <- mdClasses ) {
		println("Clustering plugins for class <cn>");
		defs = { < d, cdef > | d <-  definers[ cn ], /cdef:class(cn, _, _, _, _) := loadPluginBinary(d) };
		flipdefs = invert(defs);
		res[cn] = { flipdefs[cd] | cd <- flipdefs<0> };  
	}
	return res;
}

map[tuple[str,str],set[set[str]]] runMethodClustering() {
	pm = pluginMethods();
	map[tuple[str,str],set[str]] dpm = definingPluginsForMethods(pm);
	rel[str,str] mdm = multiplyDefinedMethods(dpm);
	lrel[str cn, str mn] dpmTop = []; lrel[str cn, str mn] dpmRandom = [];
	
	// Keep only those class/method combos that are multiply defined
	map[tuple[str,str],set[str]] dpmRestricted = domainR(dpm,mdm);
	// Then, sort them from most defs to fewest (but still > 1)
	lrel[str cn, str mn] dpmSorted = reverse(sort([ mni | mni <- dpmRestricted ], bool (tuple[str,str] i1, tuple[str,str] i2) { return dpmRestricted[i1] < dpmRestricted[i2]; }));
	
	bool writeTop = false;
	bool writeRandom = false;
	
	// Assuming this wasn't passed in, pick the class x method combos defined in the most plugins
	if (isEmpty(dpmTop)) {
		writeTop = true;
		dpmTop = head(dpmSorted,100); // NOTE: We know there are more than 100, else we would need to check
	}
	
	// Assuming this wasn't passed in, pick 100 class x method combos that are not already in the top 100
	if (isEmpty(dpmRandom)) {
		writeRandom = true;
		// We also know we have more than 200 choices, or we would need to check here as well...
		for (i <- [0..100]) {
			randomChoice = arbInt(size(dpmSorted));
			while (randomChoice < size(dpmTop)) randomChoice = arbInt(size(dpmSorted));
			while (dpmSorted[randomChoice] in dpmRandom) randomChoice = arbInt(size(dpmSorted));
			dpmRandom = dpmRandom + dpmSorted[randomChoice];
		}
	}

	if (writeTop || writeRandom) {		
		println("Writing chosen plugins to file for reproducibility");
		
		if (writeTop) {
			writeBinaryValueFile(pluginAnalysisInfoBin + "top-cmcombo-for-methods.bin", dpmTop);
		}
		
		if (writeRandom) {
			writeBinaryValueFile(pluginAnalysisInfoBin + "random-cmcombo-for-methods.bin", dpmRandom);
		}
	}
	 			
	return clusterMultiplyDefinedMethods(toSet(dpmTop)+toSet(dpmRandom),dpmRestricted);
}

void writeMethodClusteringResults(map[tuple[str,str],set[set[str]]] res) {
	writeBinaryValueFile(pluginAnalysisInfoBin + "method-clustering.bin", res);
}

map[tuple[str,str],set[set[str]]] readMethodClusteringResults() {
	return readBinaryValueFile(#map[tuple[str,str],set[set[str]]], pluginAnalysisInfoBin + "method-clustering.bin"); 
}

map[str,set[set[str]]] runClassClustering() {
	pm = pluginMethods();
	map[str,set[str]] dpc = definingPluginsForClasses(pm);
	set[str] mdc = multiplyDefinedClasses(dpc);
	list[str] dpcTop = []; list[str] dpcRandom = [];
	
	// Keep only those classes that are multiply defined
	map[str,set[str]] dpcRestricted = domainR(dpc,mdc);
	// Then, sort them from most defs to fewest (but still > 1)
	list[str] dpcSorted = reverse(sort([ cni | cni <- dpcRestricted ], bool (str i1, str i2) { return dpcRestricted[i1] < dpcRestricted[i2]; }));
	
	bool writeTop = false;
	bool writeRandom = false;
	
	// Assuming this wasn't passed in, pick the classes defined in the most plugins
	if (isEmpty(dpcTop)) {
		writeTop = true;
		dpcTop = head(dpcSorted,100); // NOTE: We know there are more than 100, else we would need to check
	}
	
	// Assuming this wasn't passed in, pick 100 classes that are not already in the top 100
	if (isEmpty(dpcRandom)) {
		writeRandom = true;
		// We also know we have more than 200 choices, or we would need to check here as well...
		for (i <- [0..100]) {
			randomChoice = arbInt(size(dpcSorted));
			while (randomChoice < size(dpcTop)) randomChoice = arbInt(size(dpcSorted));
			while (dpcSorted[randomChoice] in dpcRandom) randomChoice = arbInt(size(dpcSorted));
			dpcRandom = dpcRandom + dpcSorted[randomChoice];
		}
	}

	if (writeTop || writeRandom) {		
		println("Writing chosen plugins to file for reproducibility");
		
		if (writeTop) {
			writeBinaryValueFile(pluginAnalysisInfoBin + "top-c-for-classes.bin", dpcTop);
		}
		
		if (writeRandom) {
			writeBinaryValueFile(pluginAnalysisInfoBin + "random-c-for-classes.bin", dpcRandom);
		}
	}
	 			
	return clusterMultiplyDefinedClasses(toSet(dpcTop)+toSet(dpcRandom),dpcRestricted);
}

void writeClassClusteringResults(map[str,set[set[str]]] res) {
	writeBinaryValueFile(pluginAnalysisInfoBin + "class-clustering.bin", res);
}

map[str,set[set[str]]] readClassClusteringResults() {
	return readBinaryValueFile(#map[str,set[set[str]]], pluginAnalysisInfoBin + "class-clustering.bin"); 
}

void extractSummariesForWordPress() {
	vs = getSortedVersions("WordPress");
	vs121 = vs[indexOf(vs,"1.2.1")..];
	for (v <- vs121) {
		pt = loadBinary("WordPress",v);
		s = summary(
			noInfo(), 
			definedFunctions(pt),
			definedClasses(pt), 
			definedMethods(pt), 
			definedFilters(pt), 
			definedActions(pt), 
			definedConstants(pt), 
			definedClassConstants(pt), 
			definedShortcodes(pt), 
			definedOptions(pt), 
			definedPostMetaKeys(pt), 
			definedUserMetaKeys(pt), 
			definedCommentMetaKeys(pt), 
			findSimpleActionHooksWithLocs(pt) + findDerivedActionHooksWithLocs(pt), 
			findSimpleFilterHooksWithLocs(pt) + findDerivedFilterHooksWithLocs(pt));
			writeBinaryValueFile(wpAsPluginBin + "wordpress-<v>-summary.bin", s);		
	}
}

@doc{Load the summary for the given plugin}
PluginSummary loadWordpressPluginSummary(str version) {
	return readBinaryValueFile(#PluginSummary, wpAsPluginBin + "wordpress-<version>-summary.bin");
}

bool wordpressPluginSummaryExists(str version) {
	return exists(wpAsPluginBin + "wordpress-<version>-summary.bin");
}
 
void findCollisionsWithWordPress() {
	vs = getSortedVersions("WordPress");
	vs40 = vs[indexOf(vs,"4.0")..];

	pf = pluginFunctions();
	pm = pluginMethods();
	pc = pluginConstants();
	pcc = pluginClassConstants();
	ps = pluginShortcodes();
	po = pluginOptions();
	ppm = pluginPostMetaKeys();
	pum = pluginUserMetaKeys();
	pcm = pluginCommentMetaKeys();

	dpf = definingPluginsForFunctions(pf);
	dpc = definingPluginsForClasses(pm);
	dpm = definingPluginsForMethods(pm);
	dpconst = definingPluginsForConstants(pc);
	dpcconst = definingPluginsForClassConstants(pcc);
	dps = definingPluginsForShortcodes(ps);
	dpo = definingPluginsForOptions(po);
	dppm = definingPluginsForMetaKeys(ppm);	
	dpum = definingPluginsForMetaKeys(pum);	
	dpcm = definingPluginsForMetaKeys(pcm);	
	
	// Function collisions
	for (v <- vs40) {
		wps = readBinaryValueFile(#PluginSummary, wpAsPluginBin + "wordpress-<v>-summary.bin");
		
		wpf = { f | < f, _ > <- wps.functions };
		wpm = { < c, m > | < c, m, _ > <- wps.methods };
		wpc = wpm<0>;
		wpconst = { c | < c, _ > <- wps.consts };
		wpcconst = { < c, x > | < c, x, _ > <- wps.classConsts };
		wpshort = { s | < s:name(name(si)), _ > <- wps.shortcodes };
		wpo = { s | < s:name(name(si)), _ > <- wps.options };
		wppm = { s | < s:name(name(si)), _ > <- wps.postMetaKeys };
		wpum = { s | < s:name(name(si)), _ > <- wps.userMetaKeys };
		wpcm = { s | < s:name(name(si)), _ > <- wps.commentMetaKeys };
		
		conflictFunctions = domainR(dpf,wpf);
		conflictMethods = domainR(dpm,wpm);
		conflictClasses = domainR(dpc,wpc);
		conflictConsts = domainR(dpconst, wpconst);
		conflictClassConsts = domainR(dpcconst, wpcconst);
		conflictShortcodes = domainR(dps, wpshort);
		conflictOptions = domainR(dpo, wpo);
		conflictPostMeta = domainR(dppm, wppm);
		conflictUserMeta = domainR(dpum, wpum);
		conflictCommentMeta = domainR(dpcm, wpcm);

		println("START <v>");
		println("<v>: Found <size(conflictFunctions)> function conflicts with <size({p|k<-conflictFunctions,p<-conflictFunctions[k]})> plugins");
		println("<v>: Found <size(conflictMethods)> method conflicts with <size({p|k<-conflictMethods,p<-conflictMethods[k]})> plugins");
		println("<v>: Found <size(conflictClasses)> class conflicts with <size({p|k<-conflictClasses,p<-conflictClasses[k]})> plugins");
		println("<v>: Found <size(conflictConsts)> const conflicts with <size({p|k<-conflictConsts,p<-conflictConsts[k]})> plugins");
		println("<v>: Found <size(conflictClassConsts)> class const conflicts with <size({p|k<-conflictClassConsts,p<-conflictClassConsts[k]})> plugins");
		println("<v>: Found <size(conflictShortcodes)> shortcode conflicts with <size({p|k<-conflictShortcodes,p<-conflictShortcodes[k]})> plugins");
		println("<v>: Found <size(conflictOptions)> option conflicts with <size({p|k<-conflictOptions,p<-conflictOptions[k]})> plugins");
		println("<v>: Found <size(conflictPostMeta)> post meta conflicts with <size({p|k<-conflictPostMeta,p<-conflictPostMeta[k]})> plugins");
		println("<v>: Found <size(conflictUserMeta)> user meta conflicts with <size({p|k<-conflictUserMeta,p<-conflictUserMeta[k]})> plugins");
		println("<v>: Found <size(conflictCommentMeta)> comment meta conflicts with <size({p|k<-conflictCommentMeta,p<-conflictCommentMeta[k]})> plugins");
		println("END <v>"); println("");
	} 
}

tuple[datetime s, datetime e] timeNameConflictDetection() {
	dt1 = now();
	computeClassInfo(pluginMethods());
	computeMethodInfo(pluginMethods());
	computeFunctionInfo(pluginFunctions());
	computeConstantInfo(pluginConstants());
	computeClassConstantInfo(pluginClassConstants());
	dt2 = now();
	return < dt1, dt2 >;
}

tuple[datetime s, datetime e] timeKeyConflictDetection() {
	dt1 = now();
	computeShortcodeConflictInfo(pluginShortcodes());
	computeOptionConflictInfo(pluginOptions());
	computeMetaKeyConflictInfo(pluginPostMetaKeys());
	computeMetaKeyConflictInfo(pluginUserMetaKeys());
	computeMetaKeyConflictInfo(pluginCommentMetaKeys());
	dt2 = now();
	return < dt1, dt2 >;
}

@doc{The conflict report, containing conflicts with a given plugin}
data Conflicts = conflicts(PluginInfo pInfo, map[str,set[str]] functions, map[str,set[str]] classes, map[tuple[str,str],set[str]] methods, map[str,set[str]] filters, map[str,set[str]] actions, map[str,set[str]] consts, map[tuple[str,str],set[str]] classConsts, map[str,set[str]] shortcodes, map[str,set[str]] options, map[str,set[str]] postMetaKeys, map[str,set[str]] userMetaKeys, map[str,set[str]] commentMetaKeys);

@doc{Find conflicts with the set of plugins in plugins.}
Conflicts findConflicts(System sys, set[str] plugins) {
	return findConflicts(extractPluginSummary(sys), plugins);
}

@doc{Find conflicts with the set of plugins in plugins.}
Conflicts findConflicts(PluginSummary sysSummary, set[str] plugins) {
	// TODO: For now, we are checking against every plugin, we need to filter this to allow
	// for checks against user-defined subsets.
	
	// Get back entities defined in the plugins
	pf = pluginFunctions();
	pm = pluginMethods();
	pc = pluginConstants();
	pcc = pluginClassConstants();
	ps = pluginShortcodes();
	po = pluginOptions();
	ppm = pluginPostMetaKeys();
	pum = pluginUserMetaKeys();
	pcm = pluginCommentMetaKeys();

	// Put these info a form where we can easily map from entities to plugins that define them
	dpf = definingPluginsForFunctions(pf);
	dpc = definingPluginsForClasses(pm);
	dpm = definingPluginsForMethods(pm);
	dpconst = definingPluginsForConstants(pc);
	dpcconst = definingPluginsForClassConstants(pcc);
	dps = definingPluginsForShortcodes(ps);
	dpo = definingPluginsForOptions(po);
	dppm = definingPluginsForMetaKeys(ppm);	
	dpum = definingPluginsForMetaKeys(pum);	
	dpcm = definingPluginsForMetaKeys(pcm);	
	
	// Get back just the names of entities for the current plugin
	wpf = { f | < f, _ > <- sysSummary.functions };
	wpm = { < c, m > | < c, m, _ > <- sysSummary.methods };
	wpc = wpm<0>;
	wpconst = { c | < c, _ > <- sysSummary.consts };
	wpcconst = { < c, x > | < c, x, _ > <- sysSummary.classConsts };
	wpshort = { s | < s:name(name(si)), _ > <- sysSummary.shortcodes };
	wpo = { s | < s:name(name(si)), _ > <- sysSummary.options };
	wppm = { s | < s:name(name(si)), _ > <- sysSummary.postMetaKeys };
	wpum = { s | < s:name(name(si)), _ > <- sysSummary.userMetaKeys };
	wpcm = { s | < s:name(name(si)), _ > <- sysSummary.commentMetaKeys };
	
	// Restrict the domains of each entity map/relation to just include conflicting entities
	conflictFunctions = domainR(dpf,wpf);
	conflictMethods = domainR(dpm,wpm);
	conflictClasses = domainR(dpc,wpc);
	conflictConsts = domainR(dpconst, wpconst);
	conflictClassConsts = domainR(dpcconst, wpcconst);
	conflictShortcodes = domainR(dps, wpshort);
	conflictOptions = domainR(dpo, wpo);
	conflictPostMeta = domainR(dppm, wppm);
	conflictUserMeta = domainR(dpum, wpum);
	conflictCommentMeta = domainR(dpcm, wpcm);

	println("CONFLICT REPORT");
	println("Found <size(conflictFunctions)> function conflicts with <size({p|k<-conflictFunctions,p<-conflictFunctions[k]})> plugins");
	println("Found <size(conflictMethods)> method conflicts with <size({p|k<-conflictMethods,p<-conflictMethods[k]})> plugins");
	println("Found <size(conflictClasses)> class conflicts with <size({p|k<-conflictClasses,p<-conflictClasses[k]})> plugins");
	println("Found <size(conflictConsts)> const conflicts with <size({p|k<-conflictConsts,p<-conflictConsts[k]})> plugins");
	println("Found <size(conflictClassConsts)> class const conflicts with <size({p|k<-conflictClassConsts,p<-conflictClassConsts[k]})> plugins");
	println("Found <size(conflictShortcodes)> shortcode conflicts with <size({p|k<-conflictShortcodes,p<-conflictShortcodes[k]})> plugins");
	println("Found <size(conflictOptions)> option conflicts with <size({p|k<-conflictOptions,p<-conflictOptions[k]})> plugins");
	println("Found <size(conflictPostMeta)> post meta conflicts with <size({p|k<-conflictPostMeta,p<-conflictPostMeta[k]})> plugins");
	println("Found <size(conflictUserMeta)> user meta conflicts with <size({p|k<-conflictUserMeta,p<-conflictUserMeta[k]})> plugins");
	println("Found <size(conflictCommentMeta)> comment meta conflicts with <size({p|k<-conflictCommentMeta,p<-conflictCommentMeta[k]})> plugins");
	
	// Return the summary of conflicts
	return conflicts(conflictFunctions, conflictClasses, conflictMethods, conflictConsts, conflictClassConsts, conflictShortcodes, conflictOptions, conflictPostMeta, conflictUserMeta, conflictCommentMeta);
}

public data NamePart = literalPart(str s) | exprPart(Expr e);
public alias NameModel = list[NamePart];

public Expr replaceClassConsts(Expr e, loc el, PluginSummary psum) {
	containerClasses = { cname | < cname, at > <- psum.classes, insideLoc(el,at) };
	if (size(containerClasses) == 1) {
		cname = getOneFrom(containerClasses);
		possibleClassConsts = { < xname,  d > | < cname, xname, at, d > <- psum.classConsts };
		e = bottom-up visit(e) {
			case fcc:fetchClassConst(name(name("self")),cn) : {
				possibleMatches = possibleClassConsts[cn];
				if (size(possibleMatches) == 1) {
					insert(getOneFrom(possibleMatches));
				}
			}
		}
	}
	return e;
}

public NameModel nameModel(Expr e, PluginSummary psum) {
	loc el = e@at;
	solve(e) {
		e = simulateCall(algebraicSimplification(replaceClassConsts(e,el,psum)));
	}

	NameModel nameModelInternal(Expr e) {
		if (binaryOperation(l,r,concat()) := e) {
			return [ *nameModelInternal(l), *nameModelInternal(r) ];
		} else if (scalar(encapsed(elist)) := e) {
			return [ *nameModelInternal(eli) | eli <- elist ];
		} else if (scalar(string(s)) := e) {
			return [ literalPart(s) ];
		} else {
			return [ exprPart(e) ];
		}
	}
	
	return nameModelInternal(e);
}

public NameModel nameModel(name(name(str s)), PluginSummary psum) = [ literalPart(s) ];
public NameModel nameModel(expr(Expr e), PluginSummary psum) = nameModel(e, psum);

public str regexpForNameModel(NameModel nm) {
	list[str] parts = [ ];
	for (nmi <- nm) {
		if (literalPart(s) := nmi) {
			parts = parts + s;
		} else {
			parts = parts + ".*";
		}
	}
	return intercalate("",parts);
}

public int specificity(literalPart(str s)) = size(s);
public int specificity(exprPart(Expr e)) = 0;

public int specificity(NameModel nm, str toMatch) {
	allAts = findAll(toMatch,"@");
	if ([literalPart(str s)] := nm && size(allAts) == 0) {
		return 99; // This is very specific, neither part is a regexp match
	}
	return (0 | it + specificity(i) | i <- nm );
}

public str stringForMatch(Expr e, PluginSummary psum) {
	loc el = e@at;
	solve(e) {
		e = simulateCall(algebraicSimplification(replaceClassConsts(e,el,psum)));
	}

	if (binaryOperation(l,r,concat()) := e) {
		return stringForMatch(l,psum) + stringForMatch(r,psum);
	} else if (scalar(encapsed(el)) := e) {
		return intercalate("", [stringForMatch(eli,psum) | eli <- el]);
	} else if (scalar(string(s)) := e) {
		return s;
	} else {
		return "@"; // "@" cannot be a name, so this won't match with anything else
	}
}

public str stringForMatch(expr(Expr e), PluginSummary psum) = stringForMatch(e,psum);
public str stringForMatch(name(name(str s)), PluginSummary psum) = s;

alias HookUses = rel[loc usedAt, NameOrExpr use, loc defAt, NameOrExpr def, Expr reg, int specificity];
alias HookUsesWithPlugin = rel[str pluginName, loc usedAt, NameOrExpr use, loc defAt, NameOrExpr def, Expr reg, int specificity];

public HookUses resolveHooks(str pluginName) {
	pt = loadPluginBinary(pluginName);
	psum = loadPluginSummary(pluginName);
	
	HookUses res = { };
	
	if (psum.pInfo is pluginInfo && just(maxVersion) := psum.pInfo.testedUpTo) {
		if (binaryExists("WordPress", maxVersion)) {
			//wp = loadBinary("WordPress", maxVersion);
			wpsum = loadWordpressPluginSummary(maxVersion);
			
			println("Resolving against version <maxVersion> of WordPress");
			
			// Build name models for each of the hooks defined in WordPress
			rel[NameOrExpr hookName, loc at, NameModel model] wpActionModels = { < hn, at, nameModel(hn,wpsum) > | < hn, at > <- wpsum.providedActionHooks };
			rel[NameOrExpr hookName, loc at, NameModel model] wpFilterModels = { < hn, at, nameModel(hn,wpsum) > | < hn, at > <- wpsum.providedFilterHooks };
	
			// Build name models for each of the hooks defined in the plugin itself
			rel[NameOrExpr hookName, loc at, NameModel model] actionModels = { < hn, at, nameModel(hn,psum) > | < hn, at > <- psum.providedActionHooks };
			rel[NameOrExpr hookName, loc at, NameModel model] filterModels = { < hn, at, nameModel(hn,psum) > | < hn, at > <- psum.providedFilterHooks };
	
			// Create subsets of the above where we have exact name matches, that way we only fall back on regular
			// expression matching in cases where we define the def or use dynamically (note, here we are making
			// an ASSUMPTION that, in these cases, this is the intended semantics).
			rel[str hookName, loc at] wpActionsJustNames = { < s, at > | < _, at, [ literalPart(str s) ] > <- wpActionModels };
			rel[str hookName, loc at] wpFiltersJustNames = { < s, at > | < _, at, [ literalPart(str s) ] > <- wpFilterModels };
			rel[str hookName, loc at] actionsJustNames = { < s, at > | < _, at, [ literalPart(str s) ] > <- actionModels };
			rel[str hookName, loc at] filtersJustNames = { < s, at > | < _, at, [ literalPart(str s) ] > <- filterModels };
			
			println("Computed <size(wpActionModels)> for wordpress actions");
			println("Computed <size(wpFilterModels)> for wordpress filters");
			println("Computed <size(actionModels)> for plugin actions");
			println("Computed <size(filterModels)> for plugin filters");
			
			// Build a regexp for each name model
			map[NameModel model, str regexp] regexps = ( nm : regexpForNameModel(nm) | nm <- (wpActionModels<2> + wpFilterModels<2> + actionModels<2> + filterModels<2>) );
			println("Computed <size(regexps)> name model to regexp mappings");
			
			println("Attempting to resolve <size(psum.filters)> filter uses and <size(psum.actions)> action uses");
			
			// Now, using these models, compute which of the actual uses match these models
			HookUses localFilterMatches = { };
			for ( < hnUse, useloc, _, reg > <- psum.filters ) {
				//bool doCheck = true;
				//if (name(name(str s)) := hnUse) {
				//	for ( < s, defloc > <- filtersJustNames ) {
				//		localFilterMatches = localFilterMatches + < useloc, hnUse, defloc, name(name(s)), reg, 1000 >;
				//		doCheck = false;
				//	}
				//}
				//if (doCheck) {
					useString = stringForMatch(hnUse,psum);
					for ( < hnDef, defloc, nm > <- filterModels) {
						try {
							if (rexpMatch(useString, regexps[nm])) {
								localFilterMatches = localFilterMatches + < useloc, hnUse, defloc, hnDef, reg, specificity(nm,useString) >;
							}
						} catch v : {
							println("Bad regexp <regexps[nm]> caused by bug in source, skipping");
						}
					}
				//}
			}
			println("Local filter matches: <size(localFilterMatches)>");
	
			HookUses localActionMatches = { };
			for ( < hnUse, useloc, _, reg > <- psum.actions ) {
				//bool doCheck = true;
				//if (name(name(str s)) := hnUse) {
				//	for ( < s, defloc > <- actionsJustNames ) {
				//		localActionMatches = localActionMatches + < useloc, hnUse, defloc, name(name(s)), reg, 1000 >;
				//		doCheck = false;
				//	}
				//}
				//if (doCheck) {
					useString = stringForMatch(hnUse,psum);
					for ( < hnDef, defloc, nm > <- actionModels) {
						try {
							if (rexpMatch(useString, regexps[nm])) {
								localActionMatches = localActionMatches + < useloc, hnUse, defloc, hnDef, reg, specificity(nm,useString) >;
							}
						} catch v : {
							println("Bad regexp <regexps[nm]> caused by bug in source, skipping");
						}
					}
				//}	
			}
			println("Local action matches: <size(localActionMatches)>");
	
			HookUses wpFilterMatches = { };
			for ( < hnUse, useloc, _, reg > <- psum.filters ) {
				//bool doCheck = true;
				//if (name(name(str s)) := hnUse) {
				//	for ( < s, defloc > <- wpFiltersJustNames ) {
				//		wpFilterMatches = wpFilterMatches + < useloc, hnUse, defloc, name(name(s)), reg, 1000 >;
				//		doCheck = false;
				//	}
				//}
				//if (doCheck) {
					useString = stringForMatch(hnUse,psum);
					for ( < hnDef, defloc, nm > <- wpFilterModels) {
						//println("Going to check against <regexps[nm]>");
						try {
							if (rexpMatch(useString, regexps[nm])) {
								wpFilterMatches = wpFilterMatches + < useloc, hnUse, defloc, hnDef, reg, specificity(nm,useString) >;
							}
						} catch v : {
							println("Bad regexp <regexps[nm]> caused by bug in source, skipping");
						}
					}	
				//}
			}
			println("WordPress filter matches: <size(wpFilterMatches)>");
	
			HookUses wpActionMatches = { };
			for ( < hnUse, useloc, _, reg > <- psum.actions ) {
				//bool doCheck = true;
				//if (name(name(str s)) := hnUse) {
				//	for ( < s, defloc > <- wpActionsJustNames ) {
				//		wpActionMatches = wpActionMatches + < useloc, hnUse, defloc, name(name(s)), reg, 1000 >;
				//		doCheck = false;
				//	}
				//}
				//if (doCheck) {
					useString = stringForMatch(hnUse,psum);
					for ( < hnDef, defloc, nm > <- wpActionModels) {
						//println("Going to check against <regexps[nm]>");
						try {
							if (rexpMatch(useString, regexps[nm])) {
								wpActionMatches = wpActionMatches + < useloc, hnUse, defloc, hnDef, reg, specificity(nm,useString) >;
							}
						} catch v : {
							println("Bad regexp <regexps[nm]> caused by bug in source, skipping");
						}
					}	
				//}
			}
			println("WordPress action matches: <size(wpActionMatches)>");
			
			res = localFilterMatches + localActionMatches + wpFilterMatches + wpActionMatches;
			
			unresFilters = { < hnUse, useloc > | < hnUse, useloc, _, _ > <- psum.filters, < useloc, hnUse > notin res<0,1> };
			unresActions = { < hnUse, useloc > | < hnUse, useloc, _, _ > <- psum.actions, < useloc, hnUse > notin res<0,1> };
			println("Unresolved: <size(unresFilters)> filters and <size(unresActions)> actions");
		} else {
			println("No binary for WordPress version <maxVersion>");
		}
	} else {
		println("Could not resolve hooks for <pluginName>, max WP version unknown");
	}
	
	return res;
}

@doc{This gets a distribution of uses, but does not tie this to a specific use. It also
     differentiates uses of the same hook across different versions.}
public map[int,int] occurrenceDistribution(HookUses uses) {
	map[int,int] res = ( );
	for ( < ul, u > <- uses<0,1>) {
		ucount = size(uses[ul,u]);
		if (ucount in res) {
			res[ucount] = res[ucount] + 1;
		} else {
			res[ucount] = 1;
		}
	} 
	return res;
}

@doc{Extract plugin summaries for all pre-parsed plugin binaries}
public void resolveHooks(bool overwrite = true) {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file))) {
    	if ( (overwrite && exists(infoBin+"<l.file>-hook-uses.bin")) || !exists(infoBin+"<l.file>-hook-uses.bin")) { 
	        println("Resolving hooks for plugin: <l.file>");
	        res = resolveHooks(l.file);
	        writeBinaryValueFile(infoBin+"<l.file>-hook-uses.bin", res);
		} else {
			println("Already resolved hooks for plugin: <l.file>");
		}
    }
}

@doc{Gives back a master relation of all uses across all plugins}
public HookUsesWithPlugin combineUses() {
	HookUsesWithPlugin res = { };
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file)), exists(infoBin+"<l.file>-hook-uses.bin")) {
		HookUses hu = readBinaryValueFile(#HookUses, infoBin+"<l.file>-hook-uses.bin");
		res = res + { < l.file, uat, u, dat, d, r, s > | < uat, u, dat, d, r, s > <- hu, s > 3 }; 
	}
	return res;
}

alias HookUsesForCounts = rel[str pluginName, loc usedAt, loc defAt, NameOrExpr def, int specificity];

@doc{Gives back a master relation of all uses across all plugins}
public HookUsesForCounts combineUsesForCounts() {
	HookUsesForCounts res = { };
	int processed = 0;
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file)), exists(infoBin+"<l.file>-hook-uses.bin")) {
		HookUses hu = readBinaryValueFile(#HookUses, infoBin+"<l.file>-hook-uses.bin");
		res = res + { < l.file, uat, dat, d, s > | < uat, u, dat, d, r, s > <- hu }; 
    	processed += 1;
    	if ((processed % 100) == 0) println("Processed <processed>...");
	}
	return res;
}

public list[str] problemPlugins() {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    return [ l.file | l <- pluginDirs, exists(getPluginBinLoc(l.file)), !exists(infoBin+"<l.file>-hook-uses.bin")]; 
}

// What diagrams do we want? What stats?
// For each hook defined by WordPress, how many plugins use it?
// For each hook defined by WordPress, how many times is it used?
// For each plugin, how many hooks does it define locally?
// For each plugin, how many of these local hooks are used?
// For each plugin, how many hooks (actions/filters) does it use?
// For each use, how many hooks does this resolve to on average?

@doc{This acts as a check -- it looks over all the plugins and gives us the smallest version tested up to. We intended
     to pull only plugins that were tested up to 4.0 or higher.}
public str minVersionSupported() {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    v = "4.3";
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file))) {
		psum = loadPluginSummary(l.file);
		if (psum.pInfo is pluginInfo && just(maxVersion) := psum.pInfo.testedUpTo) {
			if (maxVersion[-1] == ".") {
				maxVersion = maxVersion + "0";
				pieces = split(".", maxVersion);
				try {
					for (p <- pieces) toInt(p);
				} catch _ : {
					continue;
				}
			}
			if (compareVersion(maxVersion,v)) {
				v = maxVersion;
			}
		}
	}
	return v;
}

@doc{Normalize the WP version that is recorded in the plugin summary. For instance, sometimes 4.0 is given as 4., 4, or 4.0.0.}
public void normalizeWPVersion() {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file))) {
		psum = loadPluginSummary(l.file);
		if (psum.pInfo is pluginInfo && just(maxVersion) := psum.pInfo.testedUpTo) {		
			if (maxVersion in { "4.", "4", "4.0.0" }) maxVersion = "4.0";
			else if (maxVersion in {"4.1.","4.1.0"}) maxVersion = "4.1";
			else if (maxVersion in {"4.2.","4.2.0"}) maxVersion = "4.2";
			else if (maxVersion in {"4.3.","4.3.0"}) maxVersion = "4.3";
			
			psum.pInfo.testedUpTo = just(maxVersion);
			writeBinaryValueFile(pluginInfoBin + "<l.file>-summary.bin", psum);
		}
	}		
}

@doc{For each plugin, return the WP version that it has been tested up to. Note that we only do simple parsing of the version number,
     in some cases people put additional information in this slot but we don't attempt to decipher it.}
public rel[str,str] versionsUsed() {
	rel[str,str] res = { };
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file))) {
		psum = loadPluginSummary(l.file);
		if (psum.pInfo is pluginInfo && just(maxVersion) := psum.pInfo.testedUpTo) {		
			res = res + < l.file, maxVersion>;
		} else {
			res = res + < l.file, "unknown" >;
		}
	}
	return res;
}

@doc{Return a map from WP version to the number of plugins that have been tested up to this version}
public map[str,int] byVersion(set[str] versions = corpusVersions()) {
	// Return the version with the number of plugins that use it
	used = versionsUsed();
	validVersions = versions;
	map[str,int] counts = ( v : size(invert(used)[v]) | v <- used<1>, v in validVersions );
	return counts;
}

@doc{Return a relation from version numbers to both filter and action hooks}
public rel[str version, NameOrExpr hook] hooksByVersion(set[str] versions = corpusVersions()) {
	rel[str version, NameOrExpr hook] res = { };
	
	for (v <- versions) {
		wpsum = loadWordpressPluginSummary(v);
		res = res + { < v, h > | h <- (wpsum.providedFilterHooks<0> + wpsum.providedActionHooks<0>) };
	}
	
	return res;
}

@doc{Return a relation from version numbers to filter hooks}
public rel[str version, NameOrExpr hook] filtersByVersion(set[str] versions = corpusVersions()) {
	rel[str version, NameOrExpr hook] res = { };
	
	for (v <- versions) {
		wpsum = loadWordpressPluginSummary(v);
		res = res + { < v, h > | h <- (wpsum.providedFilterHooks<0>) };
	}
	
	return res;
}

@doc{Return a relation from version numbers to action hooks}
public rel[str version, NameOrExpr hook] actionsByVersion(set[str] versions = corpusVersions()) {
	rel[str version, NameOrExpr hook] res = { };
	
	for (v <- versions) {
		wpsum = loadWordpressPluginSummary(v);
		res = res + { < v, h > | h <- (wpsum.providedActionHooks<0>) };
	}
	
	return res;
}

@doc{This returns just those versions we are focusing on in this study}
set[str] corpusVersions() = { v | v <- getVersions("WordPress"), v == "4.0" || ( compareVersion("4.0",v) && compareVersion(v,"4.3.2") ) };

@doc{This returns a sorted list of just those versions we are focusing on in this study}
list[str] sortedVersions() = [ v | v <- getSortedVersions("WordPress"), v == "4.0" || ( compareVersion("4.0",v) && compareVersion(v,"4.3.2") ) ];

@doc{This returns all versions of WordPress that we have that include plugin support}
set[str] wpVersionsWithPlugins() = { v | v <- getVersions("WordPress"), v == "1.2.1" || ( compareVersion("1.2.1",v) && compareVersion(v,"4.3.2") ) };

@doc{This returns a sorted list of all versions of WordPress that we have that include plugin support}
list[str] sortedWPVersionsWithPlugins() = [ v | v <- getSortedVersions("WordPress"), v == "1.2.1" || ( compareVersion("1.2.1",v) && compareVersion(v,"4.3.2") ) ];

@doc{Given a relation from version numbers to hooks, return a map from version numbers to the number of hooks in that version}
map[str version, int count] summarizeByVersion(rel[str version, NameOrExpr hook] hbv) {
	return ( v : size(hbv[v]) | v <- hbv<0> );
}

@doc{Dump counts to a file so we can load them up in Excel or R and take a look at them}
void dumpCountsByVersion(rel[str version, NameOrExpr hook] hbv, rel[str version, NameOrExpr hook] fbv, rel[str version, NameOrExpr hook] abv, loc dumpTo) {
	dumpCountsByVersion(summarizeByVersion(hbv),summarizeByVersion(fbv),summarizeByVersion(abv),dumpTo);
}

@doc{Dump counts to a file so we can load them up in Excel or R and take a look at them}
void dumpCountsByVersion(map[str version, int count] hbv, map[str version, int count] fbv, map[str version, int count] abv, loc dumpTo) {
	list[str] lines = [ "<v>,<hbv[v]>,<fbv[v]>,<abv[v]>" | v <- sortedWPVersionsWithPlugins() ];
	writeFile(dumpTo,intercalate("\n",lines));
}

public map[str,int] pluginDownloads() {
	map[str,int] res = ( );
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file))) {
    	println("Getting stats for <l.file>");
    	try {
	    	hftext = readFile(|https://wordpress.org/plugins| + l.file);
			if(/UserDownloads:<c:\d+>/ := hftext) {
				res[l.file] = toInt(c);
				continue;
			}
		} catch _ : {
			;
		}
		res[l.file] = -1;
	}
	return res;
}

public void writePluginDownloadCounts(map[str,int] counts) {
	writeBinaryValueFile(pluginInfoBin + "download-counts.bin", counts);
}

map[str,int] readPluginDownloadCounts() {
	return readBinaryValueFile(#map[str,int], pluginInfoBin + "download-counts.bin");
}

private lrel[num,num] computeCoords(list[num] inputs) {
	return [ < idx+1, inputs[idx] > | idx <- index(inputs) ];
}

str computeTicks(list[str] vlist) {
	displayThese = [ idx+1 | idx <- index(vlist), ((idx+1)%10==1) || (idx==size(vlist)-1) ];
	return "xtick={<intercalate(",",displayThese)>}";
}

str computeTickLabels(list[str] vlist) {
	displayThese = [ vlist[idx] | idx <- index(vlist), ((idx+1)%10==1) || (idx==size(vlist)-1) ];
	return "xticklabels={<intercalate(",",displayThese)>}";
}

private str makeCoords(list[num] inputs, str mark="", str markExtra="", str legend="") {
	return "\\addplot<if(size(mark)>0){>[mark=<mark><if(size(markExtra)>0){>,<markExtra><}>]<}> coordinates {
		   '<intercalate(" ",[ "(<i>,<j>)" | < i,j > <- computeCoords(inputs)])>
		   '};<if(size(legend)>0){>
		   '\\addlegendentry{<legend>}<}>";
}

public str hooksChart(list[str] versions, map[str version, int count] fbv, map[str version, int count] abv, str title="Grown in WordPress Filter and Action Hooks, by Version", str label="fig:Hooks", str markExtra="mark phase=1,mark repeat=5") {
	list[str] coordinateBlocks = [ ];
	coordinateBlocks += makeCoords([ fbv[v] | v <- versions, v in fbv ], mark="o", markExtra=markExtra, legend="Filters");
	coordinateBlocks += makeCoords([ abv[v] | v <- versions, v in abv ], mark="x", markExtra=markExtra, legend="Actions");

	int maxcoord() {
		return max([ fbv[v] | v <- versions, v in fbv ] +
				   [ abv[v] | v <- versions, v in abv ]) + 10;
	}
		
	str res = "\\begin{figure*}
			  '\\centering
			  '\\begin{tikzpicture}
			  '\\begin{axis}[width=\\textwidth,height=.25\\textheight,xlabel=Version,ylabel=Count,xmin=1,ymin=0,xmax=<size(versions)>,ymax=<maxcoord()>,legend style={at={(0,1)},anchor=north west},x tick label style={rotate=90,anchor=east},<computeTicks(versions)>,<computeTickLabels(versions)>]
			  '<for (cb <- coordinateBlocks) {> <cb> <}>
			  '\\end{axis}
			  '\\end{tikzpicture}
			  '\\caption{<title>.\\label{<label>}} 
			  '\\end{figure*}
			  ";
	return res;	
}

public str makeHooksChart() {
	fbv = filtersByVersion(versions=wpVersionsWithPlugins());
	abv = actionsByVersion(versions=wpVersionsWithPlugins());
	versions = sortedWPVersionsWithPlugins();
	
	return hooksChart(versions,summarizeByVersion(fbv),summarizeByVersion(abv));
}

public void sampleQueries() {

	huFunctionCalls = { h | h:call(name(name(_)),[actualParameter(scalar(string(_)),_),actualParameter(scalar(string(_)),_),_*]) <- huCalls };
	huMethodCalls = { h | h:call(name(name(_)),[actualParameter(scalar(string(_)),_),actualParameter(array([arrayElement(_,_,_),arrayElement(_,_,_)]),_),_*]) <- huCalls };
	huMethodCalls2 = { h | h:call(name(name(_)),[actualParameter(scalar(string(_)),_),actualParameter(array([arrayElement(_,_,_),arrayElement(_,scalar(string(_)),_)]),_),_*]) <- huCalls };
	huMethodCalls3 = { h | h:call(name(name(_)),[actualParameter(scalar(string(_)),_),actualParameter(array([arrayElement(_,var(name(name("this"))),_),arrayElement(_,scalar(string(_)),_)]),_),_*]) <- huCalls };
	huMethodCalls4 = { h | h:call(name(name(_)),[actualParameter(scalar(string(_)),_),actualParameter(array([arrayElement(_,scalar(string(_)),_),arrayElement(_,scalar(string(_)),_)]),_),_*]) <- huCalls };
	huOther = huCalls - (huFunctionCalls + huMethodCalls);
	huDynFunctionCalls = { h | h:call(name(name(_)),[actualParameter(e,_),actualParameter(scalar(string(_)),_),_*]) <- huCalls, scalar(string(_)) !:= e };
}

// alias HookUses = rel[loc usedAt, NameOrExpr use, loc defAt, NameOrExpr def, Expr reg, int specificity];

data HookUseTarget 
	= functionTarget(str fname, loc at)
	| unknownFunctionTarget(str fname) 
	| methodTarget(str cname, str mname, loc at)
	| potentialMethodTarget(str cname, str mname, loc at) 
	| staticMethodTarget(str cname, str mname, loc at)
	| unknownMethodTarget(str mname) 
	| unknownTarget()
	| unresolvedTarget()
	;

alias HookUsesResolved = rel[loc usedAt, NameOrExpr use, loc defAt, NameOrExpr def, Expr reg, int specificity, HookUseTarget target];

public bool insideLoc(loc at, loc container) {
	return 
		container.file == at.file &&
		container.offset <= at.offset &&
		(container.offset + container.length) >= (at.offset + at.length);
}

public HookUsesResolved resolveCallbacks(str pluginName) {
	HookUsesResolved res = { };

	psum = loadPluginSummary(pluginName);
	wpsum = (psum.pInfo is pluginInfo && just(maxVersion) := psum.pInfo.testedUpTo && wordpressPluginSummaryExists(maxVersion)) ? loadWordpressPluginSummary(maxVersion) : loadWordpressPluginSummary("4.3.1"); 

	hu = readBinaryValueFile(#HookUses, infoBin+"<pluginName>-hook-uses.bin");
	for (< loc usedAt, NameOrExpr use, loc defAt, NameOrExpr def, Expr reg, int specificity > <- hu) {
		if (h:call(name(name(_)),[actualParameter(_,_),actualParameter(scalar(string(fn)),_),_*]) := reg) {
			// These are the cases for where the call target is given as a string.
			if (fn in psum.functions<0>) {
				// In this case, the target is an actual function provided by the plugin
				res = res + { < usedAt, use, defAt, def, reg, specificity, functionTarget(fn,at) > | < fn,at> <- psum.functions };
			} else if (fn in wpsum.functions<0>) {
				// In this case, the target in an actual function provided by WordPress
				res = res + { < usedAt, use, defAt, def, reg, specificity, functionTarget(fn,at) > | < fn,at> <- wpsum.functions };			
			} else if (contains(fn,"::")) {
				// Here the target is a static method on a class, given as ClassName::MethodName
				pieces = split(fn,"::");
				methodName = pieces[-1];
				classPieces = split(intercalate("::",pieces[..-1]),"\\\\");
				className = classPieces[-1];

				possibleMethods = { < className, methodName, at > | < className, methodName, at, _ > <- (psum.methods + wpsum.methods) };

				if (size(possibleMethods) > 0) {
					res = res + { < usedAt, use, defAt, def, reg, specificity, staticMethodTarget(cname, mname, at) > | < className, methodName, at > <- possibleMethods };
				} else {
					res = res + < usedAt, use, defAt, def, reg, specificity, unknownMethodTarget(methodName) >;
				}
			} else if (contains(fn,"\\\\")) {
				// Here the target is a function given with the namespace (which technically isn't supported by WordPress)
				functionPieces = split(fn,"\\\\");
				functionName = functionPieces[-1];
				if (functionName in psum.functions<0>) {
					res = res + { < usedAt, use, defAt, def, reg, specificity, functionTarget(functionName,at) > | < functionName,at> <- psum.functions };
				} else if (functionName in wpsum.functions<0>) {
					res = res + { < usedAt, use, defAt, def, reg, specificity, functionTarget(functionName,at) > | < functionName,at> <- wpsum.functions };
				}				
			} else {
				// If we don't identify the function based on those categories, this is an unknown function
				res = res + < usedAt, use, defAt, def, reg, specificity, unknownFunctionTarget(fn) >;
			}
		} else if (h:call(name(name(_)),[actualParameter(scalar(string(_)),_),actualParameter(array([arrayElement(_,var(name(name("this"))),_),arrayElement(_,scalar(string(mn)),_)]),_),_*]) := reg) {
			// This is a method call on $this
			containerClasses = { cname | < cname, at > <- psum.classes, insideLoc(defAt,at) };
			possibleMethods = { < cname, mn, at > | cname <- containerClasses, < cname, mn, at, _ > <- (psum.methods + wpsum.methods) };
			if (size(possibleMethods) > 0) {
				res = res + { < usedAt, use, defAt, def, reg, specificity, methodTarget(cname, mname, at) > | < cname, mname, at > <- possibleMethods };
			} else {
				res = res + < usedAt, use, defAt, def, reg, specificity, unknownMethodTarget(mn) >;
			}
		} else if (h:call(name(name(_)),[actualParameter(scalar(string(_)),_),actualParameter(array([arrayElement(_,Expr e,_),arrayElement(_,scalar(string(mn)),_)]),_),_*]) := reg) {
			// This is a method call on some expression, since we don't have types we do a probable match
			possibleMethods = { < cname, mn, at > | < cname, mn, at, _ > <- (psum.methods + wpsum.methods) };
			if (size(possibleMethods) > 0) {
				res = res + { < usedAt, use, defAt, def, reg, specificity, potentialMethodTarget(cname, mname, at) > | < cname, mname, at > <- possibleMethods };
			} else {
				res = res + < usedAt, use, defAt, def, reg, specificity, unknownMethodTarget(mn) >;
			}
		} else if (h:call(name(name(_)),[actualParameter(scalar(string(_)),_),actualParameter(array([arrayElement(_,scalar(string(cn)),_),arrayElement(_,scalar(string(mn)),_)]),_),_*]) := reg) {
			// This is a static method call, given instead as array elements, e.g., array("ClassName","MethodName")
			possibleMethods = { < cn, mn, at > | < cn, mn, at, _ > <- (psum.methods + wpsum.methods) };
			if (size(possibleMethods) > 0) {
				res = res + { < usedAt, use, defAt, def, reg, specificity, staticMethodTarget(cname, mname, at) > | < cname, mname, at > <- possibleMethods };
			} else {
				res = res + < usedAt, use, defAt, def, reg, specificity, unknownMethodTarget(mn) >;
			}
		} else {
			res = res + < usedAt, use, defAt, def, reg, specificity, unresolvedTarget() >;
		}
	}
	return res;
}

public HookUsesResolved resolveCallbacks() {
	HookUsesResolved res = { };
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file))) {
    	println("Resolving callbacks for <l.file>");
		res = res + resolveCallbacks(l.file);
	}
	return res;
}

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
	return ( l : normalizeComments(sys[l]) | l <- sys );
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

public void staticDynamicCountsInWP(str v) {
	wpsum = loadWordpressPluginSummary(v);
	staticFilters = [ e | < e, _ > <- wpsum.providedFilterHooks, name(name(_)) := e ];
	dynamicFilters = [ e | < e, _ > <- wpsum.providedFilterHooks, expr(_) := e ];
	staticActions = [ e | < e, _ > <- wpsum.providedActionHooks, name(name(_)) := e ];
	dynamicActions = [ e | < e, _ > <- wpsum.providedActionHooks, expr(_) := e ];
	
	println("WordPress <v> defines <size(staticFilters)> static filters");
	println("WordPress <v> defines <size(dynamicFilters)> dynamic filters");
	println("WordPress <v> defines <size(staticActions)> static actions");
	println("WordPress <v> defines <size(dynamicActions)> dynamic actions");
}

public void staticDynamicCountsInPlugins() {
	staticFilterCount = 0;
	dynamicFilterCount = 0;
	staticActionCount = 0;
	dynamicActionCount = 0;
	
	pluginCount = 0;
	
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin")) {
    	psum = loadPluginSummary(l.file);
    	pluginCount += 1;
    		
		staticFilterCount += size([ e | < e, _, _, _ > <- psum.filters, name(name(_)) := e ]);
		dynamicFilterCount += size([ e | < e, _, _, _ > <- psum.filters, expr(_) := e ]);
		staticActionCount += size([ e | < e, _, _, _ > <- psum.actions, name(name(_)) := e ]);
		dynamicActionCount += size([ e | < e, _, _, _ > <- psum.actions, expr(_) := e ]);
	}

	println("The corpus registers <staticFilterCount> static filter handlers across <pluginCount> plugins");
	println("The corpus registers <dynamicFilterCount> dynamic filter handlers across <pluginCount> plugins");
	println("The corpus registers <staticActionCount> static action handlers across <pluginCount> plugins");
	println("The corpus registers <dynamicActionCount> dynamic action handlers across <pluginCount> plugins");
}

alias HookUsesForDist = rel[str pluginName, NameOrExpr hookName, NameOrExpr handlerName, loc handlerLoc];

@doc{Get stats on how many hooks are used by plugins, in general}
public HookUsesForDist combineUsesForPluginDist(bool justWordpressHooks=true) {
	HookUsesForDist uses = { }; 
	int processed = 0;
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    
    set[str] wpfiles = {};
    if (justWordpressHooks) {
    	for (v <- sortedVersions()) {
    		wpfiles = wpfiles + { l.path | l <- loadBinary("WordPress",v) };
    	}
    }
    
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file)), exists(infoBin+"<l.file>-hook-uses.bin")) {
		HookUses hu = readBinaryValueFile(#HookUses, infoBin+"<l.file>-hook-uses.bin");
		if (!justWordpressHooks) {
			uses = uses + { < l.file, d, u, uat > | < uat, u, dat, d, r, s > <- hu, s > 1 };
		} else {
			uses = uses + { < l.file, d, u, uat > | < uat, u, dat, d, r, s > <- hu, s > 1, dat.path in wpfiles };
		}
    	processed += 1;
    	if ((processed % 100) == 0) println("Processed <processed>...");
	}
	return uses;
}

@doc{Reduce these stats down into a map of numbers for the distribution, this is number of hooks used by each plugin}
public map[int,int] computeDistForHookUses(HookUsesForDist hud) {
	perPluginCounts =  ( p : size(hud[p]<0>) | p <- hud<0> );
	
	map[int,int] res = ( );
	for (pn <- perPluginCounts) {
		if (perPluginCounts[pn] in res) {
			res[perPluginCounts[pn]] += 1;
		} else {
			res[perPluginCounts[pn]] = 1;
		}
	}
	
	return res;
}

// alias HookUsesForDist = rel[str pluginName, NameOrExpr hookName, NameOrExpr handlerName, loc handlerLoc];

@doc{Similar to the above, but gives the number of uses of each extension point}
public map[str,int] computeDistForMostUsedHooks(HookUsesForDist hud) {
	pluginsPerHook = { < pp(h), p > | < h, p > <- invert(hud<0,1>) };
	perHookCounts =  ( h : size(pluginsPerHook[h]) | h <- pluginsPerHook<0> );
	return perHookCounts;
}

public lrel[str,int] sortMostUsed(map[str,int] mostUsed) {
	return reverse(sort(toList(mostUsed), bool(tuple[str s1, int i1] t1, tuple[str s2, int i2] t2) { return t1.i1 < t2.i2; }));
}

public set[str] getUnused(map[str,int] mostUsed) {
	map[str,bool] allHooks = ( );
	// Get a set of all hooks from 4.0 on
	for (v <- sortedVersions(), v == "4.3.1") {
		wpsum = loadWordpressPluginSummary(v);
		allHooks = allHooks + 
			( pp(h) : true  | <h,_> <- wpsum.providedActionHooks, name(name(_)) := h ) + 
			( pp(h) : false | <h,_> <- wpsum.providedActionHooks, name(name(_)) !:= h ) + 
			( pp(h) : true  | <h,_> <- wpsum.providedFilterHooks, name(name(_)) := h ) +
			( pp(h) : false | <h,_> <- wpsum.providedFilterHooks, name(name(_)) !:= h );
	}
	
	println("Size before removal: <size(allHooks<0>)>");
	allHooks = domainX(allHooks,mostUsed<0>);
	println("Total unused: <size(allHooks<0>)>");
	println("Static unused: <size([h | h <- allHooks, allHooks[h]])>");
	println("Dynamic unused: <size([h | h <- allHooks, !allHooks[h]])>");
	
	return allHooks<0>;
}

public set[str] getUnusedOriginal(map[str,int] mostUsed) {
	set[str] allHooks = { };
	// Get a set of all hooks from 4.0 on
	for (v <- sortedVersions(), v == "4.3.1") {
		wpsum = loadWordpressPluginSummary(v);
		allHooks = allHooks + 
			{ pp(h) | <h,_> <- wpsum.providedActionHooks } + 
			{ pp(h) | <h,_> <- wpsum.providedFilterHooks };
	}
	
	println("Size before removal: <size(allHooks)>");
	allHooks = allHooks - mostUsed<0>;
	println("Total unused: <size(allHooks)>");
	
	return allHooks;
}

@doc{Similar to the above, but get the plugin names instead.}
public map[int,set[str]] computeDistForHookUsesWithNames(HookUsesForDist hud) {
	map[str,int] perPluginCounts = ( p : 0 | p <- hud<0> );
	for (<pn,hn,fn,fl> <- hud) {
		perPluginCounts[pn] += 1;
	}
	
	map[int,set[str]] res = ( );
	for (pn <- perPluginCounts) {
		if (perPluginCounts[pn] in res) {
			res[perPluginCounts[pn]] = res[perPluginCounts[pn]] + { pn };
		} else {
			res[perPluginCounts[pn]] = { pn };
		}
	}
	
	return res;
}

private str makeSimpleCoords(map[int,int] inputs, str mark="", str markExtra="", str legend="") {
	return "\\addplot<if(size(mark)>0){>[mark=<mark><if(size(markExtra)>0){>,<markExtra><}>]<}> coordinates {
		   '<intercalate(" ",[ "(<i>,<inputs[i]>)" | i <- sort(toList(inputs<0>))])>
		   '};<if(size(legend)>0){>
		   '\\addlegendentry{<legend>}<}>";
}

private str makeSimpleCoords(lrel[int,int] inputs, str mark="", str markExtra="", str legend="") {
	return "\\addplot<if(size(mark)>0){>[mark=<mark><if(size(markExtra)>0){>,<markExtra><}>]<}> coordinates {
		   '<intercalate(" ",[ "(<i>,<j>)" | < i, j > <- inputs ])>
		   '};<if(size(legend)>0){>
		   '\\addlegendentry{<legend>}<}>";
}

public str pluginDistChart(map[int hookCount, int plugins] dist, str title="Hook Use in Plugins, by Hook Count", str label="fig:PCount", str markExtra="mark phase=1,mark repeat=5") {
	list[str] coordinateBlocks = [ makeSimpleCoords(dist,mark="x") ];

	str res = "\\begin{figure*}
			  '\\centering
			  '\\begin{tikzpicture}
			  '\\begin{semilogyaxis}[width=\\textwidth,height=.25\\textheight,xlabel=Hook Count,ylabel=Plugin Count (log),xmin=1,ymin=0,xmax=<max(dist<0>)+5>,ymax=<max(dist<1>)+5>,legend style={at={(0,1)},anchor=north west},x tick label style={rotate=90,anchor=east},log ticks with fixed point]
			  '<for (cb <- coordinateBlocks) {> <cb> <}>
			  '\\end{semilogyaxis}
			  '\\end{tikzpicture}
			  '\\caption{<title>.\\label{<label>}} 
			  '\\end{figure*}
			  ";
	return res;	
}

public str makePluginDistChart(map[int,int] dist = ( )) {
	if (size(dist) == 0) {
		dist = computeDistForHookUses(combineUsesForPluginDist());
	}
	return pluginDistChart(dist);
}

public str hookDistChart(lrel[int,int] dist, str title="Hook Popularity, by Plugin Count", str label="fig:HCount", str markExtra="mark phase=1,mark repeat=20") {
	list[str] coordinateBlocks = [ makeSimpleCoords(dist,mark="x",markExtra=markExtra) ];

	str res = "\\begin{figure*}
			  '\\centering
			  '\\begin{tikzpicture}
			  '\\begin{semilogyaxis}[width=\\textwidth,height=.25\\textheight,xlabel=Hook Ranking (Least to Most Popular),ylabel=Plugin Count (log),xmin=0,ymin=0,xmax=<max(dist<0>)+5>,ymax=<max(dist<1>)+5>,legend style={at={(0,1)},anchor=north west},x tick label style={rotate=90,anchor=east},log ticks with fixed point]
			  '<for (cb <- coordinateBlocks) {> <cb> <}>
			  '\\end{semilogyaxis}
			  '\\end{tikzpicture}
			  '\\caption{<title>.\\label{<label>}} 
			  '\\end{figure*}
			  ";
	return res;	
}

public str makeHookDistChart(map[str,int] mostUsed) {
	sorted = sortMostUsed(mostUsed);
	unused = getUnused(mostUsed);
	list[int] usedCounts = reverse([ n | < _, n > <- sorted ]); // + [ 0 | _ <- unused ];
	lrel[int,int] dist = [ < idx, usedCounts[idx] > | idx <- index(usedCounts) ]; 
	return hookDistChart(dist);
}