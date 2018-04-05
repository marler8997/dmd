#ifndef ROOT_SENTINEL_H
#define ROOT_SENTINEL_H



template<typename T>
struct SentinelPtr
{
public:
    T* ptr;
    operator T*() const { return ptr; }

private:
    SentinelPtr(T* ptr) : ptr(ptr)
    {
    }

public:
    static SentinelPtr assume(T* ptr)
    {
        return SentinelPtr(ptr);
    }

    size_t walkLength() const;
};

#define cstring         SentinelPtr<const char>
#define mutable_cstring SentinelPtr<char>

template <typename T>
struct SentinelArray
{
    size_t length;
    SentinelPtr<T> ptr;
};

#endif /* ROOT_SENTINEL_H */
