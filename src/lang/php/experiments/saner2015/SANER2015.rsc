module lang::php::experiments::saner2015::SANER2015

import lang::php::ast::AbstractSyntax;
import lang::php::util::System;
import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::metrics::CC;
import lang::php::stats::Stats;

import Set;
import List;
import ValueIO;
import IO;

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
			s.methods = s.methods + methodSummary(ci.name, size([st | /Stmt st := ci.body]), size([ex | /Expr ex := ci.body]), ci.modifiers, computeCC(ci.body), ci@at);
		}
		classSummaries = classSummaries + s;
	}
	
	set[Summary] interfaceSummaries = { };
	for (/InterfaceDef idef := sys) {
		Summary s = interfaceSummary(idef.interfaceName, {}, idef@at);
		for (/ClassItem ci := idef.members, ci is method) {
			s.methods = s.methods + methodSummary(ci.name, size([st | /Stmt st := ci.body]), size([ex | /Expr ex := ci.body]), ci.modifiers, computeCC(ci.body), ci@at);
		}
		interfaceSummaries = interfaceSummaries + s;
	}
	
	set[Summary] functionSummaries = { };
	for (/fdef:function(str name, _, _, list[Stmt] body) := sys) {
		Summary s = functionSummary(name, size([st | /Stmt st := body]), size([ex | /Expr ex := body]), computeCC(body), fdef@at);
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
	top20 = (reverse(sort([callCounts[cs] | cs <- callCounts])))[0..20];
	cutoff = top20[-1];
		
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
	return invocationCounts(size(invokers["call_user_func"]), size(invokers["call_user_func_array"]), size(invokers["call_user_method"]), size(invokers["call_user_method_array"]));
}

// NOTE: We are leaving this out for now...
data VarargsCounts = varargsCounts(int varArgsFunctions, int varArgsCalls);

public VarargsCounts getVarargsCounts(System sys) {
	funsToFind = { "func_get_args", "func_num_args", "func_get_arg" };
	invokers = [ < fn, e@at > | /e:call(name(name(str fn)),_) := sys, fn in funsToFind ];
	return varargsCounts(0, size(invokers));
}
