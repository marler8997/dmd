import std.stdio   : writeln, writefln;
import dmakelib;
import osmodel;

immutable DEFAULT_BIT_MODE = 32;

void usage()
{
    writeln ("Usage: make.d [options] [target]");
    writeln ("  -h             show this help");
    writefln("  -32 | -64      compile in 32/64 bit mode (default=%s)", DEFAULT_BIT_MODE);
}
int main(string[] args)
{
    loadCommandLineVars(&args);

    bool help = false;
    ushort selectBitMode = ushort.max;
    {
        auto nonOptionCount = 0;
        for(auto i = 1; i < args.length; i++)
        {
            if(args[i].length == 0 || args[i][0] != '-')
            {
                args[nonOptionCount++] = args[i];
            }
            else if(args[i] == "-32")
            {
                selectBitMode = 32;
            }
            else if(args[i] == "-64")
            {
                selectBitMode = 64;
            }
            else if(args[i] == "-h")
            {
                help = true;
            }
            else
            {
                writefln("Error: unknown option \"%s\"", args[i]);
                return 1; // fail
            }
        }
        args = args[0..1+nonOptionCount];
    }
    if(help)
    {
        usage();
        return 0;
    }

    makeOptions.logSymbolOverrides = true;

    //putMakefile("win32.mak");

    declare("DM_HOME", path("../../../.."));

    OsModel osModel = getOsModel();
    declare("OS", osModel.os);
    declare("MODEL", osModel.model);

    declare("DMCROOT", path("$(DM_HOME)/dm"));

    // declare allows the makefile to declare a variable type and give
    // it a default value.  If the value of the variable is already set via
    // environment variable/command line/make code, then this will just update
    // the type.
    declare("DCOMPILER", program("dmd"));
    declare("CCOMPILER", program("dmc"));
    // Librarian
    declare("LIB", program("lib"));

    // D Optimizer flags
    declare("DOPT", "");
    // Custom compile flags for all modules
    declare("OPT", "");
    // Debug flags
    declare("DEBUG", "-gl -D -DUNITTEST");
    // D Debug flags
    declare("DDEBUG", "-debug -g -unittest");
    // Linker flags (prefix with -L)
    declare("LFLAGS", "");

    declare("OBJ_MSVC", "");


    /*
    define("INCLUDE_DIRS", list(
        path("$(ROOT)"),
        path("$(DMCROOT)/include")));
    */
    define("INCLUDE", "$(ROOT_DIR);$(DMCROOT)\\include");

    declare("CFLAGS", "-I$(INCLUDE) $(OPT) $(DEBUG) -cpp -DTARGET_WINDOS=1 -DDM_TARGET_CPU_X86=1");
    // Compile flags for modules with backend/toolkit dependencies
    declare("MFLAGS", "-I$(BACKEND_DIR);$(TK_DIR) $(OPT) -DMARS -cpp $(DEBUG) -e -wx -DTARGET_WINDOS=1 -DDM_TARGET_CPU_X86=1");

    version(Windows)
        define("FINAL_COMPILER_TARGET", program("dmd.exe"));
    else
        define("FINAL_COMPILER_TARGET", program("dmd"));

    define("DDMD_DIR"   , path("ddmd"));
    define("BACKEND_DIR", path("$(DDMD_DIR)/backend"));
    define("TK_DIR"     , path("$(DDMD_DIR)/tk"));
    define("ROOT_DIR"   , path("$(DDMD_DIR)/root"));

    define("GEN_DIR", path("../generated"));
    define("G"      , path("$(GEN_DIR)/$(OS)$(MODEL)"));

    define("IDGEN_OUTPUTS", list(
        file("$(DDMD_DIR)/id.d"),
        file("$(DDMD_DIR)/id.h")));

    define("FRONT_SRCS", list(
        file("$(DDMD_DIR)/access.d"),
        file("$(DDMD_DIR)/aggregate.d"),
        file("$(DDMD_DIR)/aliasthis.d"),
        file("$(DDMD_DIR)/apply.d"),
        file("$(DDMD_DIR)/argtypes.d"),
        file("$(DDMD_DIR)/arrayop.d"),
        file("$(DDMD_DIR)/arraytypes.d"),
        file("$(DDMD_DIR)/astcodegen.d"),
        file("$(DDMD_DIR)/astnull.d"),
        file("$(DDMD_DIR)/attrib.d"),
        file("$(DDMD_DIR)/builtin.d"),
        file("$(DDMD_DIR)/canthrow.d"),
        file("$(DDMD_DIR)/clone.d"),
        file("$(DDMD_DIR)/complex.d"),
        file("$(DDMD_DIR)/cond.d"),
        file("$(DDMD_DIR)/constfold.d"),
        file("$(DDMD_DIR)/cppmangle.d"),
        file("$(DDMD_DIR)/ctfeexpr.d"),
        file("$(DDMD_DIR)/dcast.d"),
        file("$(DDMD_DIR)/dclass.d"),
        file("$(DDMD_DIR)/declaration.d"),
        file("$(DDMD_DIR)/delegatize.d"),
        file("$(DDMD_DIR)/denum.d"),
        file("$(DDMD_DIR)/dimport.d"),
        file("$(DDMD_DIR)/dinifile.d"),
        file("$(DDMD_DIR)/dinterpret.d"),
        file("$(DDMD_DIR)/dmacro.d"),
        file("$(DDMD_DIR)/dmangle.d"),
        file("$(DDMD_DIR)/dmodule.d"),
        file("$(DDMD_DIR)/doc.d"),
        file("$(DDMD_DIR)/dscope.d"),
        file("$(DDMD_DIR)/dstruct.d"),
        file("$(DDMD_DIR)/dsymbol.d"),
        file("$(DDMD_DIR)/dtemplate.d"),
        file("$(DDMD_DIR)/dversion.d"),
        file("$(DDMD_DIR)/escape.d"),
        file("$(DDMD_DIR)/expression.d"),
        file("$(DDMD_DIR)/func.d"),
        file("$(DDMD_DIR)/hdrgen.d"),
        file("$(DDMD_DIR)/imphint.d"),
        file("$(DDMD_DIR)/impcnvtab.d"),
        file("$(DDMD_DIR)/init.d"),
        file("$(DDMD_DIR)/inline.d"),
        file("$(DDMD_DIR)/inlinecost.d"),
        file("$(DDMD_DIR)/intrange.d"),
        file("$(DDMD_DIR)/json.d"),
        file("$(DDMD_DIR)/lib.d"),
        file("$(DDMD_DIR)/link.d"),
        file("$(DDMD_DIR)/mars.d"),
        file("$(DDMD_DIR)/mtype.d"),
        file("$(DDMD_DIR)/nogc.d"),
        file("$(DDMD_DIR)/nspace.d"),
        file("$(DDMD_DIR)/objc.d"),
        file("$(DDMD_DIR)/opover.d"),
        file("$(DDMD_DIR)/optimize.d"),
        file("$(DDMD_DIR)/parse.d"),
        file("$(DDMD_DIR)/sapply.d"),
        file("$(DDMD_DIR)/sideeffect.d"),
        file("$(DDMD_DIR)/statement.d"),
        file("$(DDMD_DIR)/staticassert.d"),
        file("$(DDMD_DIR)/target.d"),
        file("$(DDMD_DIR)/safe.d"),
        file("$(DDMD_DIR)/asttypename.d"),
        file("$(DDMD_DIR)/traits.d"),
        file("$(DDMD_DIR)/utils.d"),
        file("$(DDMD_DIR)/visitor.d"),
        file("$(DDMD_DIR)/libomf.d"),
        file("$(DDMD_DIR)/scanomf.d"),
        file("$(DDMD_DIR)/typinf.d"),
        file("$(DDMD_DIR)/libmscoff.d"),
        file("$(DDMD_DIR)/scanmscoff.d"),
        file("$(DDMD_DIR)/statement_rewrite_walker.d"),
        file("$(DDMD_DIR)/statementsem.d"),
        file("$(DDMD_DIR)/staticcond.d")
    ));

    define("LEXER_SRCS", list(
        file("$(DDMD_DIR)/entity.d"),
        file("$(DDMD_DIR)/errors.d"),
        file("$(DDMD_DIR)/globals.d"),
        file("$(DDMD_DIR)/id.d"),
        file("$(DDMD_DIR)/identifier.d"),
        file("$(DDMD_DIR)/lexer.d"),
        file("$(DDMD_DIR)/tokens.d"),
        file("$(DDMD_DIR)/utf.d")
    ));
    define("LEXER_ROOT", list(
        file("$(DDMD_DIR)/array.d"),
        file("$(DDMD_DIR)/ctfloat.d"),
        file("$(DDMD_DIR)/file.d"),
        file("$(DDMD_DIR)/filename.d"),
        file("$(DDMD_DIR)/outbuffer.d"),
        file("$(DDMD_DIR)/port.d"),
        file("$(DDMD_DIR)/rmem.d"),
        file("$(DDMD_DIR)/rootobject.d"),
        file("$(DDMD_DIR)/stringtable.d"),
        file("$(DDMD_DIR)/hash.d")
    ));
    define("ROOT_SRCS", list(
        file("$(ROOT_DIR)/aav.d"),
        file("$(ROOT_DIR)/array.d"),
        file("$(ROOT_DIR)/ctfloat.d"),
        file("$(ROOT_DIR)/file.d"),
        file("$(ROOT_DIR)/filename.d"),
        file("$(ROOT_DIR)/man.d"),
        file("$(ROOT_DIR)/outbuffer.d"),
        file("$(ROOT_DIR)/port.d"),
        file("$(ROOT_DIR)/response.d"),
        file("$(ROOT_DIR)/rmem.d"),
        file("$(ROOT_DIR)/rootobject.d"),
        file("$(ROOT_DIR)/speller.d"),
        file("$(ROOT_DIR)/stringtable.d"),
        file("$(ROOT_DIR)/hash.d")));

    // D backend
    define("GBACKOBJ", list(file("$G/go.obj"),
        file("$G/gdag.obj"),
        file("$G/gother.obj"),
        file("$G/gflow.obj"),
        file("$G/gloop.obj"),
        file("$G/var.obj"),
        file("$G/el.obj"),
        file("$G/newman.obj"),
        file("$G/glocal.obj"),
        file("$G/os.obj"),
        file("$G/nteh.obj"),
        file("$G/evalu8.obj"),
        file("$G/cgcs.obj"),
        file("$G/rtlsym.obj"),
        file("$G/cgelem.obj"),
        file("$G/cgen.obj"),
        file("$G/cgreg.obj"),
        file("$G/out.obj"),
        file("$G/blockopt.obj"),
        file("$G/cgobj.obj"),
        file("$G/cg.obj"),
        file("$G/cgcv.obj"),
        file("$G/type.obj"),
        file("$G/dt.obj"),
        file("$G/debug.obj"),
        file("$G/code.obj"),
        file("$G/cg87.obj"),
        file("$G/cgxmm.obj"),
        file("$G/cgsched.obj"),
        file("$G/ee.obj"),
        file("$G/csymbol.obj"),
        file("$G/cgcod.obj"),
        file("$G/cod1.obj"),
        file("$G/cod2.obj"),
        file("$G/cod3.obj"),
        file("$G/cod4.obj"),
        file("$G/cod5.obj"),
        file("$G/outbuf.obj"),
        file("$G/bcomplex.obj"),
        file("$G/ptrntab.obj"),
        file("$G/aa.obj"),
        file("$G/ti_achar.obj"),
        file("$G/md5.obj"),
        file("$G/ti_pvoid.obj"),
        file("$G/mscoffobj.obj"),
        file("$G/pdata.obj"),
        file("$G/cv8.obj"),
        file("$G/backconfig.obj"),
        file("$G/divcoeff.obj"),
        file("$G/dwarf.obj"),
        file("$G/compress.obj"),
        file("$G/varstats.obj"),
        file("$G/ph2.obj"),
        file("$G/util2.obj"),
        file("$G/tk.obj"),
        file("$G/gsroa.obj")
    ));

    define("DMD_LIBS", list(
        file("$G/backend.lib"),
        file("$G/lexer.lib")));

    define("STRING_IMPORT_FILES", list(
        file("$G/verstr.h"),
        file("../res/default_ddoc_theme.ddoc")));

    define("DMD_SRCS", list(
        getSymbol("FRONT_SRCS"),
/*        "$(FRONT_SRCS) $(GLUE_SRCS) $(BACK_HDRS) $(TK_HDRS)*/
    ));

    // D compiler flags
    define("DMODEL", "-m$(MODEL)");
    define("DFLAGS", "$(DOPT) $(DMODEL) $(DDEBUG) -wi -version=MARS");

    addRule(file("$G/backend.lib"), list(var("$(GBACKOBJ)"), var("$(OBJ_MSVC)")), [
        shell("$(LIB) -p512 -n -c $@ $(GBACKOBJ) $(OBJ_MSVC)"),
    ]);

    /*
    addRule(file("$G/%.obj"), file("$C/%.c"), [
        shell("$(CCOMPILER) -c -o$@ $(MFLAGS) $G/%.c"),
    ]);
    */

    putCode(__LINE__,`
defaulttarget: $G debdmd

$G:
    if not exist "$G" mkdir "$G"

debdmd:
    dmake "OPT=" "DEBUG=-D -g -DUNITTEST" "DDEBUG=-debug -g -unittest" "DOPT=" "LFLAGS=-L/ma/co/la" $(FINAL_COMPILER_TARGET)

clean:
    if exist "$G" rmdir /s /q "$G"

$(FINAL_COMPILER_TARGET): $(DMD_SRCS) $(ROOT_SRCS) $G/newdelete.obj $(DMD_LIBS) $(STRING_IMPORT_FILES)
    $(DCOMPILER) -of$(FINAL_COMPILER_TARGET) -vtls -J$G -J../res -L/STACK:8388608 $(DFLAGS) $(LFLAGS) $(DMD_SRCS) $(ROOT_SRCS) $G/newdelete.obj $(DMD_LIBS)
    copy $(FINAL_COMPILER_TARGET) .

$G/newdelete.obj : $(ROOT_DIR)/newdelete.c
    $(CCOMPILER) -c -o$@ $(CFLAGS) $(ROOT_DIR)\newdelete.c


#$G/backend.lib: $(GBACKOBJ) $(OBJ_MSVC)
#    $(LIB) -p512 -n -c $@ $(GBACKOBJ) $(OBJ_MSVC)

$G/lexer.lib: $(LEXER_SRCS) $(LEXER_ROOT) $(STRING_IMPORT_FILES)
    $(DCOMPILER) -of$@ -vtls -lib -J$G $(DFLAGS) $(LEXER_SRCS) $(LEXER_ROOT)

$G/go.obj: $(BACKEND_DIR)/go.c
    $(CCOMPILER) -c -o$@ $(MFLAGS) $(BACKEND_DIR)\go


    `);



    //dump();
    return runTargets(args[1..$]);
}
