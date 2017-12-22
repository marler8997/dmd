import core.stdc.stdlib : exit;

//pragma(importPath, "../src");

import std.format : format;
static import std.file;
import std.file : dirEntries, SpanMode, exists;
import std.path : buildPath, dirName, baseName, stripExtension, extension;
import std.stdio;
import std.process : spawnShell, environment;

import makelib;
import util;

auto requiredEnv(in char[] name)
{
    auto result = environment.get(name, null);
    if(result is null)
    {
        writefln("Error: missing environment variable '%s'", name);
        exit(1);
    }
    return result;
}

enum testResultsDir = "test_results";

void setEnvIfNotSet(string name, lazy string value)
{
    if(environment.get(name, null) is null)
    {
        writefln("%s=%s", name, value);
        environment[name] = value;
    }
}

void mkdir(in char[] dir)
{
    writefln("mkdir '%s'", dir);
    std.file.mkdir(dir);
}

int main(string[] args)
{
    // Set Environment Variables to pass to d_do_test.exe
    environment["RESULTS_DIR"] = testResultsDir;
    version(Windows)
    {
        enum defaultDruntimePath = `..\..\druntime`;
        enum defaultPhobosPath   = `..\..\phobos`;

        enum os = "windows";
        setEnvIfNotSet("SEP", "\\");
        setEnvIfNotSet("OBJ", ".obj");
    }
    else
    {
        enum defaultDruntimePath = `../../druntime`;
        enum defaultPhobosPath   = `../../phobos`;

        auto os = requiredEnv("OS");
        setEnvIfNotSet("SEP", "/");
        setEnvIfNotSet("OBJ", ".o");
    }
    setEnvIfNotSet("EXE", exeExtension);
    setEnvIfNotSet("MODEL", "32");
    auto model = environment.get("DMD_MODEL", "32");

    auto phobosPath = environment.get("PHOBOS_PATH", defaultPhobosPath);

    {
        string dflags;
        dflags ~= " -I" ~ buildPath(environment.get("DRUNTIME_PATH", defaultDruntimePath), "import");
        dflags ~= " -I" ~ phobosPath;
        version(Windows)
        {
            dflags ~= " -L+" ~ phobosPath ~ "\\";
        }
        setEnvIfNotSet("DFLAGS", dflags);
    }

    string dmd = environment.get("DMD", null);
    if(dmd is null)
    {
        dmd = buildPath("..", "generated", os,
            environment.get("BUILD", "release"), model, "dmd" ~ exeExtension);
        environment["DMD"] = dmd;
    }

    FileSystemMakeEngine make;

    auto d_do_test = buildPath(testResultsDir, "d_do_test" ~ exeExtension);
    make.rule()
        .target(d_do_test)
        .depend("d_do_test.d")
        .action(delegate(Item target, Target[] ruleTargets, Item[] dependencies)
        {
            writefln("Building %s", target.getName);
            writefln("OS: %s", os);
            writefln("MODEL: %s", model);
            //@echo "PIC: '$(PIC_FLAG)'"

            if(!exists(testResultsDir))
            {
                mkdir(testResultsDir);
                mkdir(buildPath(testResultsDir, "runnable"));
                mkdir(buildPath(testResultsDir, "compilable"));
                mkdir(buildPath(testResultsDir, "fail_compilation"));
            }

            //$(DMD) -conf= $(MODEL_FLAG) $(DEBUG_FLAGS) -unittest -run d_do_test.d -unittest
            //$(DMD) -conf= $(MODEL_FLAG) $(DEBUG_FLAGS) -od$(RESULTS_DIR) -of$(RESULTS_DIR)$(DSEP)d_do_test$(EXE) d_do_test.d
            //run("set");
            run(dmd ~ " -conf= -g -debug -unittest -run d_do_test.d -unittest");
            run(dmd ~ " -conf= -g -debug -od" ~ testResultsDir ~ " -of" ~ target.getName ~ " d_do_test.d");
        })
        ;

    enum test_compilable       = "test_compilable";
    enum test_runnable         = "test_runnable";
    enum test_fail_compilation = "test_fail_compilation";

    make.rule()
        .target(test_compilable)
        .depend(d_do_test)
        .depend(customItemRange(TestItemRange("compilable", "*.{d,sh}")))
        ;
    make.rule()
        .target(test_runnable)
        .depend(d_do_test)
        .depend(customItemRange(TestItemRange("runnable", "*.{d,sh}")))
        ;
    make.rule()
        .target(test_fail_compilation)
        .depend(d_do_test)
        .depend(customItemRange(TestItemRange("fail_compilation", "*.{d,html}")))
        ;
    make.rule()
        .target(buildPath(testResultsDir, "$testDir", "$testName.d.out"))
        .depend(d_do_test)
        .depend(buildPath("$testDir", "$testName.d"))
        .action(delegate(Item target, Target[] ruleTargets, Item[] dependencies)
        {
            auto testDir = baseName(dirName(target.getName));
            auto targetBaseName = baseName(target.getName);
            auto testBaseName = targetBaseName[0..$-4]; // remove ".out"
            run(d_do_test ~ " " ~ testDir ~ " " ~
                testBaseName.stripExtension() ~ " " ~ testBaseName.extension()[1..$]);
        })
        ;
    make.rule()
        .target(buildPath(testResultsDir, "$testDir", "$testName.sh.out"))
        .depend(d_do_test)
        .depend(buildPath("$testDir", "$testName.sh"))
        .action(delegate(Item target, Target[] ruleTargets, Item[] dependencies)
        {
            auto testDir = baseName(dirName(target.getName));
            auto targetBaseName = baseName(target.getName);
            auto testBaseName = targetBaseName[0..$-4]; // remove ".out"
            writefln(" ... %s/%s", testDir, testBaseName);
            version(Windows)
            {
                writefln(".sh files not supported on windows!");
                auto file = File(target.getName, "wb");
                scope(exit) file.close();
                file.write(".sh files not supported on windows");
            }
            else
            {
                run(format("./%s/%s", testDir, testBaseName));
            }
        })
        ;
    enum test_all = "test_all";
    make.rule()
        .target(test_all)
        .depend(test_compilable)
        .depend(test_runnable)
        .depend(test_fail_compilation)
        ;

    args = args[1..$];
    string target;
    if(args.length == 0)
    {
        target = test_all; // default target
    }
    else if(args.length == 1)
    {
        target = args[0];
    }
    else
    {
        writeln("Error: expecetd 1 target");
        make.dumpTargets();
        return 1;
    }

    //make.verbose = true;
    //make.dumpRules();
    make.make(target);
    return 0;
}

struct TestItemRange
{
    alias RangeType = Range;

    string testDir;
    string testFilePattern;
    void initRange(RangeType* range)
    {
        import std.conv : emplace;
        emplace(range, testDir, testFilePattern);
    }

    static struct Range
    {
        alias DirIteratorType = typeof(dirEntries("","", SpanMode.shallow));

        DirIteratorType iterator;
        this(string testDir, string testFilePattern)
        {
            this.iterator = dirEntries(testDir, testFilePattern, SpanMode.shallow);
        }
        @property bool empty() { return iterator.empty(); }
        auto front()
        {
            return Item.getGlobalItem(buildPath(testResultsDir, iterator.front ~ ".out"));
        }
        void popFront() {iterator.popFront(); }
    }
}