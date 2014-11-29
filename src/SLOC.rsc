@generated
module SLOC
import lang::csv::IO;

alias slocType = rel[str \Product,str \Version,int \LoC,int \Files];

public slocType sloc() {
   return readCSV(#rel[str \Product,str \Version,int \LoC,int \Files], |rascal://src/lang/php/extract/csvs/linesOfCode.csv?funname=sloc|, ());
}
