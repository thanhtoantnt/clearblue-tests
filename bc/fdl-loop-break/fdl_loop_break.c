#include <sys/socket.h>
#include <unistd.h>

struct node {
  struct node *next;
};
struct out {
  int fd;
};

/* The FP shape (mcmc_connect): the post-loop cursor==NULL error return is
 * unreachable on the break path because the loop header tested the cursor
 * non-null and the break bypasses the advance. Not a leak. */
int not_a_leak(struct node *head, struct out *o) {
  struct node *next = head;
  int fd = -1;
  while (next) {
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
      return -1;
    if (next->next == (struct node *)1) /* stands in for connect() ok */
      break;
    close(fd);
    next = next->next;
  }
  if (next == 0)
    return -1;
  o->fd = fd;
  return 0;
}

/* Control: the break path really does leak. The post-loop return tests a
 * different condition, not the cursor, so this must stay reported. */
int real_leak_on_break(struct node *head, struct out *o, int late) {
  struct node *next = head;
  int fd;
  while (next) {
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
      return -1;
    if (late)
      break;
    close(fd);
    next = next->next;
  }
  if (next == 0)
    return -1;
  if (late)
    return -1; /* fd live */
  o->fd = fd;
  return 0;
}

/* Review: an unrelated indirect call on the feasible side is not a
 * release. The leak is the return after that call. Must stay reported. */
int leak_after_unrelated_call(struct node *head, struct out *o,
                              void (*cb)(int), int late) {
  struct node *next = head;
  int fd;
  while (next) {
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
      return -1;
    if (late)
      break;
    close(fd);
    next = next->next;
  }
  if (next == 0)
    return -1;
  cb(0);
  if (late)
    return -1; /* fd live */
  o->fd = fd;
  return 0;
}

/* Same handoff as not_a_leak, but the feasible side passes the descriptor
 * to an indirect call. That matches checkSite and must stay quiet. */
int saved_by_callback(struct node *head, void (*cb)(int)) {
  struct node *next = head;
  int fd = -1;
  while (next) {
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
      return -1;
    if (next->next == (struct node *)1)
      break;
    close(fd);
    next = next->next;
  }
  if (next == 0)
    return -1;
  cb(fd);
  return 0;
}

/* Control: the normal exit really does leak — the loop body never closes
 * before advancing. Must stay reported. */
int real_leak_on_normal_exit(struct node *head, struct out *o) {
  struct node *next = head;
  int fd = -1;
  while (next) {
    if (fd < 0)
      fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
      return -1;
    next = next->next;
  }
  if (next == 0)
    return -1; /* fd live */
  o->fd = fd;
  return 0;
}
