#include <stdlib.h>
#include <string.h>

/* Two shapes from the PR #180 review.
 *
 * copy_freed: CWE-416 read of a freed byte buffer through memcpy. Current
 * main reports this. The branch returns ST_Others for every memcpy source
 * and does not transfer a byte payload, so the report disappears.
 *
 * free_rr / use_after: unbound's delfunc(void *elemptr) casts a void* to a
 * struct and frees a field (edns-subnet/subnetmod.c). kcat's buf_destroy
 * frees b->buf (github.com/edenhill/kcat input.c). clang-15 -O0 emits
 *   bitcast i8* %p to %struct.msg*
 *   getelementptr ... i32 0, i32 1
 * extractWrapperChain strips the bitcast and does not record it.
 * replayWrapperChain starts at the caller's bitcast actual and never
 * walks back to the struct whose GEP is the freed cell.
 */

struct msg {
  int n;
  char *rr;
};

void free_rr(void *p) {
  struct msg *m = p;
  free(m->rr);
}

void use_after(char *dst) {
  struct msg m;
  m.n = 1;
  m.rr = malloc(8);
  if (!m.rr)
    return;
  free_rr(&m);
  memcpy(dst, m.rr, 4);
}

void copy_freed(char *dst) {
  char *p = malloc(16);
  if (!p)
    return;
  memset(p, 'a', 8);
  free(p);
  memcpy(dst, p, 8);
}
