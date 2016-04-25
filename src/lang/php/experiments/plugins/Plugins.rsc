module lang::php::experiments::plugins::Plugins

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::pp::PrettyPrinter;
import lang::php::analysis::evaluators::AlgebraicSimplification;
import lang::php::analysis::evaluators::SimulateCalls;
import lang::php::analysis::includes::IncludesInfo;
import lang::php::analysis::includes::QuickResolve;

import lang::php::experiments::plugins::Summary;
import lang::php::experiments::plugins::Conflicts;
import lang::php::experiments::plugins::CommentSyntax;
import lang::php::experiments::plugins::Shortcodes;
import lang::php::experiments::plugins::MetaData;
import lang::php::experiments::plugins::Options;
import lang::php::experiments::plugins::Hooks;
import lang::php::experiments::plugins::Abstractions;
import lang::php::experiments::plugins::Locations;
import lang::php::experiments::plugins::TextSearch;
import lang::php::experiments::plugins::Includes;

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

@doc{This is only needed if these were built originally when systems where just aliases to maps}
public void convertPluginBinaries() {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs) {
    	println("Converting binary for <l.file>");
    	loc binLoc = pluginBin + "<l.file>.pt";
    	writeBinaryValueFile(binLoc, convertSystem(readBinaryValueFile(#value, binLoc), l), compression=false);
    }
}

@doc{This is only needed if these were built originally when systems where just aliases to maps}
public void convertToNamedSystem() {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs) {
    	println("Converting binary for <l.file>");
    	loc binLoc = pluginBin + "<l.file>.pt";
    	pt = readBinaryValueFile(#System, binLoc);
    	pt = namedSystem(l.file, pt.baseLoc, pt.files);
    	writeBinaryValueFile(binLoc, pt, compression=false);
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
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file)), l.file >= "gravity-forms-advanced-file-uploader") {
    	if ( (overwrite && exists(pluginInfoBin+"<l.file>-info.bin")) || !exists(pluginInfoBin+"<l.file>-info.bin")) { 
	        println("Extracting info for plugin: <l.file>");
	        extractPluginSummary(l.file);
		} else {
			println("Already extracted info for plugin: <l.file>");
		}
    }
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

@doc{Return the shortcodes defined in a given plugin, with locations.}
rel[str,NameOrExpr,loc] pluginShortcodesWithLocations(str pluginName) {
    psum = loadPluginSummary(pluginName);
	return { < pluginName, e, at > | < e, at > <- psum.shortcodes };
}

@doc{Return the shortcodes defined in all plugins in the corpus with the plugin name as first projection}
rel[str,NameOrExpr,loc] pluginShortcodesWithLocations() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	return { < pn, sn, at > | l <- pluginDirs, exists(pluginInfoBin + "<l.file>-summary.bin"), < pn, sn, at > <- pluginShortcodesWithLocations(l.file) }; 
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
	= functionTarget(str pluginName, str fname, loc at)
	| potentialFunctionTarget(str pluginName, str fname, loc at)
	| unknownFunctionTarget(str fname) 
	| methodTarget(str pluginName, str cname, str mname, loc at)
	| potentialMethodTarget(str pluginName, str cname, str mname, loc at) 
	| staticMethodTarget(str pluginName, str cname, str mname, loc at)
	| unknownMethodTarget(str mname) 
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
	for (< loc usedAt, NameOrExpr use, loc defAt, NameOrExpr def, Expr reg, int sp > <- hu) {
		if (h:call(name(name(_)),[actualParameter(_,_),actualParameter(scalar(string(fn)),_),_*]) := reg) {
			// These are the cases for where the call target is given as a string.
			if (fn in psum.functions<0> || fn in wpsum.functions<0>) {
				// In this case, the target is an actual function provided by the plugin or by WordPress
				res = res + { < usedAt, use, defAt, def, reg, 99, functionTarget(pluginName,fn,at) > | < fn,at> <- (psum.functions + wpsum.functions) };
			} else if (contains(fn,"::")) {
				// Here the target is a static method on a class, given as ClassName::MethodName
				pieces = split("::",fn);
				methodName = pieces[-1];
				classPieces = split("\\",intercalate("::",pieces[..-1]));
				className = classPieces[-1];

				possibleMethods = { < className, methodName, at > | < className, methodName, at, _ > <- (psum.methods + wpsum.methods) };

				if (size(possibleMethods) > 0) {
					res = res + { < usedAt, use, defAt, def, reg, 99, staticMethodTarget(pluginName,className, methodName, at) > | < className, methodName, at > <- possibleMethods };
				} else {
					res = res + < usedAt, use, defAt, def, reg, 0, unknownMethodTarget(methodName) >;
				}
			} else if (contains(fn,"\\")) {
				// Here the target is a function given with the namespace (which technically isn't supported by WordPress)
				functionPieces = split("\\", fn);
				functionName = functionPieces[-1];
				if (functionName in psum.functions<0> || functionName in wpsum.functions<0>) {
					res = res + { < usedAt, use, defAt, def, reg, 99, functionTarget(pluginName,functionName,at) > | < functionName,at> <- (psum.functions + wpsum.functions) };
				} else {
					res = res + < usedAt, use, defAt, def, reg, 0, unknownFunctionTarget(fn) >;
				}			
			} else {
				// If we don't identify the function based on those categories, this is an unknown function
				res = res + < usedAt, use, defAt, def, reg, 0, unknownFunctionTarget(fn) >;
			}
		} else if (h:call(name(name(_)),[actualParameter(_,_),actualParameter(array([arrayElement(_,var(name(name("this"))),_),arrayElement(_,scalar(string(mn)),_)]),_),_*]) := reg) {
			// This is a method call on $this, with the method name given as a string literal
			containerClasses = { cname | < cname, at > <- (wpsum.classes + psum.classes), insideLoc(defAt,at) || insideLoc(usedAt,at) };
			possibleMethods = { < cname, mn, at > | cname <- containerClasses, < cname, mn, at, _ > <- (psum.methods + wpsum.methods) };
			if (size(possibleMethods) > 0) {
				res = res + { < usedAt, use, defAt, def, reg, 99, methodTarget(pluginName, cname, mname, at) > | < cname, mname, at > <- possibleMethods };
			} else {
				res = res + < usedAt, use, defAt, def, reg, 0, unknownMethodTarget(mn) >;
			}
		} else if (h:call(name(name(_)),[actualParameter(_,_),actualParameter(array([arrayElement(_,var(name(name("this"))),_),arrayElement(_,e,_)]),_),_*]) := reg) {
			// This is a method call on $this, with the method name given as an expression
			containerClasses = { cname | < cname, at > <- (wpsum.classes + psum.classes), insideLoc(defAt,at) || insideLoc(usedAt,at) };
			methodNameModel = nameModel(e,psum);
			methodRegexp = regexpForNameModel(methodNameModel);
			possibleMethods = { < cname, mn, at > | cname <- containerClasses, < cname, mn, at, _ > <- (psum.methods + wpsum.methods), rexpMatch(mn, methodRegexp) };
			if (size(possibleMethods) > 0) {
				res = res + { < usedAt, use, defAt, def, reg, specificity(methodNameModel, "somename"), methodTarget(pluginName, cname, mname, at) > | < cname, mname, at > <- possibleMethods };
			} else {
				res = res + < usedAt, use, defAt, def, reg, 0, unknownMethodTarget(pp(e)) >;
			}
		} else if (h:call(name(name(_)),[actualParameter(_,_),actualParameter(array([arrayElement(_,scalar(string(cn)),_),arrayElement(_,scalar(string(mn)),_)]),_),_*]) := reg) {
			// This is a static method call, given instead as array elements, e.g., array("ClassName","MethodName")
			possibleMethods = { < cn, mn, at > | < cn, mn, at, _ > <- (psum.methods + wpsum.methods) };
			if (size(possibleMethods) > 0) {
				res = res + { < usedAt, use, defAt, def, reg, 99, staticMethodTarget(pluginName, cname, mname, at) > | < cname, mname, at > <- possibleMethods };
			} else {
				res = res + < usedAt, use, defAt, def, reg, 0, unknownMethodTarget(mn) >;
			}
		} else if (h:call(name(name(_)),[actualParameter(_,_),actualParameter(array([arrayElement(_,scalar(string(cn)),_),arrayElement(_,e,_)]),_),_*]) := reg) {
			// This is a static method call, given instead as array elements, but with the second element an expression
			possibleMethods = { < cn, mn, at > | < cn, mn, at, _ > <- (psum.methods + wpsum.methods) };
			methodNameModel = nameModel(e,psum);
			methodRegexp = regexpForNameModel(methodNameModel);
			if (size(possibleMethods) > 0) {
				res = res + { < usedAt, use, defAt, def, reg, specificity(methodNameModel, "somename"), staticMethodTarget(pluginName, cname, mname, at) > | < cname, mname, at > <- possibleMethods, rexpMatch(mname, methodRegexp) };
			} else {
				res = res + < usedAt, use, defAt, def, reg, 0, unknownMethodTarget(pp(e)) >;
			}
		} else if (h:call(name(name(_)),[actualParameter(_,_),actualParameter(array([arrayElement(_,Expr e,_),arrayElement(_,scalar(string(mn)),_)]),_),_*]) := reg) {
			// This is a method call on some expression, since we don't have types we do a probable match
			possibleMethods = { < cname, mn, at > | < cname, mn, at, _ > <- (psum.methods + wpsum.methods) };
			if (size(possibleMethods) > 0) {
				res = res + { < usedAt, use, defAt, def, reg, 99, potentialMethodTarget(pluginName, cname, mname, at) > | < cname, mname, at > <- possibleMethods };
			} else {
				res = res + < usedAt, use, defAt, def, reg, 0, unknownMethodTarget(mn) >;
			}
		} else if (h:call(name(name(_)),[actualParameter(_,_),actualParameter(array([arrayElement(_,Expr e,_),arrayElement(_,e,_)]),_),_*]) := reg) {
			// This is a method call on some expression, since we don't have types we do a probable match
			possibleMethods = { < cname, mn, at > | < cname, mn, at, _ > <- (psum.methods + wpsum.methods) };
			methodNameModel = nameModel(e,psum);
			methodRegexp = regexpForNameModel(methodNameModel);
			if (size(possibleMethods) > 0) {
				res = res + { < usedAt, use, defAt, def, reg, specificity(methodNameModel, "somename"), potentialMethodTarget(pluginName, cname, mname, at) > | < cname, mname, at > <- possibleMethods, rexpMatch(mname, methodRegexp) };
			} else {
				res = res + < usedAt, use, defAt, def, reg, 0, unknownMethodTarget(pp(e)) >;
			}
		//} else if (h:call(name(name(_)),[actualParameter(_,_),actualParameter(e,_),_*]) := reg) {
		//	functionNameModel = nameModel(e,psum);
		//	functionAsString = pp(e);
		//	functionRegexp = regexpForNameModel(functionNameModel);
		//	if (contains(functionAsString,"\\") || contains(functionAsString,"::")) {
		//		res = res + < usedAt, use, defAt, def, reg, 0, unknownFunctionTarget(functionAsString) >;
		//	} else {
		//		res = res + { < usedAt, use, defAt, def, reg, specificity(functionNameModel, "somename"), potentialFunctionTarget(fname, at) > | < fname, at > <- (psum.functions + wpsum.functions), rexpMatch(fname, functionRegexp) };
		//	}
		} else {
			res = res + < usedAt, use, defAt, def, reg, 0, unresolvedTarget() >;
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

public str mostUsedTable(lrel[str,int] mostUsed, int cutoff) {
	wpsum = loadWordpressPluginSummary("4.3.1");
	filterNames = { pp(e) | e <- wpsum.providedFilterHooks<0> };
	actionNames = { pp(e) | e <- wpsum.providedActionHooks<0> };
	topN = mostUsed[0..cutoff];
	
	str fa(str s) {
		if (s in filterNames && s in actionNames) {
			return "B";
		} else if (s in filterNames) {
			return "F";
		} else if (s in actionNames) {
			return "A";
		} else {
			return "N";
		}
	}
	
	str lines = intercalate("\n",["<s> & & <i> & & <fa(s)> \\\\" | <s,i> <- topN]);
	
	str tableContents = 
	"\\begin{table}
	'\\begin{center}
	'\\caption{Most Popular WordPress Hooks.\\label{tbl:popular}}
	'\\ra{1.2}
	'\\begin{tabular}{@{}lcrcl@{}} \\toprule
	'Hook & \\phantom{aaa} & Usage Count & \\phantom{bbb} & Type \\\\ \\midrule
	'<lines>
	'\\bottomrule
	'\\end{tabular}
	'\\end{center}
	'The type is either A (Action) or F (Filter).
	'\\end{table}
	";
	
	return tableContents;
}

// alias HookUsesWithPlugin = rel[str pluginName, loc usedAt, NameOrExpr use, loc defAt, NameOrExpr def, Expr reg, int specificity];
// alias HookUsesResolved = rel[loc usedAt, NameOrExpr use, loc defAt, NameOrExpr def, Expr reg, int specificity, HookUseTarget target];

//data HookUseTarget 
//	= functionTarget(str pluginName, str fname, loc at)
//	| potentialFunctionTarget(str pluginName, str fname, loc at)
//	| unknownFunctionTarget(str fname) 
//	| methodTarget(str pluginName, str cname, str mname, loc at)
//	| potentialMethodTarget(str pluginName, str cname, str mname, loc at) 
//	| staticMethodTarget(str pluginName, str cname, str mname, loc at)
//	| unknownMethodTarget(str mname) 
//	| unresolvedTarget()
//	;

private int targetQuality(HookUseTarget t) = 2 when (t is functionTarget) || (t is methodTarget) || (t is staticMethodTarget);
private int targetQuality(HookUseTarget t) = 1 when (t is potentialFunctionTarget) || (t is potentialMethodTarget);
private default int targetQuality(HookUseTarget t) = 0;

public lrel[str pn, HookUseTarget target] findBestImplementationsForId(str v, int id) {
	return findBestImplementationsForId(v, id, combineUses());
}

public lrel[str pn, HookUseTarget target] findBestImplementationsForId(str v, int id, HookUsesWithPlugin hup) {
	imap = loadIndexMap(v);
	hookexp = imap[id];
	
	// The expression naming the handler
	searchExp = expr(hookexp);
	if (scalar(string(hn)) := hookexp) {
		searchExp = name(name(hn));
	}
	
	// Narrow this down to just the links for this hook
	narrowed = { < pn, uat, u, s > | < pn, uat, u, dat, searchExp, r, s > <- hup };
	
	// Now, use this to link to the actual handler implementations
	rel[str pn, loc usedAt, NameOrExpr use, int specificity, HookUseTarget target] res = { };
	for (pn <- narrowed<0>) {
		res = res + { < pn, uat, u, s, t > | <uat, u, _, searchExp, _, s, t > <- resolveCallbacks(pn) };
	}
	
	// Sort these implementations by the popularity of the plugin that contains them
	dc = readPluginDownloadCounts();
	lrel[str pn, loc usedAt, NameOrExpr use, int specificity, HookUseTarget target] sorted = [ ];
	
	bool sortfun(tuple[str pn, loc usedAt, NameOrExpr use, int specificity, HookUseTarget target] t1, tuple[str pn, loc usedAt, NameOrExpr use, int specificity, HookUseTarget target] t2) {
		t1downloads = (t1.pn in dc) ? dc[t1.pn] : 0;
		t2downloads = (t2.pn in dc) ? dc[t2.pn] : 0;
		t1quality = targetQuality(t1.target);
		t2quality = targetQuality(t2.target);
		
		if (t1.specificity != t2.specificity) return t1.specificity < t2.specificity;
		if (t1quality != t2quality) return t1quality < t2quality;
		
		return t1downloads < t2downloads;
	}
	
	sorted = reverse(sort(toList(res), sortfun));
	return sorted<0,4>;
}

public void buildIncludesInfoForPlugins() {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs) {
		pt = loadPluginBinary(l.file);
    	println("Building includes info for plugin <pt.name>");
		buildIncludesInfo(pt);
	}
}

public void buildIncludesInfoForWP() {
	for (v <- getVersions("WordPress")) {
		pt = loadBinary("WordPress", v);
		println("Building includes info for WordPress version <v>");
		buildIncludesInfo(pt);
	}
}

@doc{The location of serialized quick resolve information}
private loc infoLoc = baseLoc + "serialized/quickResolved";

public void quickResolveWordpress() {
	p = "WordPress";
	for (v <- getVersions(p)) {
		sys = loadBinary(p,v);
		if (!includesInfoExists(p,v)) buildIncludesInfo(p,v,sys.baseLoc);
		IncludesInfo iinfo = loadIncludesInfo(p, v);
		rel[loc,loc,loc] res = { };
		map[loc,Duration] timings = ( );
		println("Resolving for <size(sys.files<0>)> files");
		counter = 0;
		for (l <- sys.files) {
			dt1 = now();
			qr = quickResolve(sys, iinfo, l, sys.baseLoc, libs = { });
			dt2 = now();
			res = res + { < l, ll, lr > | < ll, lr > <- qr };
			counter += 1;
			if (counter % 100 == 0) {
				println("Resolved <counter> files");
			}
			timings[l] = (dt2 - dt1);
		}
		writeBinaryValueFile(infoLoc + "<p>-<v>-qr.bin", res);
		writeBinaryValueFile(infoLoc + "<p>-<v>-qrtime.bin", timings);
	}
}

public loc patchLoc(loc baseLoc, loc newBase, loc toPatch) {
	// NOTE: We assume these have the same scheme, we should check that
	toPatchTarget = toPatch.path[size(baseLoc.path)..];
	return newBase + toPatchTarget;
}

public str patchLocString(loc baseLoc, loc newBase, str toPatch) {
	// NOTE: We assume these have the same scheme, we should check that
	toPatchTarget = toPatch[size(baseLoc.path)..];
	return (newBase + toPatchTarget).path;
}

public void quickResolvePlugins() {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    for (l <- pluginDirs, l.file > "wp-bible-embed") {
    	println("Resolving for plugin <l.file>");
		quickResolvePlugin(l.file);
	}
}

public void findMissingIncludesInfo() {
	pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	for (l <- pluginDirs, !includesInfoExists(l.file)) {
		println("<l.file>");
	}
}

public int countPluginsWithIncludesInfo() {
	pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	counter = 0;
	for (l <- pluginDirs, includesInfoExists(l.file)) {
		counter += 1;
	}
	return counter;
}

public void quickResolvePlugins2() {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l), !includesInfoExists(l.file) ]);
    for (l <- pluginDirs) {
    	println("Resolving for plugin <l.file>");
		quickResolvePlugin(l.file);
	}
}

