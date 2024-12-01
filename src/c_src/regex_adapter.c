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

exec_result exec(regex_t* ptr, const char* input, size_t re_nsub, int flags) {
    exec_result result;

    result.n_matches = (re_nsub + 1);
    result.matches = (regmatch_t*)malloc(result.n_matches * sizeof(regmatch_t));
    result.exec_code = regexec(ptr, input, result.n_matches, result.matches, flags);
    
    return result;
}
