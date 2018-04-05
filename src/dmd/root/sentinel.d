/**
Contains types to differentiate arrays with sentinel values.
*/
module dmd.root.sentinel;

extern (C++) struct SentinelPtr(T)
{
    T* ptr;
    alias ptr this;

    extern (D) private this(T* ptr)
    {
        this.ptr = ptr;
    }

    extern (D) this(SentinelPtr!T other)
    {
        this.ptr = other.ptr;
    }

    extern (D) static SentinelPtr!T nullPtr() { return SentinelPtr!T(null); }

    /**
    Convert a raw pointer `ptr` to a `SentinelPtr` without checking that
    the array it is pointing to has a sentinel value.
    Params:
        ptr = the raw pointer to be converted
    Returns:
        the given `ptr` interpreted as a `SentinelPtr`
    */
    extern (D) static SentinelPtr!T assume(T* ptr) pure
    {
        return SentinelPtr!T(ptr);
    }

    /**
    Walks the array to determine its length.
    Returns:
        the length of the array
    */
    extern(C++) size_t walkLength() const
    {
        for(size_t i = 0; ; i++)
        {
            if (ptr[i] == cast(T)0)
            {
                return i;
            }
        }
    }

    /**
    Walks the array to determine its length and then returns a `SentinelArray`.
    Returns:
        the `ptr` as a `SentinelArray`
    */
    extern (D) SentinelArray!T walkToSentinelArray() const
    {
        return SentinelArray!T(cast(T*)ptr, walkLength());
    }

    extern (D) void opAssign(SentinelPtr!T rhs)
    {
        this.ptr = rhs.ptr;
    }

    static if ( is(T U == const U) )
    {
        extern (D) this(SentinelPtr!U rhs)
        {
            this.ptr = rhs.ptr;
        }
        extern (D) void opAssign(SentinelPtr!U rhs)
        {
            this.ptr = rhs.ptr;
        }
        extern (D) static SentinelPtr!T fromPtrUnchecked(U* ptr)
        {
            return SentinelPtr!T(ptr);
        }
    }
    else
    {
        /**
        Re-interpret a "pointer to mutable data" to a "pointer to const data".
        */
        extern (D) SentinelPtr!(const(T)) asConst() const
        {
            return SentinelPtr!(const(T))(ptr);
        }
        // TODO: This would allow mutable sentinel pointer to implicitly
        //       convert to const sentinel pointers but requires multiple
        //       alias this.
        // alias asConst this;
    }

    extern (D) SentinelPtr!T opBinary(string op)(size_t rhs)
    {
        return SentinelPtr!T(mixin("this.ptr " ~ op ~ " rhs"));
    }


    /**
    Return the current value pointed to by `ptr`.
    */
    extern (D) auto front() inout { return *ptr; }

    /**
    Returns true if `ptr` is pointing at the sentinel value.
    */
    extern (D) @property bool empty() const { return *this == cast(T)0; }

    /**
    Move ptr to the next value.
    */
    extern (D) void popFront() { ptr++; }
}

/**
Convert a raw pointer `ptr` to a `SentinelPtr` without checking that
the array it is pointing to has a sentinel value.
Params:
    ptr = the raw pointer to be converted
Returns:
    the given `ptr` interpreted as a `SentinelPtr`
*/
SentinelPtr!T assumeSentinel(T)(T* ptr) pure
{
    return SentinelPtr!T.assume(ptr);
}

extern (C++) struct SentinelArray(T)
{
    union
    {
        // TODO: assert and make sure the length/ptr has the same alignment as array
        struct
        {
            size_t length;
            SentinelPtr!T ptr;
        }
        T[] array;
    }
    alias array this;

    extern (D) private this(T* ptr, size_t length) @system
    {
        this.length = length;
        this.ptr = SentinelPtr!T(ptr);
    }

    /**
    Convert a raw array `array` to a `SentinelArray` without checking that
    the array has a sentinel value.
    Params:
        array = the array to convert
    Returns:
        the given `array` interpreted as a `SentinelArray`
    */
    extern (D) static SentinelArray!T assume(T[] array) pure
    {
        return SentinelArray!T(array.ptr, array.length);
    }


    extern (D) bool opEquals(const(T)[] other) const
    {
        return array == other;
    }

    /**
    A no-op that just returns the array as is.  This is to be useful for templates that can accept
    normal arrays an sentinel arrays. The function is marked as `@system` not because it is unsafe
    but because it should only be called in unsafe code, mirroring the interface of the free function
    version of asSentinelArray.
    Returns:
        this
    */
    pragma(inline) auto asSentinelArray() @system inout { return this; }
    /// ditto
    pragma(inline) auto asSentinelArrayUnchecked() @system inout { return this; }
}

/**
Convert a raw array `array` to a `SentinelArray` without checking that
the array has a sentinel value.
Params:
    array = the array to convert
Returns:
    the given `array` interpreted as a `SentinelArray`
*/
SentinelArray!T assumeSentinel(T)(T[] array) pure
{
    return SentinelArray!T.assume(array);
}


