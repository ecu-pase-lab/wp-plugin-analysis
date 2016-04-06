module lang::php::experiments::plugins::WordPress

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::util::Utils;
import lang::php::util::Corpus;
import lang::php::experiments::plugins::Hooks;
import lang::php::experiments::plugins::Locations;

import IO;
import ValueIO;

@doc{Find all derived action hooks defined across all versions of WordPress}
rel[str,Expr] findDerivedActionHooks() {
	return { < v, e > | v <- getVersions("WordPress"), pt := loadBinary("WordPress",v), e <- findDerivedActionHooks(pt) };
}

@doc{Find all simple action hooks defined across all versions of WordPress}
rel[str,str] findSimpleActionHooks() {
	return { < v, e > | v <- getVersions("WordPress"), pt := loadBinary("WordPress",v), e <- findSimpleActionHooks(pt) };
}

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