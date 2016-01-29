module lang::php::experiments::plugins::Plugins

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::pp::PrettyPrinter;

import Set;
import Relation;
import List;
import IO;
import ValueIO;
import String;
import util::Math;
import Map;
import DateTime;

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
    for (l <- pluginDirs, l.file notin skip) {
    	i += 1;
    	println("Building binary #<i> for <l.file>");
        buildPluginBinary(l.file,l,overwrite=overwrite,skip=skip);
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
@doc{A relation from class x method names to the location of the method declaration}
alias MRel = rel[str cname, str mname, loc at];
@doc{The location of the hooks used inside the plugin}
alias HRel = rel[NameOrExpr hookName, loc at, int priority];
@doc{The location of the constants defined in the plugin}
alias ConstRel = rel[str constName, loc at];
@doc{The location of the class constants defined in the plugin}
alias ClassConstRel = rel[str cname, str constName, loc at];
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

@doc{The plugin summary, containing extracted information about the plugin.}
data PluginSummary = summary(PluginInfo pInfo, FRel functions, MRel methods, HRel filters, HRel actions, ConstRel consts, ClassConstRel classConsts, ShortcodeRel shortcodes, OptionRel options, PostMetaRel postMetaKeys, UserMetaRel userMetaKeys, CommentMetaRel commentMetaKeys);

@doc{Extract the information on declared functions for the given system}
FRel definedFunctions(System s) {
    return { < fname, f@at > | /f:function(fname,_,_,_) := s };
}

@doc{Extract the information on declared methods for the given system}
MRel definedMethods(System s) {
    return { < cname, mname, m@at > | /c:class(cname,_,_,_,members) := s, m:method(mname,mods,_,_,_) <- members, \public() in mods || !(\private() in mods || \protected() in mods) };
}

@doc{Extract the information on declared constants for the given system}
ConstRel definedConstants(System s) {
	return { < cn, c@at > | /c:call(name(name("define")),[actualParameter(scalar(string(cn)),false),actualParameter(e,false)]) := s };
}

@doc{Extract the information on declared class constants for the given system}
ClassConstRel definedClassConstants(System s) {
	return { < cn, name, cc@at > | /class(cn,_,_,_,cis) := s, constCI(consts) <- cis, cc:const(name,ce) <- consts };
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
                res = res + < name(name(tagname)), c@at, priority >;
            } else {
                res = res + < name(name(tagname)), c@at, 10 >; // 10 is the default priority
            }
        } if (actualParameter(te,_) := plist[0]) {
			if (size(plist) > 2 && actualParameter(scalar(integer(priority)),_) := plist[2]) {
			    res = res + < expr(te), c@at, priority >;
			} else {
			    res = res + < expr(te), c@at, 10 >; // 10 is the default priority
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
                res = res + < name(name(actionName)), c@at, priority >;
            } else {
                res = res + < name(name(actionName)), c@at, 10 >; // 10 is the default priority
            }
        } if (actualParameter(ae,_) := plist[0]) {
            if (size(plist) > 2 && actualParameter(scalar(integer(priority)),_) := plist[2]) {
                res = res + < expr(ae), c@at, priority >;
            } else {
                res = res + < expr(ae), c@at, 10 >; // 10 is the default priority
            }
        }
    }
    
    return res;
}

@doc{Extract a relational summary of the given plugin, passed as a System}
public PluginSummary extractPluginSummary(System pt) {
	return summary(noInfo(), definedFunctions(pt), definedMethods(pt), definedFilters(pt), definedActions(pt), definedConstants(pt), definedClassConstants(pt), definedShortcodes(pt), definedOptions(pt), definedPostMetaKeys(pt), definedUserMetaKeys(pt), definedCommentMetaKeys(pt));
}

@doc{Extract a relational summary of the given plugin from a pre-parsed plugin binary}
public void extractPluginSummary(str pluginName) {
    pt = loadPluginBinary(pluginName);
	s = summary(readPluginInfo(pluginName), definedFunctions(pt), definedMethods(pt), definedFilters(pt), definedActions(pt), definedConstants(pt), definedClassConstants(pt), definedShortcodes(pt), definedOptions(pt), definedPostMetaKeys(pt), definedUserMetaKeys(pt), definedCommentMetaKeys(pt));
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
	vs40 = vs[indexOf(vs,"4.0")..];
	for (v <- vs40) {
		pt = loadBinary("WordPress",v);
		s = summary(noInfo(), definedFunctions(pt), definedMethods(pt), definedFilters(pt), definedActions(pt), definedConstants(pt), definedClassConstants(pt), definedShortcodes(pt), definedOptions(pt), definedPostMetaKeys(pt), definedUserMetaKeys(pt), definedCommentMetaKeys(pt));
		writeBinaryValueFile(wpAsPluginBin + "wordpress-<v>-summary.bin", s);		
	}
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