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

private loc pluginDir = |file:///Users/hillsma/PHPAnalysis/plugins|;
private loc pluginBin = |file:///Users/hillsma/PHPAnalysis/serialized/plugins|;

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

public System loadPluginBinary(str s) {
	loc binLoc = pluginBin + "<s>.pt";
	if (exists(binLoc)) {
		return readBinaryValueFile(#System, binLoc);
	} else {
		throw "No binary for plugin <s> is available at location <binLoc.path>";
	}
}

//public void readPluginInfo
