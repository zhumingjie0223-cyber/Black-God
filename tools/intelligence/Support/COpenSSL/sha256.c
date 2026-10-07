#include "COpenSSL.h"
#include <openssl/sha.h>

int black_god_sha256(const uint8_t *data, size_t count, uint8_t digest[32]) {
    return SHA256(data, count, digest) != NULL;
}
