/* UAF false negatives from UseAfterFree::isSrcSinkNotAlias (FermatAnalyzer).
 *
 * Bug (UseAfterFree.cpp): when the freed SSA value flows into an external or
 * indirect call, checkSite asks isSrcSinkNotAlias(freeCall, useCall) and
 * suppresses the report (ST_Call) when it answers "not alias".  Two defects
 * made that answer wrong for field-derived pointers:
 *
 *   1. The CallInst-vs-CallInst case compared the SSA *value names*.  The
 *      name of an unnamed instruction is "", so free(p) vs strlen(p) compared
 *      equal and the check recursed into the FIRST arguments of two
 *      unrelated calls.
 *   2. The GEP-vs-GEP case returned true ("not alias") for every pair,
 *      including a value against itself, so a pointer loaded from a struct
 *      field (LoadInst of a GEP) was never reported.
 *
 * Every function below is a genuine use-after-free.  A fixed analyzer must
 * report all eight; an unfixed one misses f_field and m2_arg0_gep (their
 * freed pointer is field-derived) while still reporting the identical
 * malloc-derived shapes.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct s { char *data; char *buf; size_t len; };

/* --- shapes the unfixed analyzer MISSES (freed pointer is a Load of GEP) --- */

/* freed field pointer reused as arg0 of the external call */
size_t f_field(struct s *x) {
    char *p = x->data;
    free(p);
    return strlen(p);              /* UAF: read after free */
}

/* freed field pointer reused as arg2; the call's arg0 is a GEP too */
void m2_arg0_gep(struct s *x) {
    char *p = x->data;
    free(p);
    snprintf(x->buf, 32, "%s", p); /* UAF: read after free */
}

/* --- control shapes an unfixed analyzer already reports --- */

/* same as f_field but the pointer comes from malloc (CallInst provenance) */
size_t f_plain(size_t n) {
    char *p = (char *)malloc(n);
    free(p);
    return strlen(p);
}

/* freed field pointer, sink is a plain dereference (no call involved) */
int f_field_deref(struct s *x) {
    char *p = x->data;
    free(p);
    return p[0];
}

/* same as m2_arg0_gep but arg0 is a plain parameter */
void m1_arg0_plain(struct s *x, char *out) {
    char *p = x->data;
    free(p);
    snprintf(out, 32, "%s", p);
}

/* same as m2_arg0_gep but the pointer comes from malloc */
void m3_malloc_gep(struct s *x, size_t n) {
    char *p = (char *)malloc(n);
    free(p);
    snprintf(x->buf, 32, "%s", p);
}

/* scrub-after-free through memset (deref site, arg0 IS the freed value) */
void u1_malloc(struct s *x, size_t n) {
    char *p = (char *)malloc(n);
    free(p);
    memset(p, 0, n);
}

/* u1 with field provenance: still reported (deref site path) */
void u2_field(struct s *x) {
    char *p = x->data;
    free(p);
    memset(p, 0, x->len);
}