public System relocateFiles(System sys, loc newBase) {
	patched = sys[files = ( patchLoc(sys.baseLoc, newBase, l) : sys.files[l] | l <- sys.files)];
	patched = visit(patched) {
		case fc:fileConstant() => fc[@actualValue=patchLocString(sys.baseLoc, newBase, fc@actualValue)] when (fc@actualValue)?
		
		case dc:dirConstant() => dc[@actualValue=patchLocString(sys.baseLoc, newBase, dc@actualValue)] when (dc@actualValue)?
	}
	return patched;
}

public System installPlugin(System wp, System plugin) {
	patched = relocateFiles(plugin, wp.baseLoc + "wp-content/plugins/<plugin.name>/");
	return wp[files=wp.files + patched.files];
}

public void quickResolvePlugin(str pluginName) {
	sys = loadPluginBinary(pluginName);
	psum = loadPluginSummary(pluginName);
	
	if (psum.pInfo is pluginInfo && just(maxVersion) := psum.pInfo.testedUpTo) {
		if (binaryExists("WordPress",maxVersion)) {
			// Now, "install" the plugin into WordPress (at least logically)
			wpsys = loadBinary("WordPress", maxVersion);
			wpsysExtended = installPlugin(wpsys, sys);
			
			buildIncludesInfo(wpsysExtended, overrideName=sys.name);
			iinfo = loadIncludesInfo(sys.name);
			
			rel[loc,loc,loc] res = { };
			map[loc,Duration] timings = ( );
			println("Resolving for <size(wpsysExtended.files<0>)> files");
			counter = 0;
			for (l <- wpsysExtended.files) {
				dt1 = now();
				qr = quickResolve(wpsysExtended, iinfo, l, wpsysExtended.baseLoc, libs = { });
				dt2 = now();
				res = res + { < l, ll, lr > | < ll, lr > <- qr };
				counter += 1;
				if (counter % 100 == 0) {
					println("Resolved <counter> files");
				}
				timings[l] = (dt2 - dt1);
			}
			writeBinaryValueFile(infoLoc + "<sys.name>-qr.bin", res);
			writeBinaryValueFile(infoLoc + "<sys.name>-qrtime.bin", timings);			
		} else {
			println("WordPress version <maxVersion> does not exist");
		}
	} else {
		println("Could not use plugin info for plugin <pluginName>");
	}
}

