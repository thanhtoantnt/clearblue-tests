#include <stdio.h>
#include <stdlib.h>

struct Inner {
  char *name;
};

struct Box {
  int *p;
  FILE *f;
  struct Inner in;
  FILE *slots[2];
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

void leak_calloc(void) {
  struct Box b;
  b.p = calloc(4, sizeof(int));
  if (!b.p)
    return;
  b.p[0] = 1;
}

void leak_nested(const char *s) {
  struct Box b;
  b.in.name = malloc(8);
  if (!b.in.name)
    return;
  b.in.name[0] = s ? s[0] : 0;
}

void leak_slot(const char *path) {
  struct Box b;
  b.slots[0] = fopen(path, "r");
  if (!b.slots[0])
    return;
  fgetc(b.slots[0]);
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

struct Box make_field(void) {
  struct Box b;
  b.p = malloc(sizeof(int));
  return b;
}

struct Wide {
  int *p;
  char pad[64];
};

struct Wide *copy_out(void) {
  struct Wide b;
  struct Wide *out;
  b.p = malloc(sizeof(int));
  if (!b.p)
    return 0;
  out = malloc(sizeof(b));
  if (!out)
    return 0;
  *out = b;
  return out;
}

void pass_by_value(void (*use)(struct Box)) {
  struct Box b;
  b.p = malloc(sizeof(int));
  if (!b.p)
    return;
  use(b);
}

void handoff_field(void (*consume)(struct Box *)) {
  struct Box b;
  b.p = malloc(sizeof(int));
  if (!b.p)
    return;
  consume(&b);
}
