#!/usr/bin/env bash
#
# Compile with/without -nodefaultlibs, make sure that the libraries
# that were linked without -nodefaultlibs were not linked with it
#

$DMD -m${MODEL} -of${OUTPUT_BASE}a -v ${EXTRA_FILES}/noruntime.d                > ${RESULTS_TEST_DIR}/verbose_out_a
$DMD -m${MODEL} -of${OUTPUT_BASE}b -v ${EXTRA_FILES}/noruntime.d -nodefaultlibs > ${RESULTS_TEST_DIR}/verbose_out_b

set +x

candidates="-lphobos2 -lm -lrt -ldl"
if [[ $OS = *"win"* ]]; then
    candidates="$candidates user32 kernel32"
fi

found=""
for candidate in $candidates; do
    if grep -q "\\$candidate" ${RESULTS_TEST_DIR}/verbose_out_a; then
        found="$found $candidate"
    else
        echo "did not find library $candidate"
    fi
done

echo "found these options in verbose output:$found"

fail=false
for lib in $found; do
    if grep "\\$lib" ${RESULTS_TEST_DIR}/verbose_out_b; then
        echo "Error: found library \"$lib\" even with -nodefaultlibs"
        fail=true
    fi
done
if $fail; then
    echo "Error: found libraries even with -nodefaultlibs"
    exit 1
fi