public System loadInstalledPlugin(str pluginName) {
	sys = loadPluginBinary(pluginName);
	psum = loadPluginSummary(pluginName);
	
	if (psum.pInfo is pluginInfo && just(maxVersion) := psum.pInfo.testedUpTo && binaryExists("WordPress",maxVersion)) {
		// Now, "install" the plugin into WordPress (at least logically)
		wpsys = loadBinary("WordPress", maxVersion);
		wpsysExtended = installPlugin(wpsys, sys);
		return wpsysExtended;
	}
	
	throw "Cannot load installed version of <pluginName>";
}

public QRRel loadResolvedPluginIncludes(str pluginName) {
	return readBinaryValueFile(#rel[loc file, loc source, loc target], infoLoc + "<pluginName>-qr.bin");
}

public bool quickResolveComputed(str pluginName) = exists(infoLoc + "<pluginName>-qr.bin");

@doc{Extract inclusion guard information for all pre-parsed plugin binaries}
public void extractIncludeGuards(bool overwrite = true) {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l), l.file != "wp-bible-embed" ]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file))) {
    	if ( (overwrite && exists(pluginIncludesBin+"<l.file>-include-guards.bin")) || !exists(pluginIncludesBin+"<l.file>-include-guards.bin")) { 
	        println("Extracting include guard info for plugin: <l.file>");
	        igrel = includeGuards(loadPluginBinary(l.file));
	        writeBinaryValueFile(pluginIncludesBin+"<l.file>-include-guards.bin", igrel);
		} else {
			println("Already extracted info for plugin: <l.file>");
		}
    }
}

