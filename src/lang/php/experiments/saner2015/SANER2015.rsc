module lang::php::experiments::saner2015::SANER2015

import lang::php::ast::AbstractSyntax;
import lang::php::util::System;
import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::metrics::CC;
import lang::php::stats::Stats;

import String;
import Set;
import List;
import ValueIO;
import IO;

import lang::csv::IO;
import SLOC; // = |csv+rascal://src/lang/php/extract/csvs/linesOfCode.csv?funname=sloc|;
//import DynamicUses = |csv+rascal://src/lang/php/experiments/saner2015/dynamic.csv?funname=dynamicUses|;

data Summary 
	= systemSummary(set[Summary] classes, set[Summary] interfaces, set[Summary] functions, int functionCallCount, int methodCallCount, int staticCallCount, int stmtCount, int exprCount, map[str,int] topFunctions, list[Summary] exceptionInfo, int throwCount, VarFeatureCounts varFeatures, MagicMethodCounts magicMethods, IncludeCounts includeCounts, EvalLikeCounts evalCounts, InvocationCounts invocationCounts)
	| classSummary(str className, set[Summary] methods, set[Modifier] modifiers, int expCount, int stmtCount, loc at)
	| interfaceSummary(str className, set[Summary] methods, loc at)
	| methodSummary(str methodName, int expCount, int stmtCount, set[Modifier] modifiers, int cc, loc at)
	| functionSummary(str functionName, int expCount, int stmtCount, int cc, loc at)
	| exceptionSummary(int expCount, int stmtCount, int catches, bool hasFinally, loc at)
	;

public Summary extractSummaries(System sys) {
	set[Summary] classSummaries = { };
	for (/ClassDef cdef := sys) {
		Summary s = classSummary(cdef.className, {}, cdef.modifiers, size([st | /Stmt st := cdef]), size([ex | /Expr ex := cdef]), cdef@at);
		for (/ClassItem ci := cdef.members, ci is method) {
			s.methods = s.methods + methodSummary(ci.name, size([st | /Stmt st := ci.body]), size([ex | /Expr ex := ci.body]), ci.modifiers, 0 /*computeCC(ci.body)*/, ci@at);
		}
		classSummaries = classSummaries + s;
	}
	
	set[Summary] interfaceSummaries = { };
	for (/InterfaceDef idef := sys) {
		Summary s = interfaceSummary(idef.interfaceName, {}, idef@at);
		for (/ClassItem ci := idef.members, ci is method) {
			s.methods = s.methods + methodSummary(ci.name, size([st | /Stmt st := ci.body]), size([ex | /Expr ex := ci.body]), ci.modifiers, 0 /*computeCC(ci.body)*/, ci@at);
		}
		interfaceSummaries = interfaceSummaries + s;
	}
	
	set[Summary] functionSummaries = { };
	for (/fdef:function(str name, _, _, list[Stmt] body) := sys) {
		Summary s = functionSummary(name, size([st | /Stmt st := body]), size([ex | /Expr ex := body]), 0 /*computeCC(body)*/, fdef@at);
		functionSummaries = functionSummaries + s;
	}

	map[str,int] callCounts = ( );
	for (/c:call(name(name(n)),_) := sys) {
		if (n in callCounts) {
			callCounts[n] = callCounts[n] + 1;
		} else {
			callCounts[n] = 1;
		}
	}
	ccList = reverse(sort([callCounts[cs] | cs <- callCounts]));
	top20 = (size(ccList) >= 20) ? [0..20] : [ ];
	cutoff = (size(ccList) >= 20) ? top20[-1] : 0;
		
	functionCallCount = size([c | /c:call(_,_) := sys]);
	methodCallCount = size([c | /c:methodCall(_,_,_) := sys]);
	staticCallCount = size([c | /c:staticCall(_,_,_) := sys]);
	stmtCount = size([s | /Stmt s := sys]);
	exprCount = size([e | /Expr e := sys]);
	
	// Exception information
	list[Summary] exceptionInfo = [ ];
	
	throwCount = size([t | /t:\throw(_) := sys]);
	for (/tc:tryCatch(b,cl) := sys) {
		es = exceptionSummary(size([st | /Stmt st := b]), size([ex | /Expr ex := b]), size(cl), false, tc@at);
		exceptionInfo = exceptionInfo + es;
	}
	for (/tcf:tryCatchFinally(b,cl,fb) := sys) {
		es = exceptionSummary(size([st | /Stmt st := b]), size([ex | /Expr ex := b]), size(cl), true, tcf@at);
		exceptionInfo = exceptionInfo + es;
	}
	
	return systemSummary(classSummaries, interfaceSummaries, functionSummaries, functionCallCount, methodCallCount, staticCallCount, stmtCount, exprCount, ( cs : callCounts[cs] | cs <- callCounts, callCounts[cs] > cutoff), exceptionInfo, throwCount, getVarFeatureCounts(sys), getMagicMethodCounts(sys), getIncludeCounts(sys), getEvalLikeCounts(sys), getInvocationCounts(sys));
}

