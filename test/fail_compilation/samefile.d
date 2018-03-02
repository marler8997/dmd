/*
ARG_SETS: fail_compilation/samefile.d
ARG_SETS: ./fail_compilation/samefile.d
ARG_SETS: fail_compilation/../fail_compilation/samefile.d
ARG_SETS: fail_compilation/./samefile.d
TEST_OUTPUT:
---
Error: module `samefile` from file fail_compilation/samefile.d is specified twice on the command line
---
*/
void main() { }