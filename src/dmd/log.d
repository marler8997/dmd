/**
This module defines symbols to support the recommended debug logging pattern for dmd.

Example:
---
import dmd.log;

private enum LOG = logAll || false;

void foo(int x)
{
    if (LOG) printf("foo was called with x = %d\n", x);
    // ...
    if (logOptimizer) printf("doing something optimizer specific...\n");
}
---

In this example, importing `dmd.log` pulls in the `printf` function along with some
boolean enum values for enabling certain categories of logging. The line:
---
private enum LOG = logAll || false;
---
defines the LOG symbol which is the module-specific variable to enable logging
related to a particular module.  A developer can change it to:
---
private enum LOG = logAll || true;
---
or they can enable ALL loging by setting logAll to `true` in this module.

Note that in the example, `if` is used instead of `static if`.  This is important
because using `if` means that the log statements will still be analyzed even if
they are disabled, meaning that log statements won't break as code changes.
*/
module dmd.log;

// mark as pure/trusted so that logging can be done in pure/safe functions
extern (C) int printf(const(char)* format, ...) pure @trusted;

enum logAll = false;
enum logGlue = logAll | false;

