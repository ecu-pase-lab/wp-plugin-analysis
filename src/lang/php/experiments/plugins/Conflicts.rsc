module lang::php::experiments::plugins::Conflicts

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::experiments::plugins::Summary;

import Prelude;

data FunctionInfo = functionInfo(int totalFunctions, int inPlugins, int conflictingFunctions, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data ClassInfo = classInfo(int totalClasses, int inPlugins, int conflictingClasses, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data MethodInfo = methodInfo(int totalMethods, int inPlugins, int conflictingMethods, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data ConstInfo = constInfo(int totalConsts, int conflictingConsts, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data ClassConstInfo = classConstInfo(int totalClassConsts, int conflictingClassConsts, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data MetaKeyInfo = metaKeyInfo(int totalOccurrences, int totalKeysDefined, int conflictingKeys, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data ShortcodeInfo = shortcodeInfo(int totalOccurrences, int totalShortcodesDefined, int conflictingShortcodes, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

data OptionInfo = optionInfo(int totalOccurrences, int totalOptionsDefined, int conflictingOptions, int conflictingPlugins, int totalConflicts, int smallestSet, real medianSet, int biggestSet);

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

@doc{Get the names of any post meta keys defined multiple times}
set[NameOrExpr] multiplyDefinedPostMetaKeys() = multiplyDefinedKeys(definingPluginsForMetaKeys(pluginPostMetaKeys()));

@doc{Get the names of any user meta keys defined multiple times}
set[NameOrExpr] multiplyDefinedUserMetaKeys() = multiplyDefinedKeys(definingPluginsForMetaKeys(pluginUserMetaKeys()));

@doc{Get the names of any comment meta keys defined multiple times}
set[NameOrExpr] multiplyDefinedCommentMetaKeys() = multiplyDefinedKeys(definingPluginsForMetaKeys(pluginCommentMetaKeys()));

@doc{Get the median value of a list of ints}
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

@doc{Compute information about potential function conflicts}
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

@doc{Compute information about potential class conflicts}
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

@doc{Compute information about potential method conflicts}
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

@doc{Compute information about potential constant conflicts}
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

@doc{Compute information about potential class constant conflicts}
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

@doc{Compute information about potential key conflicts}
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

@doc{Compute information about potential shortcode conflicts}
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

@doc{Compute information about potential option conflicts}
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

@doc{Find cases where a plugin has a conflict with the version of WordPress it supports}
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

@doc{Benchmark the time to run conflict detection on names/PHP entities}
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

@doc{Benchmark the time to run conflict detection on API keys}
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
