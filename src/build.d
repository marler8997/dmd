#!/usr/bin/env rdmd
/**
DMD builder

Usage:
  ./build.d dmd

detab, tolf, install targets - require the D Language Tools (detab.exe, tolf.exe)
  https://github.com/dlang/tools.

zip target - requires Info-ZIP or equivalent (zip32.exe)
  http://www.info-zip.org/Zip.html#Downloads

TODO:
- add all posix.mak Makefile targets
- support 32-bit builds
- test the script with LDC or GDC as host compiler
*/

version(CoreDdoc) {} else:

import std.algorithm, std.conv, std.datetime, std.exception, std.file, std.format, std.functional,
       std.getopt, std.path, std.process, std.range, std.stdio, std.string, std.traits;

import std.parallelism : totalCPUs;

const thisBuildScript = __FILE_FULL_PATH__.buildNormalizedPath;
const srcDir = thisBuildScript.dirName;
const dmdRepo = srcDir.dirName;
shared bool verbose; // output verbose logging
shared bool force; // always build everything (ignores timestamp checking)
shared bool dryRun; /// dont execute targets, just print command to be executed

__gshared string[string] env;
__gshared string[][string] flags;
__gshared typeof(sourceFiles()) sources;
__gshared Scheduler!Dependency scheduler = void;

/// Array of dependencies through which all other dependencies can be reached
immutable rootDeps = [
    &dmdDefault,
    &autoTesterBuild,
    &runDmdUnittest,
    &clean,
    &checkwhitespace,
    &runCxxUnittest,
    &detab,
    &tolf,
    &zip,
    &html,
    &toolchainInfo,
    &style,
    &man,
    &testDeps,
];
alias testDeps = makeDep!((testBuilder, testDep) {
    import core.thread;
    static Dependency[] makeSet(string names, Dependency[] deps)
    {
        return names.split().map!(e =>
            methodInit!(Dependency, (b, d) => b
                .name(e)
                .msg("Building " ~ e)
                .deps(deps)
                .commandFunction(() { Thread.sleep(dur!"seconds"(1)); })
            )
        ).array;
    }
    auto set0 = makeSet("0a 0b 0c 0d", null);
    auto set1a = makeSet("1a 1b", set0);
    auto set1b = makeSet("1c 1d", set0);
    //auto set1c = makeSet("1c", set0);
    //auto set1d = makeSet("1d", set0);
    /*
    auto set2a = makeSet("2a", set1a);
    auto set2b = makeSet("2b", set1b);
    auto set2c = makeSet("2c 2d", set1c);
    */

    testBuilder
    .name("testdeps")
    //.deps(set2a ~ set2b ~ set2c)
    .deps(set1a ~ set1b)// ~ set1c ~ set1d)
    ;
});

int main(string[] args)
{
    try
    {
        runMain(args);
        return 0;
    }
    catch (BuildException e)
    {
        writeln(e.msg);
        return 1;
    }
}

void runMain(string[] args)
{
    int jobs = totalCPUs;
    bool calledFromMake = false;
    auto res = getopt(args,
        "j|jobs", "Specifies the number of jobs (commands) to run simultaneously (default: %d)".format(totalCPUs), &jobs,
        "v|verbose", "Verbose command output", (cast(bool*) &verbose),
        "f|force", "Force run (ignore timestamps and always run all tests)", (cast(bool*) &force),
        "d|dry-run", "Print commands instead of executing them", (cast(bool*) &dryRun),
        "called-from-make", "Calling the build script from the Makefile", &calledFromMake
    );
    void showHelp()
    {
        defaultGetoptPrinter(`./build.d <targets>...

Examples
--------

    ./build.d dmd           # build DMD
    ./build.d unittest      # runs internal unittests
    ./build.d clean         # remove all generated files
    ./build.d generated/linux/release/64/dmd.conf

Important variables:
--------------------

HOST_DMD:             Host D compiler to use for bootstrapping
AUTO_BOOTSTRAP:       Enable auto-boostrapping by downloading a stable DMD binary
MODEL:                Target architecture to build for (32,64) - defaults to the host architecture

Build modes:
------------
BUILD: release (default) | debug (enabled a build with debug instructions)

Opt-in build features:

ENABLE_RELEASE:       Optimized release built
ENABLE_DEBUG:         Add debug instructions and symbols (set if ENABLE_RELEASE isn't set)
ENABLE_LTO:           Enable link-time optimizations
ENABLE_UNITTEST:      Build dmd with unittests (sets ENABLE_COVERAGE=1)
ENABLE_PROFILE:       Build dmd with a profiling recorder (D)
ENABLE_COVERAGE       Build dmd with coverage counting
ENABLE_SANITIZERS     Build dmd with sanitizer (e.g. ENABLE_SANITIZERS=address,undefined)

Targets
-------
` ~ targetsHelp ~ `
The generated files will be in generated/$(OS)/$(BUILD)/$(MODEL) (` ~ env["G"] ~ `)

Command-line parameters
-----------------------
`, res.options);
        return;
    }

    // parse arguments
    args.popFront;
    args2Environment(args);
    parseEnvironment;
    processEnvironment;
    processEnvironmentCxx;
    sources = sourceFiles;

    if (res.helpWanted)
        return showHelp;

    // default target
    if (!args.length)
        args = ["dmd"];

    auto targets = predefinedTargets(args); // preprocess

    if (targets.length == 0)
        return showHelp;

    if (verbose)
    {
        log("================================================================================");
        foreach (key, value; env)
            log("%s=%s", key, value);
        log("================================================================================");
    }
    {
        File lockFile;
        if (calledFromMake)
        {
            // If called from make, use an interprocess lock so that parallel builds don't stomp on each other
            lockFile = File(env["GENERATED"].buildPath("build.lock"), "w");
            lockFile.lock();
        }
        scope (exit)
        {
            if (calledFromMake)
            {
                lockFile.unlock();
                lockFile.close();
            }
        }

        // workaround issue https://issues.dlang.org/show_bug.cgi?id=13727
        version (CRuntime_DigitalMars)
        {
            pragma(msg, "Warning: Parallel builds disabled because of Issue 13727!");
            jobs = 1; // Fall back to a sequential build
        }
        else version (OSX)
        {
            // FIXME: Parallel executions hangs reliably on Mac  (esp. the 'macair'
            // host used by the autotester) for unknown reasons outside of this script.
            // Disable parallel execution until this issue has been resolved.
            jobs = 2;
        }

        if (jobs <= 0)
            abortBuild("Invalid number of jobs: %d".format(jobs));

        scheduler.init(jobs);
        Dependency.build(targets);
    }

    writeln("Success");
}

/// Generate list of targets for use in the help message
string targetsHelp()
{
    string result = "";
    foreach (dep; DependencyRange(rootDeps.map!(a => a()).array))
    {
        if (dep.name)
        {
            enum defaultPrefix = "\n                      ";
            result ~= dep.name;
            string prefix = defaultPrefix[1 + dep.name.length .. $];
            void add(string msg)
            {
                result ~= format("%s%s", prefix, msg);
                prefix = defaultPrefix;
            }
            if (dep.description)
                add(dep.description);
            else if (dep.targets)
            {
                foreach (target; dep.targets)
                {
                    add(target.relativePath);
                }
            }
            result ~= "\n";
        }
    }
    return result;
}

