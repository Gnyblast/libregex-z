#include "regex_adapter.h"
#include <stdio.h>

void free_regex_t(regex_t* ptr) {
    regfree(ptr);
    free(ptr);
}

compile_result compile_regex(const char* pattern, int flags) {
    compile_result result;

    result.compiled_regex = (regex_t*)malloc(sizeof(regex_t));
    result.compile_error_code = regcomp(result.compiled_regex, pattern, flags);
    result.re_nsub = result.compiled_regex->re_nsub;

    return result;
}
