#include <stdint.h>
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

/* A store on one arm must not drop the use on the arm that never stores.
 * Both arms storing must still drop the use at the join: neither store
 * dominates it. */
void branch_partial(struct msg *m, char *dst, int cond) {
  free(m->rr);
  if (cond)
    m->rr = NULL;
  memcpy(dst, m->rr, 4);
}

void branch_else_use(struct msg *m, char *dst, int cond) {
  free(m->rr);
  if (cond)
    m->rr = NULL;
  else
    memcpy(dst, m->rr, 4);
}

void branch_sibling(struct msg *m, char *dst, int cond) {
  free(m->rr);
  if (cond)
    m->rr = NULL;
  else {
    memcpy(dst, m->rr, 4);
    return;
  }
}

void early_return_store(struct msg *m, char *dst, int cond) {
  free(m->rr);
  if (cond) {
    m->rr = NULL;
    return;
  }
  memcpy(dst, m->rr, 4);
}

void branch_both_kill(struct msg *m, char *dst, int cond) {
  free(m->rr);
  if (cond)
    m->rr = NULL;
  else
    m->rr = NULL;
  memcpy(dst, m->rr, 4);
}

void snapshot_then_store(struct msg *m, char *dst) {
  char *p = m->rr;
  m->rr = NULL;
  free(p);
  memcpy(dst, m->rr, 4);
}

void set_rr(struct msg *m, char *p) { m->rr = p; }
void touch(struct msg *m) { m->n++; }

/* Storing the freed pointer back does not change the object. */
void store_back_same(struct msg *m, char *dst) {
  char *saved = m->rr;
  free(m->rr);
  m->rr = saved;
  memcpy(dst, m->rr, 4);
}

/* A callee that writes a fresh pointer kills the cell. A callee that does
 * not write it, or that writes the freed pointer back, does not. */
void callee_fresh(struct msg *m, char *dst, char *fresh) {
  free(m->rr);
  set_rr(m, fresh);
  memcpy(dst, m->rr, 4);
}

void callee_noop(struct msg *m, char *dst) {
  free(m->rr);
  touch(m);
  memcpy(dst, m->rr, 4);
}

void callee_restore(struct msg *m, char *dst) {
  char *p = m->rr;
  free(p);
  set_rr(m, p);
  memcpy(dst, m->rr, 4);
}

void index_same(char **a, int i) {
  free(a[i]);
  (void)strlen(a[i]);
}

void index_other(char **a, int i, int j) {
  free(a[i]);
  (void)strlen(a[j]);
}

void reload_store(struct msg *m) {
  char *p = m->rr;
  m->rr = p;
}

void use_reload_store(struct msg *m, char *dst) {
  free(m->rr);
  reload_store(m);
  memcpy(dst, m->rr, 4);
}

void store_select(struct msg *m, char *fresh, int keep) {
  char *old = m->rr;
  m->rr = keep ? old : fresh;
}

void use_store_select(struct msg *m, char *dst, char *fresh, int keep) {
  free(m->rr);
  store_select(m, fresh, keep);
  memcpy(dst, m->rr, 4);
}

void index_ptr_stride(void *p, int i) {
  char **a = p;
  int **b = p;
  free(a[i]);
  (void)strlen((char *)b[i]);
}

void probe_c_const_scale(void *base, char *dst) {
  int64_t *a = base;
  char *b = base;
  free(*(char **)&a[1]);
  memcpy(dst, *(char **)&b[1], 4);
}

void probe_var_scale(void *base, int64_t i, char *dst) {
  int64_t *a = base;
  char *b = base;
  free(*(char **)&a[i]);
  memcpy(dst, *(char **)&b[i], 4);
}

/* clang -O0 splits a[i].rr into a variable index GEP and a constant field GEP. */
void field_index(struct msg *a, int i, char *dst) {
  free(a[i].rr);
  memcpy(dst, a[i].rr, 4);
}

void field_other(struct msg *a, int i, int j, char *dst) {
  free(a[i].rr);
  memcpy(dst, a[j].rr, 4);
}
