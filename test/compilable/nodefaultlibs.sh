#!/usr/bin/env bash
#
# Compile with/without -defaultlib=, make sure that the libraries
# that were linked without -defaultlib= were not linked with it
#

mkdir -p ${OUTPUT_BASE}
$DMD -m${MODEL} -of${OUTPUT_BASE}a -v ${EXTRA_FILES}/noruntime.d              > ${OUTPUT_BASE}/verbose_out_a
$DMD -m${MODEL} -of${OUTPUT_BASE}b -v ${EXTRA_FILES}/noruntime.d -defaultlib= > ${OUTPUT_BASE}/verbose_out_b

set +x
if [[ $OS = *"win"* ]]; then
    candidates="user32 kernel32"
else
    candidates="-lphobos2 -lm -lrt -ldl"
fi

found=""
for candidate in $candidates; do
    if grep -q "\\$candidate" ${OUTPUT_BASE}/verbose_out_a; then
        found="$found $candidate"
    else
        echo "did not find library $candidate"
    fi
done

echo "found these options in verbose output:$found"

fail=false
for lib in $found; do
    if grep "\\$lib" ${OUTPUT_BASE}/verbose_out_b; then
        echo "Error: found library \"$lib\" even with -defaultlib="
        fail=true
    fi
done
if $fail; then
    echo "Error: found libraries even with -defaultlib="
    exit 1
fi
