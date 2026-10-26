#include <search.h>
#include <stdlib.h>
#include <string.h>

/* getenv / strrchr / strpbrk / memmem return NULL when nothing is found.
 * strchr is in the analyzer's null-return table; these mirrors were not,
 * so an unchecked deref of them was never a source. */

void getenv_unchecked(void) {
  char *s = getenv("HOME");
  *s = 'x'; /* NPD */
}

void getenv_checked(void) {
  char *s = getenv("HOME");
  if (!s)
    return;
  *s = 'x';
}

void strrchr_unchecked(char *p) {
  char *q = strrchr(p, 'a');
  *q = 'x'; /* NPD */
}

void strrchr_checked(char *p) {
  char *q = strrchr(p, 'a');
  if (!q)
    return;
  *q = 'x';
}

void strpbrk_unchecked(char *p) {
  char *q = strpbrk(p, "ab");
  *q = 'x'; /* NPD */
}

void memmem_unchecked(char *h, size_t n, char *nd, size_t m) {
  char *q = memmem(h, n, nd, m);
  *q = 'x'; /* NPD */
}

void bsearch_unchecked(const void *key, const void *base, size_t nm,
                       size_t sz, int (*cmp)(const void *, const void *)) {
  void *q = bsearch(key, base, nm, sz, cmp);
  *(int *)q = 1; /* NPD */
}

void strchr_baseline(char *p) {
  char *q = strchr(p, 'a');
  *q = 'x'; /* NPD: already in the table */
}
