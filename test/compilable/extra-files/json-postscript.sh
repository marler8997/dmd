#!/usr/bin/env bash

TEST_NAME=$1

echo SANITIZING JSON...
${RESULTS_DIR}/sanitize_json ${RESULTS_DIR}/compilable/${TEST_NAME}.out > ${RESULTS_DIR}/compilable/${TEST_NAME}.out.sanitized
if [ $? -ne 0 ]; then
    exit 1;
fi

diff --strip-trailing-cr compilable/extra-files/${TEST_NAME}.out ${RESULTS_DIR}/compilable/${TEST_NAME}.out.sanitized
if [ $? -ne 0 ]; then
    exit 1;
fi

rm ${RESULTS_DIR}/compilable/${TEST_NAME}.out
rm ${RESULTS_DIR}/compilable/${TEST_NAME}.out.sanitized