/**
D build dependencies
====================

The strategy of this script is to emulate what the Makefile is doing.

Below all individual dependencies of DMD are defined.
They have a target path, sources paths and an optional name.
When a dependency is needed either its command or custom commandFunction is executed.
A dependency will be skipped if all targets are older than all sources.
This script is by default part of the sources and thus any change to the build script,
will trigger a full rebuild.

*/

/// Returns: The dependency that runs the autotester build
alias autoTesterBuild = makeDep!((builder, dep) {
    builder
    .name("auto-tester-build")
    .description("Run the autotester build")
    .deps([toolchainInfo, dmdDefault, checkwhitespace]);

    version (Posix)
        dep.deps ~= runCxxUnittest;

    // unittests are currently not executed as part of `auto-tester-test` on windows
    // because changes to `win32.mak` require additional changes on the autotester
    // (see https://github.com/dlang/dmd/pull/7414).
    // This requires no further actions and avoids building druntime+phobos on unittest failure
    version (Windows)
        dep.deps ~= runDmdUnittest;
});

/// Returns: the dependency that builds the lexer object file
alias lexer = makeDep!((builder, dep) => builder
    .name("lexer")
    .target(env["G"].buildPath("lexer").objName)
    .sources(sources.lexer)
    .deps([versionFile, sysconfDirFile])
    .msg("(DC) LEXER_OBJ")
    .command([env["HOST_DMD_RUN"],
        "-c",
        "-of" ~ dep.target,
        "-vtls"]
        .chain(flags["DFLAGS"],
            // source files need to have relative paths in order for the code coverage
            // .lst files to be named properly for CodeCov to find them
            dep.sources.map!(e => e.relativePath(srcDir))
        ).array
    )
);

/// Returns: the dependency that generates the dmd.conf file in the output folder
alias dmdConf = makeDep!((builder, dep) {
    // TODO: add support for Windows
    string exportDynamic;
    version(OSX) {} else
        exportDynamic = " -L--export-dynamic";

    auto conf = `[Environment32]
DFLAGS=-I%@P%/../../../../../druntime/import -I%@P%/../../../../../phobos -L-L%@P%/../../../../../phobos/generated/{OS}/{BUILD}/32{exportDynamic}

[Environment64]
DFLAGS=-I%@P%/../../../../../druntime/import -I%@P%/../../../../../phobos -L-L%@P%/../../../../../phobos/generated/{OS}/{BUILD}/64{exportDynamic} -fPIC`
        .replace("{exportDynamic}", exportDynamic)
        .replace("{BUILD}", env["BUILD"])
        .replace("{OS}", env["OS"]);
    builder
        .name("dmdconf")
        .target(env["G"].buildPath("dmd.conf"))
        .msg("(TX) DMD_CONF")
        .commandFunction(() {
            conf.toFile(dep.target);
        });
});

/// Returns: the dependency that builds the backend object file
alias backend = makeDep!((builder, dep) => builder
    .name("backend")
    .target(env["G"].buildPath("backend").objName)
    .sources(sources.backend)
    .msg("(DC) BACKEND_OBJ")
    .command([
        env["HOST_DMD_RUN"],
        "-c",
        "-of" ~ dep.target,
        "-betterC"]
        .chain(flags["DFLAGS"], dep.sources).array)
);

/// Returns: the dependencies that generate required string files: VERSION and SYSCONFDIR.imp
alias versionFile = makeDep!((builder, dep) {
    alias contents = memoize!(() {
        if (dmdRepo.buildPath(".git").exists)
        {
            try
            {
                auto gitResult = [env["GIT"], "describe", "--dirty"].tryRun;
                if (gitResult.status == 0)
                    return gitResult.output.strip;
            }
            catch (ProcessException)
            {
                // git not installed
            }
        }
        // version fallback
        return dmdRepo.buildPath("VERSION").readText;
    });
    builder
    .target(env["G"].buildPath("VERSION"))
    .condition(() => !dep.target.exists || dep.target.readText != contents)
    .msg("(TX) VERSION")
    .commandFunction(() => std.file.write(dep.target, contents));
});

alias sysconfDirFile = makeDep!((builder, dep) => builder
    .target(env["G"].buildPath("SYSCONFDIR.imp"))
    .condition(() => !dep.target.exists || dep.target.readText != env["SYSCONFDIR"])
    .msg("(TX) SYSCONFDIR")
    .commandFunction(() => std.file.write(dep.target, env["SYSCONFDIR"]))
);

/// Dependency to create a directory if it doesn't exist.
alias directoryDep = makeDepWithArgs!((MethodInitializer!Dependency builder, Dependency dep, string dir) => builder
   .target(dir)
   .condition(() => !exists(dir))
   .msg("mkdirRecurse '%s'".format(dir))
   .commandFunction(() => mkdirRecurse(dir))
);

/**
Dependency for the DMD executable.

Params:
  extra_flags = Flags to apply to the main build but not the dependencies
*/
alias dmdExe = makeDepWithArgs!((MethodInitializer!Dependency builder, Dependency dep, string targetSuffix, string[] extraFlags) {
    const dmdSources = sources.dmd.chain(sources.root).array;

    string[] platformArgs;
    version (Windows)
        platformArgs = ["-L/STACK:8388608"];

    builder
        // include lexer.o and backend.o
        .sources(dmdSources.chain(lexer.targets, backend.targets).array)
        .target(env["DMD_PATH"] ~ targetSuffix)
        .msg("(DC) DMD" ~ targetSuffix)
        .deps([versionFile, sysconfDirFile, lexer, backend])
        .command([
            env["HOST_DMD_RUN"],
            "-of" ~ dep.target,
            "-vtls",
            "-J" ~ env["RES"],
            ].chain(extraFlags, platformArgs, flags["DFLAGS"],
                // source files need to have relative paths in order for the code coverage
                // .lst files to be named properly for CodeCov to find them
                dep.sources.map!(e => e.relativePath(srcDir))
            ).array);
});

alias dmdDefault = makeDep!((builder, dep) => builder
    .name("dmd")
    .description("Build dmd")
    .deps([dmdExe(null, null), dmdConf])
);

/// Dependency to run the DMD unittest executable.
alias runDmdUnittest = makeDep!((builder, dep) {
    auto dmdUnittestExe = dmdExe("-unittest", ["-version=NoMain", "-unittest", "-main"]);
    builder
        .name("unittest")
        .description("Run the dmd unittests")
        .msg("(RUN) DMD-UNITTEST")
        .deps([dmdUnittestExe])
        .command(dmdUnittestExe.targets);
});

/// Runs the C++ unittest executable
alias runCxxUnittest = makeDep!((runCxxBuilder, runCxxDep) {

    /// Compiles the C++ frontend test files
    alias cxxFrontend = methodInit!(Dependency, (frontendBuilder, frontendDep) => frontendBuilder
        .name("cxx-frontend")
        .description("Build the C++ frontend")
        .msg("(CXX) CXX-FRONTEND")
        .sources(srcDir.buildPath("tests", "cxxfrontend.c") ~ .sources.frontendHeaders ~ .sources.dmd ~ .sources.root)
        .target(env["G"].buildPath("cxxfrontend").objName)
        .command([ env["CXX"], "-c", frontendDep.sources[0], "-o" ~ frontendDep.target, "-I" ~ env["D"] ] ~ flags["CXXFLAGS"])
    );

    alias cxxUnittestExe = methodInit!(Dependency, (exeBuilder, exeDep) => exeBuilder
        .name("cxx-unittest")
        .description("Build the C++ unittests")
        .msg("(DMD) CXX-UNITTEST")
        .deps([lexer, backend, cxxFrontend])
        .sources(sources.dmd ~ sources.root)
        .target(env["G"].buildPath("cxx-unittest").exeName)
        .command([ env["HOST_DMD_RUN"], "-of=" ~ exeDep.target, "-vtls", "-J" ~ env["RES"],
                    "-L-lstdc++", "-version=NoMain"
            ].chain(
                flags["DFLAGS"], exeDep.sources, exeDep.deps.map!(d => d.target)
            ).array)
    );

    runCxxBuilder
        .name("cxx-unittest")
        .description("Run the C++ unittests")
        .msg("(RUN) CXX-UNITTEST");
    version (Windows) runCxxBuilder
        .commandFunction({ abortBuild("Running the C++ unittests is not supported on Windows yet"); });
    else runCxxBuilder
        .deps([cxxUnittestExe])
        .command([cxxUnittestExe.target]);
});

