module lang::php::experiments::plugins::Locations

import lang::php::util::Config;

public loc pluginDir = baseLoc + "plugins";
public loc pluginBin = baseLoc + "serialized/plugins";
public loc infoBin = baseLoc + "serialized/hook-info";
public loc pluginInfoBin = baseLoc + "serialized/plugin-info";
public loc pluginAnalysisInfoBin = baseLoc + "serialized/plugin-analysis-info";
public loc sqlDir = baseLoc + "generated/plugin-sql";
public loc wpAsPluginBin = baseLoc + "serialized/plugin-wp-info";

