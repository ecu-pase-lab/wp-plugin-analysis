module lang::php::experiments::plugins::Plugins

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::util::Config;

import Set;
import Relation;
import List;
import IO;
import ValueIO;
import util::Maybe;
import String;

private loc pluginDir = |file:///Users/mhills/PHPAnalysis/plugins|;
private loc pluginBin = |file:///Users/mhills/PHPAnalysis/serialized/plugins|;

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

data PluginInfo = noInfo() | pluginInfo(Maybe[str] pluginName, Maybe[str] testedUpTo, Maybe[str] stableTag, Maybe[str] requiresAtLeast);

public PluginInfo readPluginInfo(str s) {
	loc srcLoc = getPluginSrcLoc(s);
	if (exists(srcLoc+"readme.txt")) {
		fileContents = readFile(srcLoc+"readme.txt");
		pluginName = (/===<v:.*>===\n/i := fileContents) ? just(trim(v)) : nothing();
		testedUpTo = (/Tested up to: <v:.*>\n/i := fileContents) ? just(trim(v)) : nothing();
		stableTag = (/Stable tag: <v:.*>\n/i := fileContents) ? just(trim(v)) : nothing(); 
		requiresAtLeast = (/Requires at least: <v:.*>\n/i := fileContents) ? just(trim(v)) : nothing(); 
		return pluginInfo(pluginName, testedUpTo, stableTag, requiresAtLeast);
	} else {
		println("readme.txt not found for plugin <s>");
		return noInfo();
	}
}