/// Dependency that removes all generated files
alias clean = makeDep!((builder, dep) => builder
    .name("clean")
    .description("Remove the generated directory")
    .msg("(RM) " ~ env["G"])
    .commandFunction(delegate() {
        if (env["G"].exists)
            env["G"].rmdirRecurse;
    })
);

alias toolsRepo = makeDep!((builder, dep) => builder
    .target(env["TOOLS_DIR"])
    .msg("(GIT) DLANG/TOOLS")
    .commandFunction(delegate() {
        auto toolsDir = env["TOOLS_DIR"];
        if (!toolsDir.exists)
        {
            version(Win32)
                // Win32-git seems to confuse C:\... as a relative path
                toolsDir = toolsDir.relativePath(srcDir);
            run([env["GIT"], "clone", "--depth=1", env["GIT_HOME"] ~ "/tools", toolsDir]);
        }
    })
);

alias checkwhitespace = makeDep!((builder, dep) => builder
    .name("checkwhitespace")
    .description("Check for trailing whitespace and tabs")
    .msg("(RUN) checkwhitespace")
    .deps([toolsRepo])
    .sources(allSources)
    .commandFunction(delegate() {
        const cmdPrefix = [env["HOST_DMD_RUN"], "-run", env["TOOLS_DIR"].buildPath("checkwhitespace.d")];
        auto chunkLength = allSources.length;
        version (Win32)
            chunkLength = 80; // avoid command-line limit on win32
        // if we want this to be parallel, we can make multiple deps
        foreach (nextSources; allSources.chunks(chunkLength))
        {
            const nextCommand = cmdPrefix ~ nextSources;
            run(nextCommand);
        }
    })
);

alias style = makeDep!((builder, dep)
{
    const dscannerDir = env["G"].buildPath("dscanner");
    alias dscanner = methodInit!(Dependency, (dscannerBuilder, dscannerDep) => dscannerBuilder
        .name("dscanner")
        .description("Build custom DScanner")
        .msg("(GIT,MAKE) DScanner")
        .target(dscannerDir.buildPath("dsc".exeName))
        .commandFunction(()
        {
            const git = env["GIT"];
            run([git, "clone", "https://github.com/dlang-community/Dscanner", dscannerDir]);
            run([git, "-C", dscannerDir, "checkout", "b51ee472fe29c05cc33359ab8de52297899131fe"]);
            run([git, "-C", dscannerDir, "submodule", "update", "--init", "--recursive"]);

            // debug build is faster, but disable 'missing import' messages (missing core from druntime)
            const makefile = dscannerDir.buildPath("makefile");
            const content = readText(makefile);
            File(makefile, "w").lockingTextWriter.replaceInto(content, "dparse_verbose", "StdLoggerDisableWarning");

            run([env.get("MAKE", "make"), "-C", dscannerDir, "githash", "debug"]);
        })
    );

    builder
        .name("style")
        .description("Check for style errors using D-Scanner")
        .msg("(DSCANNER) dmd")
        .deps([dscanner])
        // Disabled because we need to build a patched dscanner version
        // .command([
        //     "dub", "-q", "run", "-y", "dscanner", "--", "--styleCheck", "--config",
        //     srcDir.buildPath(".dscanner.ini"), srcDir.buildPath("dmd"), "-I" ~ srcDir
        // ])
        .command([
            dscanner.target, "--styleCheck", "--config", srcDir.buildPath(".dscanner.ini"),
            srcDir.buildPath("dmd"), "-I" ~ srcDir
        ]);
});

/// Dependency to generate man pages
alias man = makeDep!((builder, dep) {
    alias genMan = methodInit!(Dependency, (genManBuilder, genManDep) => genManBuilder
        .target(env["G"].buildPath("gen_man"))
        .sources([
            dmdRepo.buildPath("docs", "gen_man.d"),
            env["D"].buildPath("cli.d")])
        .command([
            env["HOST_DMD_RUN"],
            "-I" ~ srcDir,
            "-of" ~ genManDep.target]
            ~ flags["DFLAGS"]
            ~ genManDep.sources)
        .msg(genManDep.command.join(" "))
    );

    const genManDir = env["GENERATED"].buildPath("docs", "man");
    alias dmdMan = methodInit!(Dependency, (dmdManBuilder, dmdManDep) => dmdManBuilder
        .target(genManDir.buildPath("man1", "dmd.1"))
        .deps([genMan, directoryDep(dmdManDep.target.dirName)])
        .msg("(GEN_MAN) " ~ dmdManDep.target)
        .commandFunction(() {
            std.file.write(dmdManDep.target, genMan.target.execute.output);
        })
    );
    builder
    .name("man")
    .description("Generate and prepare man files")
    .deps([dmdMan].chain(
        "man1/dumpobj.1 man1/obj2asm.1 man5/dmd.conf.5".split
        .map!(e => methodInit!(Dependency, (manFileBuilder, manFileDep) => manFileBuilder
            .target(genManDir.buildPath(e))
            .sources([dmdRepo.buildPath("docs", "man", e)])
            .deps([directoryDep(manFileDep.target.dirName)])
            .commandFunction(() => copyAndTouch(manFileDep.sources[0], manFileDep.target))
            .msg("copy '%s' to '%s'".format(manFileDep.sources[0], manFileDep.target))
        ))
    ).array);
});

alias detab = makeDep!((builder, dep) => builder
    .name("detab")
    .description("Replace hard tabs with spaces")
    .command([env["DETAB"]] ~ allSources)
    .msg("(DETAB) DMD")
);

alias tolf = makeDep!((builder, dep) => builder
    .name("tolf")
    .description("Convert to Unix line endings")
    .command([env["TOLF"]] ~ allSources)
    .msg("(TOLF) DMD")
);

alias zip = makeDep!((builder, dep) => builder
    .name("zip")
    .target(srcDir.buildPath("dmdsrc.zip"))
    .description("Archive all source files")
    .sources(sources.root ~ sources.backend ~ sources.lexer ~
        sources.frontendHeaders ~ sources.dmd)
    .msg("ZIP " ~ dep.target)
    .commandFunction(() {
        if (exists(dep.target))
            remove(dep.target);
        run([env["ZIP"], dep.target, thisBuildScript] ~ dep.sources);
    })
);

