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

public loc pluginDir = baseLoc + "plugins";
public loc pluginBin = baseLoc + "serialized/plugins";
public loc pluginInfoBin = baseLoc + "serialized/plugin-info";

public void buildPluginBinary(str s, loc l) {
	logMessage("Parsing <s>. \>\> Location: <l>.", 1);
	files = loadPHPFiles(l, addLocationAnnotations=true);
	
	loc binLoc = pluginBin + "<s>.pt";
	logMessage("Now writing file: <binLoc>...", 2);
	if (!exists(pluginBin)) {
		mkDirectory(pluginBin);
	}
	writeBinaryValueFile(binLoc, files, compression=false);
	logMessage("... done.", 2);
}

public void buildPluginBinaries() {
	pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	for (l <- pluginDirs) {
		buildPluginBinary(l.file,l);
	}
}

public loc getPluginSrcLoc(str s) {
	return pluginDir + s;
}

public loc getPluginBinLoc(str s) {
	return pluginBin + "<s>.pt";
}

public System loadPluginBinary(str s) {
	loc binLoc = getPluginBinLoc(s);
	if (exists(binLoc)) {
		return readBinaryValueFile(#System, binLoc);
	} else {
		throw "No binary for plugin <s> is available at location <binLoc.path>";
	}
}

data PluginInfo = noInfo() | pluginInfo(MaybeStr pluginName, MaybeStr testedUpTo, MaybeStr stableTag, MaybeStr requiresAtLeast);

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

rel[str fname, loc l] definedFunctions(System s) {
	return { < fname, f@at > | /f:function(fname,_,_,_) := s };
}

rel[str cname, str mname, loc l] definedMethods(System s) {
	return { < cname, mname, m@at > | /c:class(cname,_,_,_,members) := s, m:method(mname,mods,_,_,_) <- members, \public() in mods || !(\private() in mods || \protected() in mods) };
}

public list[Expr] badCalls = [ ];

rel[str tagname, str callback, int priority] definedFilters(System s) {
	rel[str tagname, str callback, int priority] res = { };
	
	for (/c:call(name(name("add_filter")), plist) := s, size(plist) >= 2) {
		if (actualParameter(scalar(string(tagname)),_) := plist[0]) {
			if (size(plist) > 2 && actualParameter(scalar(integer(priority)),_) := plist[2]) {
				res = res + < tagname, pp(plist[1]), priority >;
			} else {
				res = res + < tagname, pp(plist[1]), 10 >; // 10 is the default priority
			}
		} else {
			badCalls = badCalls + c;
		}
	}
	
	return res;
}

rel[str hookname, str callback, int priority] definedHooks(System s) {
	rel[str hookname, str callback, int priority] res = { };
	
	for (/c:call(name(name("add_action")), plist) := s, size(plist) >= 2) {
		if (actualParameter(scalar(string(hookname)),_) := plist[0]) {
			if (size(plist) > 2 && actualParameter(scalar(integer(priority)),_) := plist[2]) {
				res = res + < hookname, pp(plist[1]), priority >;
			} else {
				res = res + < hookname, pp(plist[1]), 10 >; // 10 is the default priority
			}
		} else {
			badCalls = badCalls + c;
		}
	}
	
	return res;
}

public void extractPluginInfo(str pluginName) {
	pinfo = readPluginInfo(pluginName);
	pt = loadPluginBinary(pluginName);
	functions = definedFunctions(pt);
	methods = definedMethods(pt);
	actions = definedFilters(pt);
	hooks = definedHooks(pt);
	
	if (!exists(pluginInfoBin)) mkDirectory(pluginInfoBin);
	
	writeBinaryValueFile(pluginInfoBin + "<pluginName>-info.bin", pinfo);	
	writeBinaryValueFile(pluginInfoBin + "<pluginName>-functions.bin", functions);	
	writeBinaryValueFile(pluginInfoBin + "<pluginName>-methods.bin", methods);	
	writeBinaryValueFile(pluginInfoBin + "<pluginName>-actions.bin", actions);	
	writeBinaryValueFile(pluginInfoBin + "<pluginName>-hooks.bin", hooks);	
}

public void extractPluginInfo() {
	pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	for (l <- pluginDirs) {
		println("Extracting info for plugin: <l.file>");
		extractPluginInfo(l.file);
	}
}

// data PluginInfo = noInfo() | pluginInfo(MaybeStr pluginName, MaybeStr testedUpTo, MaybeStr stableTag, MaybeStr requiresAtLeast);

data MaybeStr = nothing() | just(str val);

public str strOrNull(MaybeStr s) = (nothing() := s) ? "NULL" : "\"<s.val>\"";

public map[str,int] assignPluginIds() {
	map[str,int] res = ( );
	pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	id = 1;
	for (l <- pluginDirs) {
		res[l.file] = id; id = id + 1; 
	}
	
	return res;
}

public void createModels() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	map[str,int] pluginIds = assignPluginIds();
}

public list[str] createPluginModel(list[loc] pluginDirs, map[str,int] pluginIds) {
	list[str] rows = [ ];
	for (l <- pluginDirs) {
		pluginName = l.file;
		pinfo = readBinaryValueFile(#PluginInfo, pluginInfoBin + "<pluginName>-info.bin");
		if (pinfo is pluginInfo, pinfo.pluginName is just) {
			rows = rows + "insert into plugins (id, name, testedUpTo, stableTag, requiresAtLeast, created, modified) values (<pluginIds[pluginName]>, <strOrNull(pinfo.pluginName)>, <strOrNull(pinfo.testedUpTo)>, <strOrNull(pinfo.stableTag)>, <strOrNull(pinfo.requiresAtLeast)>, now(), now())";
		}
	}
	return rows;
}

public list[str] createFunctionModel(list[loc] pluginDirs, map[str,int] pluginIds) {
	list[str] rows = [ ];
	for (l <- pluginDirs) {
		pluginName = l.file;
		pinfo = readBinaryValueFile(#PluginInfo, pluginInfoBin + "<pluginName>-info.bin");
		finfo = readBinaryValueFile(#rel[str fname, loc l], pluginInfoBin + "<pluginName>-functions.bin");
		id = 1;
		if (pinfo is pluginInfo, pinfo.pluginName is just) {
			for ( <fname, floc> <- finfo) {
				rows = rows + "insert into functions (id, plugin_id, function_name, function_loc, created, modified) values (<id>, <pluginIds[pluginName]>, <strOrNull(just(fname))>, <strOrNull(just("<floc>"))>, now(), now())";
			}
		}
	}
	return rows;
}

public list[str] createFunctionModel() {
	list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
	map[str,int] pluginIds = assignPluginIds();
	return createFunctionModel(pluginDirs, pluginIds);
}
	