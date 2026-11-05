#include <stdlib.h>
#include <string.h>

/* UAF false negatives: free(cell); use(cell) is two loads of one cell.
 *
 * After mem2reg the two field accesses are different SSA values. The search
 * starts at the load passed to free and never reaches the later load, so
 * the use is not reported. A wrapper that frees the pointer itself has the
 * same hole: the summary is installed on the actual load, not on a later
 * load of that cell.
 *
 * An unfixed analyzer misses the four direct reloads. wrap_reload_ptr is
 * already reported through the wrapper summary; it stays so that path is not
 * dropped. The "must not report" group is a reassignment, a different index,
 * or two overlaid struct pointers at one offset (libevent's extra slot).
 */

struct msg {
  int n;
  char *rr;
  char buf[8];
};

struct seg {
  struct seg *contents;
};
struct parent {
  struct parent *source;
};
union extra {
  struct seg seg;
  struct parent mc;
};

void my_free(void *p) {
  if (p)
    free(p);
}

/* --- must report --- */

void reload_field(struct msg *m, char *dst) {
  free(m->rr);
  memcpy(dst, m->rr, 4);
}

void reload_strlen(struct msg *m) {
  free(m->rr);
  (void)strlen(m->rr);
}

void double_reload(struct msg *m) {
  free(m->rr);
  free(m->rr);
}

void use_before_null(struct msg *m, char *dst) {
  free(m->rr);
  memcpy(dst, m->rr, 4);
  m->rr = NULL;
}

void wrap_reload_ptr(struct msg *m, char *dst) {
  my_free(m->rr);
  memcpy(dst, m->rr, 4);
}

/* --- must not report --- */

void killed_store(struct msg *m, char *dst) {
  free(m->rr);
  m->rr = NULL;
  if (m->rr)
    memcpy(dst, m->rr, 4);
}

void killed_memset(struct msg *m) {
  free(m->rr);
  memset(m, 0, sizeof(*m));
  (void)strlen(m->rr);
}

void other_index(char **a) {
  free(a[0]);
  (void)strlen(a[1]);
}

void overlay_fp(union extra *e) {
  free(e->seg.contents);
  if (e->mc.source)
    e->mc.source->source = 0;
}
