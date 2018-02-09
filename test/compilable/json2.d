/*
PERMUTE_ARGS:
ARG_SETS: -o- -Xf=${RESULTS_DIR}/compilable/json2.out -Xq=compilerInfo,buildInfo,modules,semantics
ARG_SETS: -o- -Xf=${RESULTS_DIR}/compilable/json2.out "-Xq=compilerInfo buildInfo modules semantics"
POST_SCRIPT: compilable/extra-files/json-postscript.sh json2
*/
import json;
