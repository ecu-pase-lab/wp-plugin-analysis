module lang::php::experiments::plugins::Summary

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::experiments::plugins::Shortcodes;
import lang::php::experiments::plugins::MetaData;
import lang::php::experiments::plugins::Options;
import lang::php::experiments::plugins::Hooks;
import lang::php::experiments::plugins::Abstractions;

import IO;
import List;

@doc{Option type for strings}
data MaybeStr = nothing() | just(str val);

@doc{High-level info for the plugin, stored in the plugin readme}
data PluginInfo = noInfo() | pluginInfo(MaybeStr pluginName, MaybeStr testedUpTo, MaybeStr stableTag, MaybeStr requiresAtLeast);

@doc{The plugin summary, containing extracted information about the plugin.}
data PluginSummary = summary(PluginInfo pInfo, FRel functions, CRel classes, MRel methods, HRel filters, HRel actions, ConstRel consts, ClassConstRel classConsts, ShortcodeRel shortcodes, OptionRel options, PostMetaRel postMetaKeys, UserMetaRel userMetaKeys, CommentMetaRel commentMetaKeys, RHRel providedActionHooks, RHRel providedFilterHooks);

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

