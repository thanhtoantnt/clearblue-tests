#include <stdio.h>
#include <stdlib.h>

struct Box {
  int *p;
  FILE *f;
};

void leak_field(void) {
  struct Box b;
  b.p = malloc(sizeof(int));
  if (!b.p)
    return;
  *b.p = 1;
}

void leak_file(const char *path) {
  struct Box b;
  b.f = fopen(path, "r");
  if (!b.f)
    return;
  fgetc(b.f);
}

void saved_field(struct Box *out) { out->p = malloc(sizeof(int)); }

void saved_file(struct Box *out, const char *path) { out->f = fopen(path, "r"); }

void freed_field(void) {
  struct Box b;
  b.p = malloc(sizeof(int));
  if (!b.p)
    return;
  free(b.p);
}

void closed_file(const char *path) {
  struct Box b;
  b.f = fopen(path, "r");
  if (!b.f)
    return;
  fclose(b.f);
}

void handoff_field(void (*consume)(struct Box *)) {
  struct Box b;
  b.p = malloc(sizeof(int));
  if (!b.p)
    return;
  consume(&b);
}