/**
Coerce the given `array` to a `SentinelPtr`. It checks and asserts
if the given array does not contain the sentinel value at `array.ptr[array.length]`.
*/
@property auto asSentinelPtr(T)(T[] array) @system
{
    return SentinelPtr!T(array);
}
/// ditto
@property auto asSentinelPtr(T)(T[] array) @system
{
    return SentinelPtr!T(array);
}

/**
Coerce the given `array` to a `SentinelPtr` without verifying that it
contains the sentinel value at `array.ptr[array.length]`.
*/
@property auto asSentinelPtrUnchecked(T)(T[] array) @system
{
    SentinelPtr!T sp = void;
    sp.ptr = array.ptr;
    return sp;
}
@property auto asSentinelPtrUnchecked(alias sentinelValue, T)(T[] array) @system
    if (is(typeof(sentinelValue == T.init)))
{
    SentinelPtr!T sp = void;
    sp.ptr = array.ptr;
    return sp;
}
/**
Create a SentinelPtr from a normal pointer without checking
that the array it is pointing to contains the sentinel value.
*/
@property auto asSentinelPtrUnchecked(T)(T* ptr) @system
{
    SentinelPtr!T sp = void;
    sp.ptr = ptr;
    return sp;
}

unittest
{
    auto s1 = "abcd".asSentinelPtr;
    auto s2 = "abcd".asSentinelPtrUnchecked;
    auto s3 = "abcd".ptr.asSentinelPtrUnchecked;

    auto full = "abcd-";
    auto s = full[0..4];
    auto s4 = s.asSentinelPtr!'-';
    auto s5 = s.asSentinelPtrUnchecked!'-';
}

/**
Coerce the given `array` to a `SentinelArray`. It checks and asserts
if the given array does not contain the sentinel value at `array.ptr[array.length]`.
*/
@property auto asSentinelArray(T)(T[] array) @system
{
    return SentinelArray!T(array);
}
/// ditto
@property auto asSentinelArray(alias sentinelValue, T)(T[] array) @system
    if (is(typeof(sentinelValue == T.init)))
{
    return SentinelArray!(T, sentinelValue)(array);
}

/**
Coerce the given `array` to a `SentinelArray` without verifying that it
contains the sentinel value at `array.ptr[array.length]`.
*/
@property auto asSentinelArrayUnchecked(T)(T[] array) @system
{
    SentinelArray!T sa = void;
    sa.array = array;
    return sa;
}
/// ditto
@property auto asSentinelArrayUnchecked(alias sentinelValue, T)(T[] array) @system
    if (is(typeof(sentinelValue == T.init)))
{
    SentinelArray!T sa = void;
    sa.array = array;
    return sa;
}

unittest
{
    auto s1 = "abcd".asSentinelArray;
    auto s2 = "abcd".asSentinelArrayUnchecked;

    auto full = "abcd-";
    auto s = full[0..4];
    auto s3 = s.asSentinelArray!'-';
    auto s4 = s.asSentinelArrayUnchecked!'-';
}

// test as ranges
unittest
{
    {
        auto s = "abcd".asSentinelPtr;
        size_t count = 0;
        foreach(c; s) { count++; }
        assert(count == 4);
    }
    {
        auto s = "abcd".asSentinelArray;
        size_t count = 0;
        foreach(c; s) { count++; }
        assert(count == 4);
    }
    auto abcd = "abcd";
    {
        auto s = abcd[0..3].asSentinelPtr!'d';
        size_t count = 0;
        foreach(c; s) { count++; }
        assert(count == 3);
    }
    {
        auto s = abcd[0..3].asSentinelArray!'d';
        size_t count = 0;
        foreach(c; s) { count++; }
        assert(count == 3);
    }
}

/**
A is a pointer to an array of characters ended with a null-terminator.
*/
alias cstring = SentinelPtr!(const(char));
/// ditto
alias mutable_cstring = SentinelPtr!char;
/// ditto
alias wide_cstring = SentinelPtr!(const(wchar));
/// ditto
alias mutable_wide_ctring = SentinelPtr!wchar;
/// ditto
alias dwide_cstring = SentinelPtr!(const(dchar));
/// ditto
alias mutable_dwide_cdstring = SentinelPtr!dchar;

unittest
{
    auto p1 = "hello".asSentinelPtr;
    auto p2 = "hello".asSentinelPtrUnchecked;
    assert(p1.walkLength() == 5);
    assert(p2.walkLength() == 5);

    assert(p1.toArray() == "hello");
    assert(p2.toArray() == "hello");
}

version(unittest)
{
    // demonstrate that C functions can be redefined using SentinelPtr
    extern (C) size_t strlen(cstring str);
}

/+
/**
Used to interpret string literals as `SentinelArray`s.
*/
template literal(string s)
{
    immutable literal = SentinelArray!(const(char)).assume(s);
}
+/

unittest
{
    assert(5 == strlen(StringLiteral!"hello".ptr));

    // NEED MULTIPLE ALIAS THIS to allow SentinelArray to implicitly convert to SentinelPtr
    //assert(5 == strlen(StringLiteral!"hello"));

    // type of string literals should be changed to SentinelString in order for this to work
    //assert(5 == strlen("hello".ptr");

    // this requires both conditions above to work
    //assert(5 == strlen("hello"));
}