public bool includeGuardsExtracted(str pluginName) = exists(pluginIncludesBin+"<pluginName>-include-guards.bin");

public IRel loadIncludeGuards(str pluginName) {
	return readBinaryValueFile(#IRel, pluginIncludesBin+"<pluginName>-include-guards.bin");
}

public GuardedQRRel buildGuardedIncludesRel(str pluginName) {
	return buildGuardedIncludesRel(loadResolvedPluginIncludes(pluginName),loadIncludeGuards(pluginName));
}

public void buildGuardedIncludesRels(bool overwrite = true) {
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l)]);
    for (l <- pluginDirs, exists(getPluginBinLoc(l.file)), quickResolveComputed(l.file), includeGuardsExtracted(l.file)) {
    	if ( (overwrite && exists(pluginIncludesBin+"<l.file>-guarded-qr.bin")) || !exists(pluginIncludesBin+"<l.file>-guarded-qr.bin")) { 
	        println("Building guarded includes relation for plugin: <l.file>");
	        gir = buildGuardedIncludesRel(l.file);
	        writeBinaryValueFile(pluginIncludesBin+"<l.file>-guarded-qr.bin", gir);
		} else {
			println("Already built relation for plugin: <l.file>");
		}
    }
}

public GuardedQRRel findGuardedIncludes() {
	GuardedQRRel res = { };
    pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l)]);
    for (l <- pluginDirs, exists(pluginIncludesBin+"<l.file>-guarded-qr.bin")) {
    	gir = readBinaryValueFile(#GuardedQRRel, pluginIncludesBin+"<l.file>-guarded-qr.bin");
    	res = res + { < f, s, t, g > | < f, s, t, g > <- gir, notGuarded() !:= g };
    }
	return res;
}

public GuardedQRRel findGuardedIncludesByFunctionName(set[str] fnames, GuardedQRRel grel) {
	return { < f, s, t, g > | 
		< f, s, t, g > <- grel, 
		guardedBy(el) := g, 
		[_*,unaryOperation(call(name(name(cn)),_),booleanNot()),_*] := el,
		cn in fnames
		};
}

public map[str,int] constantDistribution(GuardedQRRel grel) {
	map[str,int] res = ( );
	for (/call(name(name("defined")),[actualParameter(scalar(string(cn)),_)]) := grel) {
		if (cn in res) {
			res[cn] = res[cn] + 1;
		} else {
			res[cn] = 1;
		}
	}
	return res;
}