alias html = makeDep!((htmlBuilder, htmlDep) {
    htmlBuilder
        .name("html")
        .description("Generate html docs, requires DMD and STDDOC to be set");
    static string d2html(string sourceFile)
    {
        const ext = sourceFile.extension();
        assert(ext == ".d" || ext == ".di", sourceFile);
        const htmlFilePrefix = (sourceFile.baseName == "package.d") ?
            sourceFile[0 .. $ - "package.d".length - 1] :
            sourceFile[0 .. $ - ext.length];
        return htmlFilePrefix ~ ".html";
    }
    const stddocs = env.get("STDDOC", "").split();
    auto docSources = .sources.root ~ .sources.lexer ~ .sources.dmd ~ env["D"].buildPath("frontend.d");
    htmlBuilder.deps(docSources.chunks(1).map!(sourceArray =>
        methodInit!(Dependency, (docBuilder, docDep) {
            const source = sourceArray[0];
            docBuilder
            .sources(sourceArray)
            .target(env["DOC_OUTPUT_DIR"].buildPath(d2html(source)[srcDir.length + 1..$]
                .replace(dirSeparator, "_")))
            .deps([dmdDefault, versionFile, sysconfDirFile])
            .command([
                dmdDefault.deps[0].target,
                "-o-",
                "-c",
                "-Dd" ~ env["DOCSRC"],
                "-J" ~ env["RES"],
                "-I" ~ env["D"],
                srcDir.buildPath("project.ddoc")
                ] ~ stddocs ~ [
                    "-Df" ~ docDep.target,
                    // Need to use a short relative path to make sure ddoc links are correct
                    source.relativePath(runDir)
                ] ~ flags["DFLAGS"])
            .msg("(DDOC) " ~ source);
        })
    ).array);
});

alias toolchainInfo = makeDep!((builder, dep) => builder
    .name("toolchain-info")
    .description("Show informations about used tools")
    .commandFunction(() {

        static void show(string what, string[] cmd)
        {
            string output;
            try
                output = tryRun(cmd).output;
            catch (ProcessException)
                output = "<Not available>";

            writefln("%s (%s): %s", what, cmd[0], output);
        }

        writeln("==== Toolchain Information ====");

        version (Windows)
            show("SYSTEM", ["systeminfo"]);
        else
            show("SYSTEM", ["uname", "-a"]);

        show("MAKE", [env.get("MAKE", "make"), "--version"]);
        version (Posix)
            show("SHELL", [env.get("SHELL", nativeShell), "--version"]);  // cmd.exe --version hangs
        show("HOST_DMD", [env["HOST_DMD_RUN"], "--version"]);
        version (Posix)
            show("HOST_CXX", [env["CXX"], "--version"]);
        show("ld", ["ld", "-v"]);
        show("gdb", ["gdb", "--version"]);

        writeln("==== Toolchain Information ====\n");
    })
);

/**
Goes through the target list and replaces short-hand targets with their expanded version.
Special targets:
- clean -> removes generated directory + immediately stops the builder

Params:
    targets = the target list to process
Returns:
    the expanded targets
*/
Dependency[] predefinedTargets(string[] targets)
{
    import std.functional : toDelegate;
    Appender!(Dependency[]) newTargets;
LtargetsLoop:
    foreach (t; targets)
    {
        t = t.buildNormalizedPath; // remove trailing slashes

        // check if `t` matches any dependency names first
        foreach (dep; DependencyRange(rootDeps.map!(a => a()).array))
        {
            if (t == dep.name)
            {
                newTargets.put(dep);
                continue LtargetsLoop;
            }
        }

        switch (t)
        {
            case "all":
                t = "dmd";
                goto default;

            case "install":
                "TODO: install".writeln; // TODO
                break;

            default:
                // check this last, target paths should be checked after predefined names
                const tAbsolute = t.absolutePath.buildNormalizedPath;
                foreach (dep; DependencyRange(rootDeps.map!(a => a()).array))
                {
                    foreach (depTarget; dep.targets)
                    {
                        if (depTarget.endsWith(t, tAbsolute))
                        {
                            newTargets.put(dep);
                            continue LtargetsLoop;
                        }
                    }
                }

                abortBuild("Target `" ~ t ~ "` is unknown.");
        }
    }
    return newTargets.data;
}

/// An input range for a recursive set of dependencies
struct DependencyRange
{
    private Dependency[] next;
    private bool[Dependency] added;
    this(Dependency[] deps) { addDeps(deps); }
    bool empty() const { return next.length == 0; }
    auto front() inout { return next[0]; }
    void popFront()
    {
        auto save = next[0];
        next = next[1 .. $];
        addDeps(save.deps);
    }
    void addDeps(Dependency[] deps)
    {
        foreach (dep; deps)
        {
            if (!added.get(dep, false))
            {
                next ~= dep;
                added[dep] = true;
            }
        }
    }
}

/// Sets the environment variables
void parseEnvironment()
{
    // This block is temporary until we can remove the windows make files
    {
        const ddebug = env.get("DDEBUG", null);
        if (ddebug.length)
        {
            writefln("WARNING: the DDEBUG variable is deprecated");
            if (ddebug == "-debug -g -unittest -cov")
            {
                environment["ENABLE_DEBUG"] = "1";
                environment["ENABLE_UNITTEST"] = "1";
                environment["ENABLE_COVERAGE"] = "1";
            }
            else if (ddebug == "-debug -g -unittest")
            {
                environment["ENABLE_DEBUG"] = "1";
                environment["ENABLE_UNITTEST"] = "1";
            }
            else
            {
                abortBuild("DDEBUG is not an expected value: " ~ ddebug);
            }
        }
    }

    env.getDefault("TARGET_CPU", "X86");
    version (Windows)
    {
        // On windows, the OS environment variable is already being used by the system.
        // For example, on a default Windows7 system it's configured by the system
        // to be "Windows_NT".
        //
        // However, there are a good number of components in this repo and the other
        // repos that set this environment variable to "windows" without checking whether
        // it's already configured, i.e.
        //      dmd\src\win32.mak (OS=windows)
        //      druntime\win32.mak (OS=windows)
        //      phobos\win32.mak (OS=windows)
        //
        // It's necessary to emulate the same behavior in this tool in order to make this
        // new tool compatible with existing tools. We can do this by also setting the
        // environment variable to "windows" whether or not it already has a value.
        //
        const os = env["OS"] = "windows";
    }
    else
        const os = env.getDefault("OS", detectOS);
    auto build = env.getDefault("BUILD", "release");
    enforce(build.among("release", "debug"), "BUILD must be 'debug' or 'release'");

    // detect Model
    auto model = env.getDefault("MODEL", detectModel);
    env["MODEL_FLAG"] = "-m" ~ env["MODEL"];

    // detect PIC
    version(Posix)
    {
        // default to PIC on x86_64, use PIC=1/0 to en-/disable PIC.
        // Note that shared libraries and C files are always compiled with PIC.
        bool pic;
        version(X86_64)
            pic = true;
        else version(X86)
            pic = false;
        if (environment.get("PIC", "0") == "1")
            pic = true;

        env["PIC_FLAG"]  = pic ? "-fPIC" : "";
    }
    else
    {
        env["PIC_FLAG"] = "";
    }

    env.getDefault("GIT", "git");
    env.getDefault("GIT_HOME", "https://github.com/dlang");
    env.getDefault("SYSCONFDIR", "/etc");
    env.getDefault("TMP", tempDir);
    env.getDefault("RES", dmdRepo.buildPath("res"));

    env.getDefault("DOCSRC", dmdRepo.buildPath("dlang.org"));
    if (env.get("DOCDIR", null).length == 0)
        env["DOCDIR"] = srcDir;
    env.getDefault("DOC_OUTPUT_DIR", env["DOCDIR"]);

    auto d = env["D"] = srcDir.buildPath("dmd");
    env["C"] = d.buildPath("backend");
    env["ROOT"] = d.buildPath("root");
    env["EX"] = srcDir.buildPath("examples");
    auto generated = env["GENERATED"] = dmdRepo.buildPath("generated");
    auto g = env["G"] = generated.buildPath(os, build, model);
    mkdirRecurse(g);
    env.getDefault("TOOLS_DIR", dmdRepo.dirName.buildPath("tools"));

    if (env.get("HOST_DMD", null).length == 0)
    {
        const hostDmd = env.get("HOST_DC", null);
        env["HOST_DMD"] = hostDmd.length ? hostDmd : "dmd";
    }

    // Auto-bootstrapping of a specific host compiler
    if (env.getDefault("AUTO_BOOTSTRAP", null) == "1")
    {
        auto hostDMDVer = env.getDefault("HOST_DMD_VER", "2.088.0");
        writefln("Using Bootstrap compiler: %s", hostDMDVer);
        auto hostDMDRoot = env["G"].buildPath("host_dmd-"~hostDMDVer);
        auto hostDMDBase = hostDMDVer~"."~os;
        auto hostDMDURL = "http://downloads.dlang.org/releases/2.x/"~hostDMDVer~"/dmd."~hostDMDBase;
        env["HOST_DMD"] = hostDMDRoot.buildPath("dmd2", os, os == "osx" ? "bin" : "bin"~model, "dmd");
        env["HOST_DMD_PATH"] = env["HOST_DMD"];
        // TODO: use dmd.conf from the host too (in case there's a global or user-level dmd.conf)
        env["HOST_DMD_RUN"] = env["HOST_DMD"];
        if (!env["HOST_DMD"].exists)
        {
            writefln("Downloading DMD %s", hostDMDVer);
            auto curlFlags = "-fsSL --retry 5 --retry-max-time 120 --connect-timeout 5 --speed-time 30 --speed-limit 1024";
            hostDMDRoot.mkdirRecurse;
            ("curl " ~ curlFlags ~ " " ~ hostDMDURL~".tar.xz | tar -C "~hostDMDRoot~" -Jxf - || rm -rf "~hostDMDRoot).spawnShell.wait;
        }
    }
    else
    {
        env["HOST_DMD_PATH"] = getHostDMDPath(env["HOST_DMD"]).strip.absolutePath;
        env["HOST_DMD_RUN"] = env["HOST_DMD_PATH"];
    }

    if (!env["HOST_DMD_PATH"].exists)
    {
        abortBuild("No DMD compiler is installed. Try AUTO_BOOTSTRAP=1 or manually set the D host compiler with HOST_DMD");
    }
}

