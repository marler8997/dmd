import std.typecons : Nullable, nullable;
import std.array : Appender;
import file = std.file;
import io = std.stdio;
import osmodel;

enum RESULTS_DIR = "test_results";
__gshared bool force = false;

void usage()
{
    io.writefln("Execute the dmd test suite (%s%s)", OS, MODEL);
    io.write(`
Usage:
    rdmd makefile.d [options] <targets>...
Target:
    all                 run all tests (that haven't been run)
    <directory>         run all tests in the given directory (that haven't been run)
                        i.e. runnable, compilable, fail_compilation
    <directory>/<file>  run the given individual test
                        i.e. runnable/testmain.d
    clean               remove test results and temporary files from previous runs
Options:
    -force            run all tests even if they have already ran
    -quick            run tests with only the default permuted args
    -32,-64           override the default 32/64 bit mode
`);
}
int main(string[] args)
{
    args = args[1..$];
    
    Nullable!ModelEnum overrideModel;
    {
        auto newArgsLength = 0;
        scope(exit) args.length = newArgsLength;
        for(size_t i = 0; i < args.length; i++)
        {
            auto arg = args[i];
            if(arg.length == 0 || arg[0] != '-')
            {
                args[newArgsLength++] = arg;
            }
            else if(arg == "-32")
                overrideModel = nullable(ModelEnum._32);
            else if(arg == "-64")
                overrideModel = nullable(ModelEnum._64);
            else if(arg == "-force")
                force = true;
            else
            {
                io.writefln("Error: unknown option '%s'", arg);
                return 1;
            }
        }
    }
    version(Windows)
        initOsModel(nullable(OsEnum.windows), overrideModel);
    else
        initOsModel(Nullable!OsEnum(), overrideModel);
    if(args.length == 0)
    {
        usage();
        return 0;
    }

/+

BUILD=release

ifeq (freebsd,$(OS))
    SHELL=/usr/local/bin/bash
else ifeq (netbsd,$(OS))
    SHELL=/usr/pkg/bin/bash
else
    SHELL=/bin/bash
endif
QUIET=@
export RESULTS_DIR=test_results
+/
    string REQUIRED_ARGS = "";
    string PIC_FLAGS = "";

/+
ifeq ($(findstring win,$(OS)),win)
    export ARGS=-inline -release -g -O
    export EXE=.exe
    export OBJ=.obj
    export DSEP=\\
    export SEP=$(subst /,\,/)

    PIC?=0

    DRUNTIME_PATH=..\..\druntime
    PHOBOS_PATH=..\..\phobos
    export DFLAGS=-I$(DRUNTIME_PATH)\import -I$(PHOBOS_PATH)
    export LIB=$(PHOBOS_PATH)

    # auto-tester might run the testsuite with a different $(MODEL) than DMD
    # has been compiled with. Hence we manually check which binary exists.
    # For windows the $(OS) during build is: `windows`
    ifeq (,$(wildcard ../generated/windows/$(BUILD)/64/dmd$(EXE)))
        DMD_MODEL=32
    else
        DMD_MODEL=64
    endif
    export DMD=../generated/windows/$(BUILD)/$(DMD_MODEL)/dmd$(EXE)

else
    export ARGS=-inline -release -g -O -fPIC
    export EXE=
    export OBJ=.o
    export DSEP=/
    export SEP=/

    # auto-tester might run the testsuite with a different $(MODEL) than DMD
    # has been compiled with. Hence we manually check which binary exists.
    ifeq (,$(wildcard ../generated/$(OS)/$(BUILD)/64/dmd))
        DMD_MODEL=32
    else
        DMD_MODEL=64
    endif
    export DMD=../generated/$(OS)/$(BUILD)/$(DMD_MODEL)/dmd

    # default to PIC on x86_64, use PIC=1/0 to en-/disable PIC.
    # Note that shared libraries and C files are always compiled with PIC.
    ifeq ($(PIC),)
        ifeq ($(MODEL),64) # x86_64
            PIC:=1
        else
            PIC:=0
        endif
    endif
    ifeq ($(PIC),1)
        export PIC_FLAG:=-fPIC
    else
        export PIC_FLAG:=
    endif

    DRUNTIME_PATH=../../druntime
    PHOBOS_PATH=../../phobos
    # link against shared libraries (defaults to true on supported platforms, can be overridden w/ make SHARED=0)
    SHARED=$(if $(findstring $(OS),linux freebsd),1,)
    DFLAGS=-I$(DRUNTIME_PATH)/import -I$(PHOBOS_PATH) -L-L$(PHOBOS_PATH)/generated/$(OS)/$(BUILD)/$(MODEL)
    ifeq (1,$(SHARED))
        DFLAGS+=-defaultlib=libphobos2.so -L-rpath=$(PHOBOS_PATH)/generated/$(OS)/$(BUILD)/$(MODEL)
    endif
    export DFLAGS
endif
    +/
    
    bool D_OBJC = false;
    if(OS == OsEnum.osx && MODEL == ModelEnum._64)
    {
        D_OBJC = true;
    }
    auto DEBUG_FLAGS = combineArgs(PIC_FLAGS, "-g");
    string DMD_TEST_COVERAGE = "";
    
    auto categories = [
        TestCategory("compilable"      , "*.{d,sh}"),
        TestCategory("runnable"        , "*.{d,sh}"),
        TestCategory("fail_compilation", "*.{d,html}"),
    ];

  TARGET_LOOP:
    foreach(target; args)
    {
        if(target == "all")
        {
            foreach(ref category; categories)
                category.includeAll = true;
            continue;
        }
        foreach(ref category; categories)
        {
            if(target == category.name)
            {
                category.includeAll = true;
                continue TARGET_LOOP;
            }
        }
        if(target == "clean")
        {
            assert(0, "clean target not implemented");
        }
        if(file.exists(target))
        {
            assert(0, "individual test not implemented");
        }
    }

    foreach(const category; categories)
    {
        if(category.includeAll)
        {
            category.runTestsThatNeedIt();
        }
        if(category.tests.data.length > 0)
        {
            assert(0, "not implemented");
        }
    }

    
/+

runnable_tests=$(wildcard runnable/*.d) $(wildcard runnable/*.sh)
runnable_test_results=$(addsuffix .out,$(addprefix $(RESULTS_DIR)/,$(runnable_tests)))

compilable_tests=$(wildcard compilable/*.d) $(wildcard compilable/*.sh)
compilable_test_results=$(addsuffix .out,$(addprefix $(RESULTS_DIR)/,$(compilable_tests)))

fail_compilation_tests=$(wildcard fail_compilation/*.d) $(wildcard fail_compilation/*.html)
fail_compilation_test_results=$(addsuffix .out,$(addprefix $(RESULTS_DIR)/,$(fail_compilation_tests)))

all: run_tests

$(RESULTS_DIR)/runnable/%.d.out: runnable/%.d $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) $(RESULTS_DIR)/d_do_test $(<D) $* d

$(RESULTS_DIR)/runnable/%.sh.out: runnable/%.sh $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) echo " ... $(<D)/$*.sh"
	$(QUIET) ./$(<D)/$*.sh

$(RESULTS_DIR)/compilable/%.d.out: compilable/%.d $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) $(RESULTS_DIR)/d_do_test $(<D) $* d

$(RESULTS_DIR)/compilable/%.sh.out: compilable/%.sh $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) echo " ... $(<D)/$*.sh"
	$(QUIET) ./$(<D)/$*.sh

$(RESULTS_DIR)/fail_compilation/%.d.out: fail_compilation/%.d $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) $(RESULTS_DIR)/d_do_test $(<D) $* d

$(RESULTS_DIR)/fail_compilation/%.html.out: fail_compilation/%.html $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) $(RESULTS_DIR)/d_do_test $(<D) $* html

quick:
	$(MAKE) ARGS="" run_tests

clean:
	@echo "Removing output directory: $(RESULTS_DIR)"
	$(QUIET)if [ -e $(RESULTS_DIR) ]; then rm -rf $(RESULTS_DIR); fi

$(RESULTS_DIR)/.created:
	@echo Creating output directory: $(RESULTS_DIR)
	$(QUIET)if [ ! -d $(RESULTS_DIR) ]; then mkdir $(RESULTS_DIR); fi
	$(QUIET)if [ ! -d $(RESULTS_DIR)/runnable ]; then mkdir $(RESULTS_DIR)/runnable; fi
	$(QUIET)if [ ! -d $(RESULTS_DIR)/compilable ]; then mkdir $(RESULTS_DIR)/compilable; fi
	$(QUIET)if [ ! -d $(RESULTS_DIR)/fail_compilation ]; then mkdir $(RESULTS_DIR)/fail_compilation; fi
	$(QUIET)touch $(RESULTS_DIR)/.created

run_tests: start_runnable_tests start_compilable_tests start_fail_compilation_tests

run_runnable_tests: $(runnable_test_results)

start_runnable_tests: $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE)
	@echo "Running runnable tests"
	$(QUIET)$(MAKE) --no-print-directory run_runnable_tests

run_compilable_tests: $(compilable_test_results)

start_compilable_tests: $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE)
	@echo "Running compilable tests"
	$(QUIET)$(MAKE) --no-print-directory run_compilable_tests

run_fail_compilation_tests: $(fail_compilation_test_results)

start_fail_compilation_tests: $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE)
	@echo "Running fail compilation tests"
	$(QUIET)$(MAKE) --no-print-directory run_fail_compilation_tests

$(RESULTS_DIR)/d_do_test$(EXE): d_do_test.d $(RESULTS_DIR)/.created
	@echo "Building d_do_test tool"
	@echo "OS: '$(OS)'"
	@echo "MODEL: '$(MODEL)'"
	@echo "PIC: '$(PIC_FLAG)'"
	$(DMD) -conf= $(MODEL_FLAG) $(DEBUG_FLAGS) -unittest -run d_do_test.d -unittest
	$(DMD) -conf= $(MODEL_FLAG) $(DEBUG_FLAGS) -od$(RESULTS_DIR) -of$(RESULTS_DIR)$(DSEP)d_do_test$(EXE) d_do_test.d
+/
    return 0;
}

string combineArgs(string left, string right)
{
    if(left.length == 0)
        return right;
    if(right.length == 0)
        return left;
    return left ~ " " ~ right;
}

/+
In-test variables
-----------------
COMPILE_SEPARATELY:  if present, forces each .d file to compile separately and linked
                     together in an extra setp.
                     default: (none, aka compile/link all in one step)

EXECUTE_ARGS:        parameters to add to the execution of the test
                     default: (none)

EXTRA_SOURCES:       list of extra files to build and link along with the test
                     default: (none)

EXTRA_OBJC_SOURCES:  list of extra Objective-C files to build and link along with the test
                     default: (none). Test files with this variable will be ignored unless
                     the D_OBJC environment variable is set to "1"

PERMUTE_ARGS:        the set of arguments to permute in multiple $(DMD) invocations.
                     An empty set means only one permutation with no arguments.
                     default: the make variable ARGS (see below)

TEST_OUTPUT:         the output is expected from the compilation (if the
                     output of the compilation doesn't match, the test
                     fails). You can use the this format for multi-line
                     output:
                     TEST_OUTPUT:
                     ---
                     Some
                     Output
                     ---

POST_SCRIPT:         name of script to execute after test run
                     note: arguments to the script may be included after the name.
                           additionally, the name of the file that contains the output
                           of the compile/link/run steps is added as the last parameter.
                     default: (none)

REQUIRED_ARGS:       arguments to add to the $(DMD) command line
                     default: (none)
                     note: the make variable REQUIRED_ARGS is also added to the $(DMD)
                           command line (see below)

DISABLED:            text describing why the test is disabled (if empty, the test is
                     considered to be enabled).
                     default: (none, enabled)
+/


struct TestCategory
{
    string name;
    string testFilePattern;
    bool includeAll;
    Appender!(string[]) tests;
    void runTestsThatNeedIt() const
    {
        io.writefln("Running %s tests", name);
        /*
start_runnable_tests: $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE)
	@echo "Running runnable tests"
	$(QUIET)$(MAKE) --no-print-directory run_runnable_tests
    
    
runnable_tests=$(wildcard runnable/*.d) $(wildcard runnable/*.sh)
runnable_test_results=$(addsuffix .out,$(addprefix $(RESULTS_DIR)/,$(runnable_tests)))

*/
        if(!file.exists(RESULTS_DIR))
        {
            io.writefln("mkdir %s", RESULTS_DIR);
            file.mkdir(RESULTS_DIR);
        }

        foreach(testEntry; file.dirEntries(name, testFilePattern, file.SpanMode.shallow))
        {
            io.writefln("%s", testEntry.name);
            auto resultsFile = buildPath(RESULTS_DIR, testEntry.name ~ ".out");
            if(testEntry.name.newerThan(resultsFile))
            {
                
            }
        }
    }
}
/*
$(RESULTS_DIR)/runnable/%.d.out: runnable/%.d $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) $(RESULTS_DIR)/d_do_test $(<D) $* d

$(RESULTS_DIR)/runnable/%.sh.out: runnable/%.sh $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) echo " ... $(<D)/$*.sh"
	$(QUIET) ./$(<D)/$*.sh

$(RESULTS_DIR)/compilable/%.d.out: compilable/%.d $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) $(RESULTS_DIR)/d_do_test $(<D) $* d

$(RESULTS_DIR)/compilable/%.sh.out: compilable/%.sh $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) echo " ... $(<D)/$*.sh"
	$(QUIET) ./$(<D)/$*.sh

$(RESULTS_DIR)/fail_compilation/%.d.out: fail_compilation/%.d $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) $(RESULTS_DIR)/d_do_test $(<D) $* d

$(RESULTS_DIR)/fail_compilation/%.html.out: fail_compilation/%.html $(RESULTS_DIR)/.created $(RESULTS_DIR)/d_do_test$(EXE) $(DMD)
	$(QUIET) $(RESULTS_DIR)/d_do_test $(<D) $* html
*/

/*
If force is true, returns true. Otherwise, if source and target both
exist, returns true iff source's timeLastModified is strictly greater
than target's. Otherwise, returns true.
 */
private bool newerThan(string source, string target)
{
    if (force) return true;
    //yap("stat ", target);
    return source.newerThan(target.timeLastModified(SysTime.min));
}