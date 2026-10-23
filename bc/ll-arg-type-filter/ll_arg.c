#include <pthread.h>

/* Caller-passed mutex, unlocked only on one path. -O0 spills the
 * parameter, but the lock value still flows through the argument node.
 * An inverted type filter drops that node and this leak is not reported.
 */
void maybe(pthread_mutex_t *m, int flag) {
  pthread_mutex_lock(m);
  if (flag)
    pthread_mutex_unlock(m);
}

/* Same shape, local mutex. Reported with or without the type-filter fix. */
void maybe_local(int flag) {
  pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
  pthread_mutex_lock(&m);
  if (flag)
    pthread_mutex_unlock(&m);
}

/* Always unlocked. Must not be reported. */
void ok(pthread_mutex_t *m) {
  pthread_mutex_lock(m);
  pthread_mutex_unlock(m);
}

/* No unlock in this function. ps-ll-must-unlock-in-this-function drops
 * this even after the type-filter fix. Not part of the gate.
 */
void leak(pthread_mutex_t *m) {
  pthread_mutex_lock(m);
}
