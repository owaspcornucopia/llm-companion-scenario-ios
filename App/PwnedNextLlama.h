#ifndef PWNEDNEXT_LLAMA_H
#define PWNEDNEXT_LLAMA_H

#include <stdint.h>

/* The C ABI keeps Swift away from C++ ownership details. */

#ifdef __cplusplus
extern "C" {
#endif

typedef void * pwnednext_llama_handle;

/* Opens the downloaded GGUF and creates the CPU inference context. */
int32_t pwnednext_llama_open(
    const char * model_path,
    int32_t context_size,
    int32_t threads,
    pwnednext_llama_handle * handle,
    char ** error_message);

/* Generates either the SQL tool call or the natural-language interpretation. */
int32_t pwnednext_llama_generate(
    pwnednext_llama_handle handle,
    const char * prompt,
    int32_t max_tokens,
    char ** output,
    char ** error_message);

/* Frees strings allocated by the native bridge. C memory does not clean itself up. */
void pwnednext_llama_free_string(char * value);
/* Releases the model and context after the app is done using them. */
void pwnednext_llama_close(pwnednext_llama_handle handle);

#ifdef __cplusplus
}
#endif

#endif