public Summary extractSummaries(str p, str v) {
	sys = loadBinary(p,v);
	return extractSummaries(sys);
}

public map[str,Summary] extractSummaries(str p) {
	map[str,Summary] res = ( );
	for (v <- getVersions(p)) {
		res[v] = extractSummaries(p, v);
	}
	return res;
}

public void extractAndWriteSummaries(str p) {
	for (v <- getVersions(p)) {
		sys = loadBinary(p,v);
		s = extractSummaries(sys);
		writeSummary(p, v, s);
	}
}

public void extractAndWriteMissingSummaries(str p) {
	for (v <- getVersions(p), !exists(infoLoc + "<p>-<v>-oo.bin")) {
		sys = loadBinary(p,v);
		s = extractSummaries(sys);
		writeSummary(p, v, s);
	}
}

@doc{The location of serialized OO Summary information}
private loc infoLoc = baseLoc + "serialized/ooSummaries";

public void writeSummary(str p, str v, Summary s) {
	writeBinaryValueFile(infoLoc + "<p>-<v>-oo.bin", s, compression=false);
}

public Summary readSummary(str p, str v) {
	return readBinaryValueFile(#Summary, infoLoc + "<p>-<v>-oo.bin");
}

public void writeSummaries(str p, map[str,Summary] smap) {
	for (v <- smap) writeSummary(p,v,smap[v]);
}

public map[str,Summary] readSummaries(str p) {
	map[str,Summary] res = ( );
	for (v <- getVersions(p), exists(infoLoc + "<p>-<v>-oo.bin"))
		res[v] = readSummary(p,v);
	return res; 
}

public map[str,int] countClassDefs(map[str,Summary] summaries) {
	return ( v : size(summaries[v].classes) | v <- summaries);
}

public map[str,real] countClassDefsAsPercent(map[str,Summary] summaries) {
	return ( v : size(summaries[v].classes)*100.00/summaries[v].stmtCount | v <- summaries);
}

// How much code is in classes?

// What is the average longevity of a class? Of a method?

// Interfaces?

// Exceptions: how many throws? how many try/catch blocks? how many catches?

// Namespaces: are they being used? is code being transitioned to this?

// Closures? (Not really OO, but may be interesting)

public map[str,int] countInterfaceDefs(str p) {
	map[str,int] interfaceDefs = ( );
	for (v <- getVersions(p)) {
		sys = loadBinary(p,v);
		interfaceDefs[v] = size([ c | /InterfaceDef c := sys ]);
	}	
	return interfaceDefs;
}

public rel[str,str,str] gatherClassMethods(str p) {
	rel[str,str,str] res = { };
	for (v <- getVersions(p)) {
		sys = loadBinary(p,v);
		res = res + { < v, cd.className, md.name > | /ClassDef cd := sys, ClassItem md <- cd.members, md is method };
	}
	return res;
}

public map[str,int] countMethodDefs(str p) {
	map[str,int] classDefs = ( );
	for (v <- getVersions(p)) {
		sys = loadBinary(p,v);
		classDefs[v] = size([ c | /ClassDef c := sys ]);
	}	
	return classDefs;
}

data VarFeatureCounts = varFeatureCounts(int varVar, int varFCall, int varMCall, int varNew, int varProp, 
	int varClassConst, int varStaticCall, int varStaticTarget, int varStaticPropertyName, int varStaticPropertyTarget);
	
public VarFeatureCounts getVarFeatureCounts(System sys) {
	int vvuses = size([ e | <_,e> <-  gatherVarVarUses(sys)]); 
	int vvcalls = size([ e | <_,e> <-  gatherVVCalls(sys)]);
	int vvmcalls = size([ e | <_,e> <-  gatherMethodVVCalls(sys)]);
	int vvnews = size([ e | <_,e> <-  gatherVVNews(sys)]);
	int vvprops = size([ e | <_,e> <-  gatherPropertyFetchesWithVarNames(sys)]);
	int vvcconsts = size([ e | <_,e> <-  gatherVVClassConsts(sys)]);
	int vvscalls = size([ e | <_,e> <-  gatherStaticVVCalls(sys)]);
	int vvstargets = size([ e | <_,e> <-  gatherStaticVVTargets(sys)]);
	int vvsprops = size([ e | <_,e> <-  gatherStaticPropertyVVNames(sys)]);
	int vvsptargets = size([ e | <_,e> <-  gatherStaticPropertyVVTargets(sys)]);
	
	return varFeatureCounts(vvuses, vvcalls, vvmcalls, vvnews, vvprops, vvcconsts, vvscalls, vvstargets, vvsprops, vvsptargets); 
}

data MagicMethodCounts = magicMethodCounts(int sets, int gets, int isSets, int unsets, int calls, int staticCalls);

public MagicMethodCounts getMagicMethodCounts(System sys) {
	sets = size(fetchOverloadedSet(sys));
	gets = size(fetchOverloadedGet(sys));
	isSets = size(fetchOverloadedIsSet(sys));
	unsets = size(fetchOverloadedUnset(sys));
	calls = size(fetchOverloadedCall(sys));
	staticCalls = size(fetchOverloadedCallStatic(sys));
	return magicMethodCounts(sets, gets, isSets, unsets, calls, staticCalls);
}

data IncludeCounts = includeCounts(int totalIncludes, int dynamicIncludes);

public IncludeCounts getIncludeCounts(System sys) {
	totalIncludes = size([ i | /i:include(_,_) := sys ]);
	dynamicIncludes = size(gatherIncludesWithVarPaths(sys));
	return includeCounts(totalIncludes, dynamicIncludes);
}

data EvalLikeCounts = evalLikeCounts(int evalCount, int createFunctionCount);

public EvalLikeCounts getEvalLikeCounts(System sys) {
	createFunctionCount = size([ e | /e:call(name(name("create_function")),_) := sys]);
	evalCount = size(gatherEvals(sys));
	return evalLikeCounts(evalCount, createFunctionCount);
}

data InvocationCounts = invocationCounts(int callUserFunc, int callUserFuncArray, int callUserMethod, int callUserMethodArray);

public InvocationCounts getInvocationCounts(System sys) {
	funsToFind = { "call_user_func", "call_user_func_array", "call_user_method", "call_user_method_array" };
	invokers = [ < fn, e@at > | /e:call(name(name(str fn)),_) := sys, fn in funsToFind ];
	
	callUserFuncCount = ("call_user_func" in invokers) ? size(invokers["call_user_func"]) : 0;
	callUserFuncArrayCount = ("call_user_func_array" in invokers) ? size(invokers["call_user_func_array"]) : 0;
	callUserMethodCount = ("call_user_method" in invokers) ? size(invokers["call_user_method"]) : 0;
	callUserMethodArrayCount = ("call_user_method_array" in invokers) ? size(invokers["call_user_method_array"]) : 0;
	 
	return invocationCounts(callUserFuncCount, callUserFuncArrayCount, callUserMethodCount, callUserMethodArrayCount);
}

// NOTE: We are leaving this out for now...
data VarargsCounts = varargsCounts(int varArgsFunctions, int varArgsCalls);

public VarargsCounts getVarargsCounts(System sys) {
	funsToFind = { "func_get_args", "func_num_args", "func_get_arg" };
	invokers = [ < fn, e@at > | /e:call(name(name(str fn)),_) := sys, fn in funsToFind ];
	return varargsCounts(0, size(invokers));
}

public list[int] getNumbersForSystem(Summary s) {
	list[int] stats = [ s.exprCount, s.stmtCount ];
	
	VarFeatureCounts vc = s.varFeatures;
	varStats = [ vc.varVar, vc.varFCall, vc.varMCall, vc.varNew, vc.varProp, vc.varClassConst, vc.varStaticCall, vc.varStaticTarget, vc.varStaticPropertyName, vc.varStaticPropertyTarget, sum([vc.varVar, vc.varFCall, vc.varMCall, vc.varNew, vc.varProp, vc.varClassConst, vc.varStaticCall, vc.varStaticTarget, vc.varStaticPropertyName, vc.varStaticPropertyTarget]) ];
	
	MagicMethodCounts mc = s.magicMethods;
	magicStats = [ mc.sets, mc.gets, mc.isSets, mc.unsets, mc.calls, mc.staticCalls, sum([mc.sets, mc.gets, mc.isSets, mc.unsets, mc.calls, mc.staticCalls]) ];
	
	IncludeCounts ic = s.includeCounts;
	includeStats = [ ic.totalIncludes, ic.dynamicIncludes ];
	
	EvalLikeCounts ec = s.evalCounts;
	evalStats = [ ec.evalCount, ec.createFunctionCount, sum([ec.evalCount, ec.createFunctionCount]) ];
	
	InvocationCounts ivc = s.invocationCounts; 	
	invokeStats = [ ivc.callUserFunc, ivc.callUserFuncArray, ivc.callUserMethod, ivc.callUserMethodArray, sum([ivc.callUserFunc, ivc.callUserFuncArray, ivc.callUserMethod, ivc.callUserMethodArray]) ];
	
	return stats + varStats + magicStats + includeStats + evalStats + invokeStats;	
}

public list[str] getColumnHeaders() {
	list[str] res = [ "System", "Version", "SLOC", "Files", "Exprs", "Stmts", 
		"Variable Variables", "Variable Function Calls", "Variable Method Calls", "Variable News", "Variable Properties",
		"Variable Class Constants", "Variable Static Calls", "Variable Static Targets", "Variable Static Properties", "Variable Static Property Targets",
		"All Variable Features",
		"Magic Sets", "Magic Gets", "Magic isSets", "Magic Unsets", "Magic Calls", "Magic Static Calls",
		"All Magic Methods",
		"Total Includes", "Dynamic Includes",
		"Eval", "Create Function Uses", "All Eval Features",
		"CallUserFunc", "CallUserFuncArray", "CallUserMethod", "CallUserMethodArray",
		"All Dynamic Invocations"];
	return res;
}

public str generateNumbersFile(set[str] systems) {
	str res = intercalate(",",getColumnHeaders()) + "\n";
	slocInfo = sloc();
	for (s <- sort(toList(systems)), v <- getSortedVersions(s)) {
		< lineCount, fileCount > = getOneFrom(slocInfo[s,v]);
		res = res + "<s>,<v>,<lineCount>,<fileCount>,<intercalate(",",getNumbersForSystem(readSummary(s,v)))>\n";
	}
	return res;
}

public void writeNumbersFile(set[str] systems) {
	for (s <- systems) {
		fileText = generateNumbersFile({s});
		writeFile(|project://SANER%202015/src/lang/php/experiments/saner2015/dynamic-<s>.csv|, fileText);
	}
}

private lrel[num,num] computeCoords(list[num] inputs) {
	return [ < idx, inputs[idx] > | idx <- index(inputs) ];
}

private str makeCoords(list[num] inputs, str mark="", str legend="") {
	return "\\addplot<if(size(mark)>0){>[mark=<mark>]<}> coordinates {
		   '<intercalate(" ",[ "(<i>,<j>)" | < i,j > <- computeCoords(inputs)])>
		   '};<if(size(legend)>0){>
		   '\\addlegendentry{<legend>}<}>";
}

public str varFeaturesChart(map[str,map[str,Summary]] smap, str s, str title="Variable Features", str label="fig:VarFeatures") {
	list[str] coordinateBlocks = [ ];
	coordinateBlocks += makeCoords([ smap[s][v].varFeatures.varFCall | v <- getSortedVersions(s), v in smap[s] ], mark="x", legend="Function Calls");
	coordinateBlocks += makeCoords([ smap[s][v].varFeatures.varMCall | v <- getSortedVersions(s), v in smap[s] ], mark="o", legend="Method Calls");
	coordinateBlocks += makeCoords([ smap[s][v].varFeatures.varNew | v <- getSortedVersions(s), v in smap[s] ], mark="+", legend="Object Creation");
	coordinateBlocks += makeCoords([ smap[s][v].varFeatures.varProp | v <- getSortedVersions(s), v in smap[s] ], mark="*", legend="Property Uses");

	int maxcoord(str s) {
		return max([ smap[s][v].varFeatures.varFCall | v <- getSortedVersions(s), v in smap[s] ] +
				   [ smap[s][v].varFeatures.varMCall | v <- getSortedVersions(s), v in smap[s] ] +
				   [ smap[s][v].varFeatures.varNew | v <- getSortedVersions(s), v in smap[s] ] +
				   [ smap[s][v].varFeatures.varProp | v <- getSortedVersions(s), v in smap[s] ]) + 10;
	}
		
	str res = "\\begin{figure*}[t]
			  '\\centering
			  '\\begin{tikzpicture}
			  '\\begin{axis}[width=\\textwidth,height=.34\\textheight,xlabel=Version,ylabel=Feature Count,xmin=1,ymin=0,xmax=<size(getSortedVersions(s))>,ymax=<maxcoord(s)>,legend style={at={(0,1)},anchor=north west}]
			  '<for (cb <- coordinateBlocks) {> <cb> <}>
			  '\\end{axis}
			  '\\end{tikzpicture}
			  '\\caption{<title>.\\label{<label>}} 
			  '\\end{figure*}
			  ";
	return res;	
}

public str varFeaturesScaledChart(map[str,map[str,Summary]] smap, str s, str title="Variable Features Scaled", str label="fig:VarFeaturesScaled") {
	list[str] coordinateBlocks = [ ];
	slocInfo = sloc();
	
	coordinateBlocks += makeCoords([ smap[s][v].varFeatures.varFCall * 100.0 / lineCount | v <- getSortedVersions(s), v in smap[s], < lineCount, fileCount > := getOneFrom(slocInfo[s,v]) ], mark="x", legend="Function Calls");
	coordinateBlocks += makeCoords([ smap[s][v].varFeatures.varMCall * 100.0 / lineCount | v <- getSortedVersions(s), v in smap[s], < lineCount, fileCount > := getOneFrom(slocInfo[s,v]) ], mark="o", legend="Method Calls");
	coordinateBlocks += makeCoords([ smap[s][v].varFeatures.varNew * 100.0 / lineCount | v <- getSortedVersions(s), v in smap[s], < lineCount, fileCount > := getOneFrom(slocInfo[s,v]) ], mark="+", legend="Object Creation");
	coordinateBlocks += makeCoords([ smap[s][v].varFeatures.varProp * 100.0 / lineCount | v <- getSortedVersions(s), v in smap[s], < lineCount, fileCount > := getOneFrom(slocInfo[s,v]) ], mark="*", legend="Property Uses");

	num maxcoord(str s) {
		return max([ smap[s][v].varFeatures.varFCall * 100.0 / lineCount | v <- getSortedVersions(s), v in smap[s], < lineCount, fileCount > := getOneFrom(slocInfo[s,v]) ] +
				   [ smap[s][v].varFeatures.varMCall * 100.0 / lineCount | v <- getSortedVersions(s), v in smap[s], < lineCount, fileCount > := getOneFrom(slocInfo[s,v]) ] +
				   [ smap[s][v].varFeatures.varNew * 100.0 / lineCount | v <- getSortedVersions(s), v in smap[s], < lineCount, fileCount > := getOneFrom(slocInfo[s,v]) ] +
				   [ smap[s][v].varFeatures.varProp * 100.0 / lineCount | v <- getSortedVersions(s), v in smap[s], < lineCount, fileCount > := getOneFrom(slocInfo[s,v]) ]) ;
	}
		
	str res = "\\begin{figure*}[t]
			  '\\centering
			  '\\begin{tikzpicture}
			  '\\begin{axis}[width=\\textwidth,height=.34\\textheight,xlabel=Version,ylabel=Feature Count,xmin=1,ymin=0,xmax=<size(getSortedVersions(s))>,ymax=<maxcoord(s)>,legend style={at={(0,1)},anchor=north west}]
			  '<for (cb <- coordinateBlocks) {> <cb> <}>
			  '\\end{axis}
			  '\\end{tikzpicture}
			  '\\caption{<title>.\\label{<label>}} 
			  '\\end{figure*}
			  ";
	return res;	
}

public str magicMethodsChart(map[str,map[str,Summary]] smap, str s, str title="Magic Methods", str label="fig:MagicMethods") {
	list[str] coordinateBlocks = [ ];
	coordinateBlocks += makeCoords([ smap[s][v].magicMethods.sets | v <- getSortedVersions(s), v in smap[s] ], mark="x", legend="Property Sets");
	coordinateBlocks += makeCoords([ smap[s][v].magicMethods.gets | v <- getSortedVersions(s), v in smap[s] ], mark="o", legend="Property Gets");
	coordinateBlocks += makeCoords([ smap[s][v].magicMethods.calls | v <- getSortedVersions(s), v in smap[s] ], mark="+", legend="Calls");

	int maxcoord(str s) {
		return max([ smap[s][v].magicMethods.sets | v <- getSortedVersions(s), v in smap[s] ] +
				   [ smap[s][v].magicMethods.gets | v <- getSortedVersions(s), v in smap[s] ] +
				   [ smap[s][v].magicMethods.calls | v <- getSortedVersions(s), v in smap[s] ]) + 10;
	}
		
	str res = "\\begin{figure*}[t]
			  '\\centering
			  '\\begin{tikzpicture}
			  '\\begin{axis}[width=\\textwidth,height=.34\\textheight,xlabel=Version,ylabel=Feature Count,xmin=1,ymin=0,xmax=<size(getSortedVersions(s))>,ymax=<maxcoord(s)>,legend style={at={(0,1)},anchor=north west}]
			  '<for (cb <- coordinateBlocks) {> <cb> <}>
			  '\\end{axis}
			  '\\end{tikzpicture}
			  '\\caption{<title>.\\label{<label>}} 
			  '\\end{figure*}
			  ";
	return res;	
}

public str evalsChart(map[str,map[str,Summary]] smap, str s, str title="Magic Methods", str label="fig:MagicMethods") {
	list[str] coordinateBlocks = [ ];
	coordinateBlocks += makeCoords([ smap[s][v].evalCounts.evalCount | v <- getSortedVersions(s), v in smap[s] ], mark="x", legend="eval Uses");
	coordinateBlocks += makeCoords([ smap[s][v].evalCounts.createFunctionCount | v <- getSortedVersions(s), v in smap[s] ], mark="o", legend="create\\_function Uses");

	int maxcoord(str s) {
		return max([ smap[s][v].evalCounts.evalCount | v <- getSortedVersions(s), v in smap[s] ] +
				   [ smap[s][v].evalCounts.createFunctionCount | v <- getSortedVersions(s), v in smap[s] ]) + 10;
	}
		
	str res = "\\begin{figure*}[t]
			  '\\centering
			  '\\begin{tikzpicture}
			  '\\begin{axis}[width=\\textwidth,height=.34\\textheight,xlabel=Version,ylabel=Feature Count,xmin=1,ymin=0,xmax=<size(getSortedVersions(s))>,ymax=<maxcoord(s)>,legend style={at={(0,1)},anchor=north west}]
			  '<for (cb <- coordinateBlocks) {> <cb> <}>
			  '\\end{axis}
			  '\\end{tikzpicture}
			  '\\caption{<title>.\\label{<label>}} 
			  '\\end{figure*}
			  ";
	return res;	
}

public map[str,map[str,Summary]] getSummaries(set[str] systems) {
	return ( s : ( v : readSummary(s,v) | v <- getVersions(s) ) | s <- systems );
}

public void makeCharts() {
	smap = getSummaries({"WordPress","MediaWiki"});
	writeFile(|file:///tmp/wpVar.tex|, varFeaturesChart(smap, "WordPress", title="Variable Features in WordPress", label="fig:VFWP"));
	writeFile(|file:///tmp/wpMagic.tex|, magicMethodsChart(smap, "WordPress", title="Magic Methods in WordPress", label="fig:MMWP"));
	writeFile(|file:///tmp/wpEval.tex|, evalsChart(smap, "WordPress", title="Eval Constructs in WordPress", label="fig:EvalWP"));

	writeFile(|file:///tmp/mwVar.tex|, varFeaturesChart(smap, "MediaWiki", title="Variable Features in MediaWiki", label="fig:VFMW"));
	writeFile(|file:///tmp/wpVarScaled.tex|, varFeaturesScaledChart(smap, "WordPress", title="Variable Features in WordPress, Scaled by SLOC", label="fig:VFWPScaled"));
	writeFile(|file:///tmp/mwVarScaled.tex|, varFeaturesScaledChart(smap, "MediaWiki", title="Variable Features in MediaWiki, Scaled by SLOC", label="fig:VFMWScaled"));

	writeFile(|file:///tmp/mwMagic.tex|, magicMethodsChart(smap, "MediaWiki", title="Magic Methods in MediaWiki", label="fig:MMMW"));

	writeFile(|file:///tmp/mwEval.tex|, evalsChart(smap, "MediaWiki", title="Eval Constructs in MediaWiki", label="fig:EvalMW"));
}