/// Checks the environment variables and flags
void processEnvironment()
{
    import std.meta : AliasSeq;

    const os = env["OS"];

    const hostDMDVersion = [env["HOST_DMD_RUN"], "--version"].execute.output;

    alias DMD = AliasSeq!("DMD");
    alias LDC = AliasSeq!("LDC");
    alias GDC = AliasSeq!("GDC", "gdmd", "gdc");
    const kindIdx = hostDMDVersion.canFind(DMD, LDC, GDC);

    enforce(kindIdx, "Invalid Host DMD found: " ~ hostDMDVersion);

    if (kindIdx <= DMD.length)
        env["HOST_DMD_KIND"] = "dmd";
    else if (kindIdx <= LDC.length + DMD.length)
        env["HOST_DMD_KIND"] = "ldc";
    else
        env["HOST_DMD_KIND"] = "gdc";

    env["DMD_PATH"] = env["G"].buildPath("dmd").exeName;
    env.getDefault("DETAB", "detab");
    env.getDefault("TOLF", "tolf");
    version (Windows)
        env.getDefault("ZIP", "zip32");
    else
        env.getDefault("ZIP", "zip");

    env.getDefault("ENABLE_WARNINGS", "0");
    string[] warnings;

    string[] dflags = ["-version=MARS", "-w", "-de", env["PIC_FLAG"], env["MODEL_FLAG"], "-J"~env["G"]];
    if (env["HOST_DMD_KIND"] != "gdc")
        dflags ~= ["-dip25"]; // gdmd doesn't support -dip25

    // TODO: add support for dObjc
    auto dObjc = false;
    version(OSX) version(X86_64)
        dObjc = true;

    if (env.getDefault("ENABLE_DEBUG", "0") != "0")
    {
        dflags ~= ["-g", "-debug"];
    }
    if (env.getDefault("ENABLE_RELEASE", "0") != "0")
    {
        dflags ~= ["-O", "-release", "-inline"];
    }
    else
    {
        // add debug symbols for all non-release builds
        if (!dflags.canFind("-g"))
            dflags ~= ["-g"];
    }
    if (env.getDefault("ENABLE_LTO", "0") != "0")
    {
        dflags ~= ["-flto=full"];
    }
    if (env.getDefault("ENABLE_UNITTEST", "0") != "0")
    {
        dflags ~= ["-unittest", "-cov"];
    }
    if (env.getDefault("ENABLE_PROFILE", "0") != "0")
    {
        dflags ~= ["-profile"];
    }
    if (env.getDefault("ENABLE_COVERAGE", "0") != "0")
    {
        dflags ~= ["-cov", "-L-lgcov"];
    }
    if (env.getDefault("ENABLE_SANITIZERS", "0") != "0")
    {
        dflags ~= ["-fsanitize="~env["ENABLE_SANITIZERS"]];
    }

    // Retain user-defined flags
    flags["DFLAGS"] = dflags ~= flags.get("DFLAGS", []);
}

/// Setup environment for a C++ compiler
void processEnvironmentCxx()
{
    // Windows requires additional work to handle e.g. Cygwin on Azure
    version (Windows) return;

    const cxxKind = env["CXX_KIND"] = detectHostCxx();

    string[] warnings  = [
        "-Wall", "-Werror", "-Wextra", "-Wno-attributes", "-Wno-char-subscripts", "-Wno-deprecated",
        "-Wno-empty-body", "-Wno-format", "-Wno-missing-braces", "-Wno-missing-field-initializers",
        "-Wno-overloaded-virtual", "-Wno-parentheses", "-Wno-reorder", "-Wno-return-type",
        "-Wno-sign-compare", "-Wno-strict-aliasing", "-Wno-switch", "-Wno-type-limits",
        "-Wno-unknown-pragmas", "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
        "-Wno-unused-value", "-Wno-unused-variable"
    ];

    if (cxxKind == "g++")
        warnings ~= [
            "-Wno-class-memaccess", "-Wno-implicit-fallthrough", "-Wno-logical-op", "-Wno-narrowing",
            "-Wno-uninitialized", "-Wno-unused-but-set-variable"
        ];

    if (cxxKind == "clang++")
        warnings ~= ["-Wno-logical-op-parentheses", "-Wno-unused-private-field"];

    auto cxxFlags = warnings ~ [
        "-g", "-fno-exceptions", "-fno-rtti", "-fasynchronous-unwind-tables", "-DMARS=1",
        env["MODEL_FLAG"], env["PIC_FLAG"],

        // No explicit if since cxxKind will always be either g++ or clang++
        cxxKind == "g++" ? "-std=gnu++98" : "-xc++"
    ];

    if (env["ENABLE_COVERAGE"] != "0")
        cxxFlags ~= "--coverage";

    if (env["ENABLE_SANITIZERS"] != "0")
        cxxFlags ~= "-fsanitize=" ~ env["ENABLE_SANITIZERS"];

    // Enable a temporary workaround in globals.h and rmem.h concerning
    // wrong name mangling using DMD.
    // Remove when the minimally required D version becomes 2.082 or later
    if (env["HOST_DMD_KIND"] == "dmd")
    {
        const output = run([ env["HOST_DMD_RUN"], "--version" ]);

        if (output.canFind("v2.079", "v2.080", "v2.081"))
            cxxFlags ~= "-DDMD_VERSION=2080";
    }

    // Retain user-defined flags
    flags["CXXFLAGS"] = cxxFlags ~= flags.get("CXXFLAGS", []);
}