unittest
{
    char[10] buffer = void;
    buffer[0 .. 5] = "hello";
    buffer[5] = '\0';
    SentinelArray!char hello = buffer[0..5].asSentinelArray;
    assert(5 == strlen(hello.ptr));
}

// Check that sentinel types can be passed to functions
// with mutable/immutable implicitly converting to const
unittest
{
    static void mutableFooArray(SentinelArray!char str) { }
    mutableFooArray((cast(char[])"hello").asSentinelArray);

    static void constFooArray(SentinelArray!(const(char)) str) { }
    constFooArray("hello".asSentinelArray);
    constFooArray(StringLiteral!"hello");
    constFooArray((cast(const(char)[])"hello").asSentinelArray);
    constFooArray((cast(char[])"hello").asSentinelArray);

    // NOTE: this only works if type of string literals is changed to SentinelString
    //constFooArray("hello");

    static void mutableFooPtr(SentinelPtr!char str) { }
    mutableFooPtr((cast(char[])"hello").asSentinelArray.ptr);

    static void fooPtr(cstring str) { }
    fooPtr("hello".asSentinelArray.ptr);
    fooPtr(StringLiteral!"hello".ptr);
    fooPtr((cast(const(char)[])"hello").asSentinelArray.ptr);
    fooPtr((cast(char[])"hello").asSentinelArray.ptr);
}

// Check that sentinel array/ptr implicitly convert to non-sentinel array/ptr
unittest
{
    static void mutableFooArray(char[] str) { }
    // NEED MULTIPLE ALIAS THIS !!!
    //mutableFooArray((cast(char[])"hello").asSentinelArray);

    static void constFooArray(const(char)[] str) { }
    constFooArray((cast(char[])"hello").asSentinelArray);
    constFooArray((cast(const(char)[])"hello").asSentinelArray);
    constFooArray("hello".asSentinelArray);
    constFooArray(StringLiteral!"hello");

    static void mutableFooPtr(char* str) { }
    // NEED MULTIPLE ALIAS THIS !!!
    //mutableFooPtr((cast(char[])"hello").asSentinelArray.ptr);

    static void constFooPtr(const(char)* str) { }
    constFooPtr((cast(char[])"hello").asSentinelArray.ptr);
    constFooPtr((cast(const(char)[])"hello").asSentinelArray.ptr);
    constFooPtr("hello".asSentinelArray.ptr);
    constFooPtr(StringLiteral!"hello".ptr);
}

/**
A template that coerces a string literal to a SentinelString.
Note that this template becomes unnecessary if the type of string literal
is changed to SentinelString.
*/
pragma(inline) @property SentinelString StringLiteral(string s)() @trusted
{
   SentinelString ss = void;
   ss.array = s;
   return ss;
}
/// ditto
pragma(inline) @property SentinelWstring StringLiteral(wstring s)() @trusted
{
   SentinelWstring ss = void;
   ss.array = s;
   return ss;
}
/// ditto
pragma(inline) @property SentinelDstring StringLiteral(dstring s)() @trusted
{
   SentinelDstring ss = void;
   ss.array = s;
   return ss;
}

unittest
{
    // just instantiate for now to make sure they compile
    auto sc = StringLiteral!"hello";
    auto sw = StringLiteral!"hello"w;
    auto sd = StringLiteral!"hello"d;
}

/**
This function converts an array to a SentinelArray.  It requires that the last element `array[$-1]`
be equal to the sentinel value. This differs from the function `asSentinelArray` which requires
the first value outside of the bounds of the array `array[$]` to be equal to the sentinel value.
This function does not require the array to "own" elements outside of its bounds.
*/
@property auto reduceToSentinelArray(T)(T[] array) @trusted
in {
    assert(array.length > 0);
    assert(array[$ - 1] == defaultSentinel!T);
   } do
{
    return asSentinelArrayUnchecked(array[0 .. $-1]);
}
/// ditto
@property auto reduceToSentinelArray(alias sentinelValue, T)(T[] array) @trusted
    if (is(typeof(sentinelValue == T.init)))
    in {
        assert(array.length > 0);
        assert(array[$ - 1] == sentinelValue);
    } do
{
    return array[0 .. $ - 1].asSentinelArrayUnchecked!sentinelValue;
}

///
@safe unittest
{
    auto s1 = "abc\0".reduceToSentinelArray;
    assert(s1.length == 3);
    () @trusted {
        assert(s1.ptr[s1.length] == '\0');
    }();

    auto s2 = "foobar-".reduceToSentinelArray!'-';
    assert(s2.length == 6);
    () @trusted {
        assert(s2.ptr[s2.length] == '-');
    }();
}

// poor mans Unqual
private template Unqual(T)
{
         static if (is(T U ==     const U)) alias Unqual = U;
    else static if (is(T U == immutable U)) alias Unqual = U;
    else                                    alias Unqual = T;
}
