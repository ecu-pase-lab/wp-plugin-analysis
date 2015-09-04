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

private loc pluginDir = baseLoc + "plugins";
private loc pluginBin = baseLoc + "serialized/plugins";
private loc pluginInfoBin = baseLoc + "serialized/plugin-info";
private loc sqlDir = baseLoc + "generated/plugin-sql";

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

public str subtractBaseLoc(loc l, loc base) {
    adjustBy = 0;
    if (base.scheme == "home" && l.scheme == "file") {
        adjustBy = size("/Users/hillsma");
    }
    return l.path[(size(base.path)+adjustBy)..];
}

public str createPluginModel(loc l, map[str,int] pluginIds) {
    pluginName = l.file;
    pinfo = readBinaryValueFile(#PluginInfo, pluginInfoBin + "<pluginName>-info.bin");
    str line = "";
    if (pinfo is pluginInfo, pinfo.pluginName is just) {
        line = "insert into plugins (id, name, testedUpTo, stableTag, requiresAtLeast, created, modified) values (<pluginIds[pluginName]>, <strOrNull(pinfo.pluginName)>, <strOrNull(pinfo.testedUpTo)>, <strOrNull(pinfo.stableTag)>, <strOrNull(pinfo.requiresAtLeast)>, now(), now());";
    }
    return line;
}


public tuple[str sql, int lastid] createFunctionModel(loc l, map[str,int] pluginIds, int id = 1) {
    pluginName = l.file;
    pinfo = readBinaryValueFile(#PluginInfo, pluginInfoBin + "<pluginName>-info.bin");
    finfo = readBinaryValueFile(#rel[str fname, loc l], pluginInfoBin + "<pluginName>-functions.bin");
    list[str] rows = [ ];
    
    if (pinfo is pluginInfo, pinfo.pluginName is just) {
        for ( <fname, floc> <- finfo) {
            rows = rows + "insert into functions (id, plugin_id, function_name, function_loc, created, modified) values (<id>, <pluginIds[pluginName]>, <strOrNull(just(fname))>, <strOrNull(just(subtractBaseLoc(floc, l)))>, now(), now());";
            id += 1;
        }
    }
    
    return < intercalate("\n", rows), id >;
}

public tuple[str sql, int lastid] createMethodModel(loc l, map[str,int] pluginIds, int id = 1) {
    pluginName = l.file;
    pinfo = readBinaryValueFile(#PluginInfo, pluginInfoBin + "<pluginName>-info.bin");
    minfo = readBinaryValueFile(#rel[str cname, str mname, loc l], pluginInfoBin + "<pluginName>-methods.bin");
    list[str] rows = [ ];
    
    if (pinfo is pluginInfo, pinfo.pluginName is just) {
        for ( <cname, mname, mloc> <- minfo) {
            rows = rows + "insert into methods (id, plugin_id, class_name, method_name, method_loc, created, modified) values (<id>, <pluginIds[pluginName]>, <strOrNull(just(cname))>, <strOrNull(just(mname))>, <strOrNull(just(subtractBaseLoc(mloc, l)))>, now(), now());";
            id += 1;
        }
    }
    
    return < intercalate("\n", rows), id >;
}

public tuple[str sql, int lastid] createHookModel(loc l, map[str,int] pluginIds, int id = 1) {
    pluginName = l.file;
    pinfo = readBinaryValueFile(#PluginInfo, pluginInfoBin + "<pluginName>-info.bin");
    minfo = readBinaryValueFile(#rel[str hookname, str callback, int priority], pluginInfoBin + "<pluginName>-hooks.bin");
    list[str] rows = [ ];
    
    if (pinfo is pluginInfo, pinfo.pluginName is just) {
        for ( <hookname, callback, priority> <- minfo) {
            rows = rows + "insert into hooks (id, plugin_id, hook_name, hook_callback, hook_priority, created, modified) values (<id>, <pluginIds[pluginName]>, <strOrNull(just(hookname))>, <strOrNull(just(callback))>, <priority>, now(), now());";
            id += 1;
        }
    }
    
    return < intercalate("\n", rows), id >;
}

public tuple[str sql, int lastid] createFilterModel(loc l, map[str,int] pluginIds, int id = 1) {
    pluginName = l.file;
    pinfo = readBinaryValueFile(#PluginInfo, pluginInfoBin + "<pluginName>-info.bin");
    minfo = readBinaryValueFile(#rel[str tagname, str callback, int priority], pluginInfoBin + "<pluginName>-actions.bin");
    list[str] rows = [ ];
    
    if (pinfo is pluginInfo, pinfo.pluginName is just) {
        for ( <tagname, callback, priority> <- minfo) {
            rows = rows + "insert into filters (id, plugin_id, tag_name, filter_callback, filter_priority, created, modified) values (<id>, <pluginIds[pluginName]>, <strOrNull(just(tagname))>, <strOrNull(just(callback))>, <priority>, now(), now());";
            id += 1;
        }
    }
    
    return < intercalate("\n", rows), id >;
}

public void createModels() {
    list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    map[str,int] pluginIds = assignPluginIds();
    
    int functionId = 1;
    int methodId = 1;
    int hookId = 1;
    int filterId = 1;
        
    for (l <- pluginDirs) {
        pluginSql = createPluginModel(l, pluginIds);
        < functionSql, functionId > = createFunctionModel(l, pluginIds, id = functionId);
        < methodSql, methodId > = createMethodModel(l, pluginIds, id = methodId);
        < hookSql, hookId > = createHookModel(l, pluginIds, id = hookId);
        < filterSql, filterId > = createFilterModel(l, pluginIds, id = filterId);
        
        writeFile(sqlDir + (l.file + ".sql"), intercalate("\n", [pluginSql, functionSql, methodSql, hookSql, filterSql]));
    }
    
    writeFile(sqlDir + "create-models.sql", createModelTables());
    writeFile(sqlDir + "load-data.sql", createLoader());
}

public str createModelTables() {
    res = 
        "CREATE TABLE plugins (
        '  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        '  name VARCHAR(50),
        '  testedUpTo VARCHAR(50),
        '  stableTag VARCHAR(50),
        '  requiresAtLeast VARCHAR(50),
        '  created DATETIME DEFAULT NULL,
        '  modified DATETIME DEFAULT NULL
        ');
        '
        'CREATE TABLE functions (
        '  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        '  plugin_id INT UNSIGNED,
        '  function_name VARCHAR(255),
        '  function_loc VARCHAR(255),
        '  created DATETIME DEFAULT NULL,
        '  modified DATETIME DEFAULT NULL
        ');
        '
        'CREATE TABLE methods (
        '  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        '  plugin_id INT UNSIGNED,
        '  class_name VARCHAR(255),
        '  method_name VARCHAR(255),
        '  method_loc VARCHAR(255),
        '  created DATETIME DEFAULT NULL,
        '  modified DATETIME DEFAULT NULL
        ');
        '
        'CREATE TABLE hooks (
        '  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        '  plugin_id INT UNSIGNED,
        '  hook_name VARCHAR(255),
        '  hook_callback VARCHAR(255),
        '  hook_priority INT UNSIGNED,
        '  created DATETIME DEFAULT NULL,
        '  modified DATETIME DEFAULT NULL
        ');
        '
        'CREATE TABLE filters (
        '  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        '  plugin_id INT UNSIGNED,
        '  tag_name VARCHAR(255),
        '  filter_callback VARCHAR(255),
        '  filter_priority INT UNSIGNED,
        '  created DATETIME DEFAULT NULL,
        '  modified DATETIME DEFAULT NULL
        ');
        '";
    
    return res;
}

public str createLoader() {
    list[loc] pluginDirs = sort([l | l <- pluginDir.ls, isDirectory(l) ]);
    res =
        "<for (l <- pluginDirs) {>source <(l.file + ".sql")>;
        '<}>
        '";
    return res;
}