/// Returns: the host C++ compiler, either "g++" or "clang++"
string detectHostCxx()
{
    import std.meta: AliasSeq;

    const cxxVersion = [env.getDefault("CXX", "c++"), "--version"].execute.output;

    alias GCC = AliasSeq!("g++", "gcc", "Free Software");
    alias CLANG = AliasSeq!("clang");

    const cxxKindIdx = cxxVersion.canFind(GCC, CLANG);
    enforce(cxxKindIdx, "Invalid CXX found: " ~ cxxVersion);

    return cxxKindIdx <= GCC.length ? "g++" : "clang++";
}

////////////////////////////////////////////////////////////////////////////////
// D source files
////////////////////////////////////////////////////////////////////////////////

/// Returns: all source files in the repository
alias allSources = memoize!(() => srcDir.dirEntries("*.{d,h,di}", SpanMode.depth).map!(e => e.name).array);

/// Returns: all source files for the compiler
auto sourceFiles()
{
    struct Sources
    {
        string[] frontend, lexer, root, glue, dmd, backend;
        string[] frontendHeaders, backendHeaders;
    }
    string targetCH;
    string[] targetObjs;
    if (env["TARGET_CPU"] == "X86")
    {
        targetCH = "code_x86.h";
    }
    else if (env["TARGET_CPU"] == "stub")
    {
        targetCH = "code_stub.h";
        targetObjs = ["platform_stub"];
    }
    else
    {
        assert(0, "Unknown TARGET_CPU: " ~ env["TARGET_CPU"]);
    }
    static string[] fileArray(string dir, string files)
    {
        return files.split.map!(e => dir.buildPath(e)).array;
    }
    Sources sources = {
        glue: fileArray(env["D"], "
            irstate.d toctype.d glue.d gluelayer.d todt.d tocsym.d toir.d dmsc.d
            tocvdebug.d s2ir.d toobj.d e2ir.d eh.d iasm.d iasmdmd.d iasmgcc.d objc_glue.d
        "),
        frontend: fileArray(env["D"], "
            access.d aggregate.d aliasthis.d apply.d argtypes.d argtypes_sysv_x64.d arrayop.d
            arraytypes.d ast_node.d astbase.d astcodegen.d attrib.d blockexit.d builtin.d canthrow.d
            cli.d clone.d compiler.d complex.d cond.d constfold.d cppmangle.d cppmanglewin.d ctfeexpr.d
            ctorflow.d dcast.d dclass.d declaration.d delegatize.d denum.d dimport.d dinifile.d
            dinterpret.d dmacro.d dmangle.d dmodule.d doc.d dscope.d dstruct.d dsymbol.d dsymbolsem.d
            dtemplate.d dversion.d env.d escape.d expression.d expressionsem.d func.d hdrgen.d impcnvtab.d
            imphint.d init.d initsem.d inline.d inlinecost.d intrange.d json.d lambdacomp.d lib.d libelf.d
            libmach.d libmscoff.d libomf.d link.d mars.d mtype.d nogc.d nspace.d objc.d opover.d optimize.d
            parse.d parsetimevisitor.d permissivevisitor.d printast.d safe.d sapply.d scanelf.d scanmach.d
            scanmscoff.d scanomf.d semantic2.d semantic3.d sideeffect.d statement.d statement_rewrite_walker.d
            statementsem.d staticassert.d staticcond.d strictvisitor.d target.d templateparamsem.d traits.d
            transitivevisitor.d typesem.d typinf.d utils.d visitor.d foreachvar.d
        "),
        frontendHeaders: fileArray(env["D"], "
            aggregate.h aliasthis.h arraytypes.h attrib.h compiler.h complex_t.h cond.h
            ctfe.h declaration.h dsymbol.h doc.h enum.h errors.h expression.h globals.h hdrgen.h
            identifier.h id.h import.h init.h json.h mangle.h module.h mtype.h nspace.h objc.h scope.h
            statement.h staticassert.h target.h template.h tokens.h version.h visitor.h
        "),
        lexer: fileArray(env["D"], "
            console.d entity.d errors.d filecache.d globals.d id.d identifier.d lexer.d tokens.d utf.d
        ") ~ fileArray(env["ROOT"], "
            array.d bitarray.d ctfloat.d file.d filename.d hash.d outbuffer.d port.d region.d rmem.d
            rootobject.d stringtable.d
        "),
        root: fileArray(env["ROOT"], "
            aav.d longdouble.d man.d response.d speller.d string.d strtold.d
        "),
        backend: fileArray(env["C"], "
            backend.d bcomplex.d evalu8.d divcoeff.d dvec.d go.d gsroa.d glocal.d gdag.d gother.d gflow.d
            out.d
            gloop.d compress.d cgelem.d cgcs.d ee.d cod4.d cod5.d nteh.d blockopt.d mem.d cg.d cgreg.d
            dtype.d debugprint.d fp.d symbol.d elem.d dcode.d cgsched.d cg87.d cgxmm.d cgcod.d cod1.d cod2.d
            cod3.d cv8.d dcgcv.d pdata.d util2.d var.d md5.d backconfig.d ph2.d drtlsym.d dwarfeh.d ptrntab.d
            dvarstats.d dwarfdbginf.d cgen.d os.d goh.d barray.d cgcse.d elpicpie.d
            machobj.d elfobj.d
            " ~ ((env["OS"] == "windows") ? "cgobj.d filespec.d mscoffobj.d newman.d" : "aarray.d")
        ),
        backendHeaders: fileArray(env["C"], "
            cc.d cdef.d cgcv.d code.d cv4.d dt.d el.d global.d
            obj.d oper.d outbuf.d rtlsym.d code_x86.d iasm.d codebuilder.d
            ty.d type.d exh.d mach.d mscoff.d dwarf.d dwarf2.d xmm.d
            dlist.d melf.d varstats.di
        "),
    };
    sources.dmd = sources.frontend ~ sources.glue ~ sources.backendHeaders;

    return sources;
}

/**
Downloads a file from a given URL

Params:
    to    = Location to store the file downloaded
    from  = The URL to the file to download
    tries = The number of times to try if an attempt to download fails
Returns: `true` if download succeeded
*/
bool download(string to, string from, uint tries = 3)
{
    import std.net.curl : download, HTTP, HTTPStatusException;

    foreach(i; 0..tries)
    {
        try
        {
            log("Downloading %s ...", from);
            auto con = HTTP(from);
            download(from, to, con);

            if (con.statusLine.code == 200)
                return true;
        }
        catch(HTTPStatusException e)
        {
            if (e.status == 404) throw e;
        }

        log("Failed to download %s (Attempt %s of %s)", from, i + 1, tries);
    }

    return false;
}

/**
Detects the host OS.

Returns: a string from `{windows, osx,linux,freebsd,openbsd,netbsd,dragonflybsd,solaris}`
*/
string detectOS()
{
    version(Windows)
        return "windows";
    else version(OSX)
        return "osx";
    else version(linux)
        return "linux";
    else version(FreeBSD)
        return "freebsd";
    else version(OpenBSD)
        return "openbsd";
    else version(NetBSD)
        return "netbsd";
    else version(DragonFlyBSD)
        return "dragonflybsd";
    else version(Solaris)
        return "solaris";
    else
        static assert(0, "Unrecognized or unsupported OS.");
}

/**
Detects the host model

Returns: 32, 64 or throws an Exception
*/
auto detectModel()
{
    string uname;
    if (detectOS == "solaris")
        uname = ["isainfo", "-n"].execute.output;
    else if (detectOS == "windows")
    {
        version (D_LP64)
            return "64"; // host must be 64-bit if this compiles
        else version (Windows)
        {
            import core.sys.windows.winbase;
            int is64;
            if (IsWow64Process(GetCurrentProcess(), &is64))
                return is64 ? "64" : "32";
        }
    }
    else
        uname = ["uname", "-m"].execute.output;

    if (uname.canFind("x86_64", "amd64", "64-bit", "64-Bit", "64 bit"))
        return "64";
    if (uname.canFind("i386", "i586", "i686", "32-bit", "32-Bit", "32 bit"))
        return "32";

    throw new Exception(`Cannot figure 32/64 model from "` ~ uname ~ `"`);
}

/**
Gets the absolute path of the host's dmd executable

Params:
    hostDmd = the command used to launch the host's dmd executable
Returns: a string that is the absolute path of the host's dmd executable
*/
auto getHostDMDPath(string hostDmd)
{
    version(Posix)
        return ["which", hostDmd].execute.output;
    else version(Windows)
    {
        if (hostDmd.canFind("/", "\\"))
            return hostDmd;
        return ["where", hostDmd].execute.output
            .lineSplitter.filter!(file => file != srcDir.buildPath("dmd.exe")).front;
    }
    else
        static assert(false, "Unrecognized or unsupported OS.");
}

/**
Add the executable filename extension to the given `name` for the current OS.

Params:
    name = the name to append the file extention to
*/
auto exeName(T)(T name)
{
    version(Windows)
        return name ~ ".exe";
    return name;
}

/**
Add the object file extension to the given `name` for the current OS.

Params:
    name = the name to append the file extention to
*/
auto objName(T)(T name)
{
    version(Windows)
        return name ~ ".obj";
    return name ~ ".o";
}

/**
Add the library file extension to the given `name` for the current OS.

Params:
    name = the name to append the file extention to
*/
auto libName(T)(T name)
{
    version(Windows)
        return name ~ ".lib";
    return name ~ ".a";
}

/**
Filter additional make-like assignments from args and add them to the environment
e.g. ./build.d ARGS=foo sets env["ARGS"] = environment["ARGS"] = "foo".

The variables DLFAGS and CXXFLAGS may contain flags intended for the
respective compiler and set flags instead, e.g. ./build.d DFLAGS="-w -version=foo"
results in flags["DFLAGS"] = ["-w", "-version=foo"].

Params:
    args = the command-line arguments from which the assignments will be removed
*/
void args2Environment(ref string[] args)
{
    bool tryToAdd(string arg)
    {
        auto parts = arg.findSplit("=");

        if (!parts)
            return false;

        const key = parts[0];
        const value = parts[2];

        if (key.among("DFLAGS", "CXXFLAGS"))
        {
            flags[key] = value.split();
        }
        else
        {
            environment[key] = value;
            env[key] = value;
        }
        return true;
    }
    args = args.filter!(a => !tryToAdd(a)).array;
}

/**
Checks whether the environment already contains a value for key and if so, sets
the found value to the new environment object.
Otherwise uses the `default_` value as fallback.

Params:
    env = environment to write the check to
    key = key to check for existence and write into the new env
    default_ = fallback value if the key doesn't exist in the global environment
*/
auto getDefault(ref string[string] env, string key, string default_)
{
    if (key in environment)
        env[key] = environment[key];
    else
        env[key] = default_;

    return env[key];
}

////////////////////////////////////////////////////////////////////////////////
// Mini build system
////////////////////////////////////////////////////////////////////////////////
/**
Checks whether any of the targets are older than the sources

Params:
    targets = the targets to check
    sources = the source files to check against
Returns:
    `true` if the target is up to date
*/
bool isUpToDate(R, S)(R targets, S sources)
{
    if (force)
        return false;
    auto oldestTargetTime = SysTime.max;
    foreach (target; targets)
    {
        const time = target.timeLastModified.ifThrown(SysTime.init);
        if (time == SysTime.init)
            return false;
        oldestTargetTime = min(time, oldestTargetTime);
    }
    return sources.all!(s => s.timeLastModified.ifThrown(SysTime.init) <= oldestTargetTime);
}

/**
Writes given the content to the given file.

The content will only be written to the file specified in `path` if that file
doesn't exist, or the content of the existing file is different from the given
content.

This makes sure the timestamp of the file is only updated when the
content has changed. This will avoid rebuilding when the content hasn't changed.

Params:
    path = the path to the file to write the content to
    content = the content to write to the file
*/
void updateIfChanged(const string path, const string content)
{
    import std.file : exists, readText, write;

    const existingContent = path.exists ? path.readText : "";

    if (content != existingContent)
        write(path, content);
}

/**
A dependency has one or more sources and yields one or more targets.
It knows how to build these target by invoking either the external command or
the commandFunction.

If a run fails, the entire build stops.
*/
class Dependency
{
    string target; // path to the resulting target file (if target is used, it will set targets)
    string[] targets; // list of all target files
    string[] sources; // list of all source files
    Dependency[] deps; // dependencies to build before this one
    bool delegate() condition; // Optional condition to determine whether or not to run this dependency
    string[] command; // the dependency command
    void delegate() commandFunction; // a custom dependency command which gets called instead of command
    string msg; // msg of the dependency that is e.g. written to the CLI when it's executed
    string name; /// optional string that can be used to identify this dependency
    string description; /// optional string to describe this dependency rather than printing the target files

    /// Finish creating the dependency by checking that it is configured properly
    void finalize()
    {
        if (target)
        {
            assert(!targets, "target and targets cannot both be set");
            targets = [target];
        }
    }

    /// Executes the dependency
    void run()
    {
        import core.atomic : atomicOp;
        run2();
        foreach (dependant; dependants)
        {
            auto built = dependant.builtDeps.atomicOp!"+="(1);
            if (built == dependant.deps.length)
                scheduler.schedule(dependant);
        }
    }
    private void run2()
    {
        if (condition !is null && !condition())
        {
            log("Skipping build of %-(%s%) as its condition returned false", targets);
            return;
        }

        if (targets && targets.isUpToDate(this.sources.chain([thisBuildScript])))
        {
            if (this.sources !is null)
                log("Skipping build of %-(%s%) as it's newer than %-(%s%)", targets, this.sources);
            return;
        }

        // Display the execution of the dependency
        if (msg)
            writefln("[%s] %s", thisThreadID(), msg);

        if(dryRun)
        {
            scope writer = stdout.lockingTextWriter;

            if(commandFunction)
            {
                writer.put("\n => Executing commandFunction()");

                if(name)
                    writer.formattedWrite!" of %s"(name);

                if(targets.length)
                    writer.formattedWrite!" to generate:\n%(    - %s\n%)"(targets);

                writer.put('\n');
            }
            if(command)
                writer.formattedWrite!"\n => %(%s %)\n\n"(command);
        }
        else
        {
            scope (failure) if (!verbose) dump();

            if (commandFunction !is null)

                return commandFunction();

            if (command)
            {
                command.run;
            }
        }
    }

     // Metadata required for parallel execution
    private
    {
        shared uint builtDeps; /// amount of dependencies already built
        bool visited; /// whether this dependency was already visited
        Dependency[] dependants; /// dependencies relying on this one
    }

    /**
    Builds all supplied targets using the global taskPool to execute buildRecursive
    for every leaf dependency.

    Params:
        targets = dependencies to build
    **/
    static void build(Dependency[] targets)
    {
        //// Recursively appends all dependencies without further dependencies to leafs
        static void walkDeps(Dependency rule, Appender!(Dependency[]) pending)
        {
            if (rule.visited) return;
            rule.visited = true;

            if (rule.deps.empty)
            {
                pending.put(rule);
            }
            else
            {
                foreach (dep; rule.deps)
                {
                    dep.dependants ~= rule;
                    walkDeps(dep, pending);
                }
            }
        }
        // Determine all executable dependencies (we can use lockedData.pending because scheduler is not running yet)
        targets.each!(t => walkDeps(t, scheduler.lockedData.pending));
        scheduler.run();
    }

    /// Writes relevant informations about this dependency to stdout
    private void dump()
    {
        scope writer = stdout.lockingTextWriter;
        void write(T)(string fmt, T what)
        {
            static if (is(T : bool))
                bool print = what;
            else
                bool print = what.length != 0;

            if (print)
                writer.formattedWrite(fmt, what);
        }

        writer.put("\nThe following operation failed:\n");
        write("Name: %s\n", name);
        write("Description: %s\n", description);
        write("Dependencies: %-(\n -> %s%)\n\n", deps.map!(d => d.name ? d.name : d.target));
        write("Sources: %-(\n -> %s%)\n\n", sources);
        write("Targets: %-(\n -> %s%)\n\n", targets);
        write("Command: %-(%s %)\n\n", command);
        write("CommandFunction: %-s\n\n", commandFunction ? "Yes" : null);
        writer.put("-----------------------------------------------------------\n");
    }
}

/** Initializes an object using a chain of method calls */
struct MethodInitializer(T) if (is(T == class)) // currenly only works with classes
{
    private T obj;
    auto ref opDispatch(string name)(typeof(__traits(getMember, T, name)) arg)
    {
        mixin("obj." ~ name ~ " = arg;");
        return this;
    }
}

/** Create an object using a chain of method calls for each field. */
T methodInit(T, alias Func, Args...)(Args args) if (is(T == class)) // currently only works with classes
{
    auto initializer = MethodInitializer!T(new T());
    Func(initializer, initializer.obj, args);
    initializer.obj.finalize();
    return initializer.obj;
}

/**
Takes a lambda and returns a memoized function to build a dependecy object.
The lambda takes a builder and a dependency object.
This differs from makeDepWithArgs in that the function literal does not need explicit
parameter types.
*/
alias makeDep(alias Func) = memoize!(methodInit!(Dependency, Func));

/**
Takes a lambda and returns a memoized function to build a dependecy object.
The lambda takes a builder, dependency object and any extra arguments needed
to create the dependnecy.
This differs from makeDep in that the function literal must contain explicit parameter types.
*/
alias makeDepWithArgs(alias Func) = memoize!(methodInit!(Dependency, Func, Parameters!Func[2..$]));

/**
Logging primitive

Params:
    spec = a format specifier
    args = the data to format to the log
*/
auto log(T...)(string spec, T args)
{
    if (verbose)
        writefln(spec, args);
}

/**
Aborts the current build

TODO:
    - Display detailed error messages

Params:
    msg = error message to display

Throws: BuildException with the supplied message

Returns: nothing but enables `throw abortBuild` to convey the resulting behavior
*/
BuildException abortBuild(string msg = "Build failed!")
{
    //scheduler.stop();
    //if (task !is null)
    //    taskPool.stop();

    throw new BuildException(msg);
}

class BuildException : Exception
{
    this(string msg) { super(msg); }
}

/**
The directory where all run commands are executed from.  All relative file paths
in a `run` command must be relative to `runDir`.
*/
alias runDir = srcDir;

/**
Run a command which may not succeed and optionally log the invocation.

Params:
    args = the command and command arguments to execute

Returns: a tuple (status, output)
*/
auto tryRun(T)(T args)
{
    args = args.filter!(a => !a.empty).array;
    log("Run: %s", args.join(" "));
    return execute(args, null, Config.none, size_t.max, runDir);
}

/**
Wrapper around execute that logs the execution
and throws an exception for a non-zero exit code.

Params:
    args = the command and command arguments to execute

Returns: any output of the executed command
*/
auto run(T)(T args)
{
    auto res = tryRun(args);
    if (res.status)
    {
        abortBuild(res.output ? res.output : format("Last command failed with exit code %s", res.status));
    }
    return res.output;
}

/** Wrapper around std.file.copy that also updates the target timestamp. */
void copyAndTouch(RF, RT)(RF from, RT to)
{
    std.file.copy(from, to);
    const now = Clock.currTime;
    to.setTimes(now, now);
}

//
// This is generic enough to be in the standard library
//
struct Scheduler(Runnable)
{
    import core.atomic: atomicLoad, atomicOp, atomicStore;
    import core.sync.mutex;
    import event;
    import core.thread;

    private uint jobCount;
    private shared Mutex mutex;
    private Event _event;
    // This data must be used within the mutex lock while the scheduler is running
    struct LockedData
    {
        private Appender!(Runnable[]) pending;
        private size_t waitingCount;
    }
    private LockedData lockedData;

    void init(uint jobCount)
    in { assert(jobCount > 0); } do
    {
        this.jobCount = jobCount;
        mutex = new shared Mutex();
        _event.initialize(true, true);
        lockedData.pending = appender!(Runnable[])();
        lockedData.waitingCount = 0;
    }

    void schedule(Runnable runnable)
    {
        mutex.lock_nothrow();
        scope(exit) mutex.unlock_nothrow();
        lockedData.pending.put(runnable);
        _event.set();
    }

    void run()
    {
        auto threads = new Thread[jobCount - 1];
        foreach (i; 0 .. threads.length)
        {
            auto t = new Thread(&threadLoop);
            t.isDaemon = true;
            t.start();
        }
        threadLoop();
    }

    private void threadLoop()
    {
        while (true)
        {
            auto runnable = getNextRunnable();
            if (runnable is null)
                break;
            runnable.run();
        }
    }

    private Runnable getNextRunnable()
    {
        bool waiting = false;
        while (true)
        {
            // INSIDE LOCK
            {
                mutex.lock_nothrow();
                scope(exit) mutex.unlock_nothrow();
                if (lockedData.pending.data.length > 0)
                {
                    if (waiting)
                    {
                        lockedData.waitingCount--;
                        waiting = false;
                    }
                    auto runnable = lockedData.pending.data[$-1];
                    lockedData.pending.shrinkTo(lockedData.pending.data.length - 1);
                    return runnable;
                }
                if (!waiting)
                {
                    lockedData.waitingCount++;
                    waiting = true;
                }
                if (lockedData.waitingCount == jobCount)
                {
                    _event.set();
                    return null;
                }
                _event.reset();
            }
            assert(_event.wait());
        }
    }
}
