#ifndef BLACK_GOD_C_OPENSSL_H
#define BLACK_GOD_C_OPENSSL_H
#include <stddef.h>
#include <stdint.h>
int black_god_sha256(const uint8_t *data, size_t count, uint8_t digest[32]);
#endif
