module lang::php::experiments::plugins::Locations

import lang::php::util::Config;

public loc pluginDir = baseLoc + "plugins";
public loc pluginBin = baseLoc + "serialized/plugins/plugins";
public loc infoBin = baseLoc + "serialized/plugins/hook-info";
public loc pluginInfoBin = baseLoc + "serialized/plugins/plugin-info";
public loc pluginAnalysisInfoBin = baseLoc + "serialized/plugins/plugin-analysis-info";
public loc sqlDir = baseLoc + "generated/plugin-sql";
public loc wpAsPluginBin = baseLoc + "serialized/plugins/plugin-wp-info";
public loc pluginIncludesBin = baseLoc + "serialized/plugins/plugin-include-info";

