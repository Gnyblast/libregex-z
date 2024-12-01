#include <regex.h>
#include <stdlib.h>

typedef struct {
    regex_t* compiled_regex;
    size_t re_nsub;
    int compile_error_code;
} compile_result;

typedef struct {
    regmatch_t* matches;
    size_t n_matches;
    int exec_code;
} exec_result;

compile_result compile_regex(const char* pattern, int flags);
void free_regex_t(regex_t* ptr);

exec_result exec(regex_t*, const char*, size_t, int);