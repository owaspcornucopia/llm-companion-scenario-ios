#include "PwnedNextLlama.h"

#include "llama.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

// The native handle encapsulates both the model and its context to simplify lifetime management.
struct LlamaHandle {
    // The model remains loaded in memory for the lifetime of this handle.
    llama_model * model = nullptr;
    // The context is recreated before each request to ensure isolation between different prompts.
    llama_context * context = nullptr;
    // The context parameters are stored to allow consistent recreation of the context for each new request.
    llama_context_params context_params{};
};

// Copies a C++ string into a newly allocated C string for consumption by Swift.
char * copy_string(const std::string & value) {
    char * result = static_cast<char *>(std::malloc(value.size() + 1));
    if (result == nullptr) {
        return nullptr;
    }
    std::memcpy(result, value.c_str(), value.size() + 1);
    return result;
}

// Sets the error message for Swift to consume, allocating memory as needed.
void set_error(char ** error_message, const char * message) {
    if (error_message != nullptr) {
        *error_message = copy_string(message);
    }
}

// Collects log messages from llama.cpp for later inspection by the Swift layer.
void collect_log(ggml_log_level, const char * text, void * user_data) {
    if (text == nullptr || user_data == nullptr) {
        return;
    }
    static_cast<std::string *>(user_data)->append(text);
}

} // namespace

// Opens the GGUF model and prepares an inference context for subsequent generation requests.
extern "C" int32_t pwnednext_llama_open(
    const char * model_path,
    int32_t context_size,
    int32_t threads,
    pwnednext_llama_handle * handle,
    char ** error_message) {
    if (handle == nullptr || model_path == nullptr || model_path[0] == '\0') {
        set_error(error_message, "llama.cpp received an empty model path");
        return 1;
    }

    // Clear the output handle to prevent dangling references in case of early failure.
    *handle = nullptr;
    llama_backend_init();

    // Collect logs from the model loading process.
    std::string load_log;
    llama_log_set(collect_log, &load_log);

    // Load the GGUF model from the specified file path using the default parameters.
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;
    llama_model * model = llama_model_load_from_file(model_path, model_params);
    // Check if the model was successfully loaded.
    if (model == nullptr) {
        llama_log_set(nullptr, nullptr);
        set_error(error_message, load_log.empty() ? "llama.cpp could not load the GGUF model" : load_log.c_str());
        llama_backend_free();
        return 2;
    }
    llama_log_set(nullptr, nullptr);

    // Initialize the inference context with the specified parameters.
    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = static_cast<uint32_t>(context_size);
    context_params.n_batch = static_cast<uint32_t>(context_size);
    context_params.n_ubatch = static_cast<uint32_t>(context_size);
    context_params.n_threads = threads;
    context_params.n_threads_batch = threads;
    llama_context * context = llama_init_from_model(model, context_params);
    // Check if the context was successfully created.
    if (context == nullptr) {
        set_error(error_message, "llama.cpp could not create an inference context");
        llama_model_free(model);
        llama_backend_free();
        return 3;
    }

    LlamaHandle * native_handle = new LlamaHandle{model, context, context_params};
    *handle = native_handle;
    return 0;
}

// Generates a response from the model given a prompt, handling tokenization, context management, and error reporting.
extern "C" int32_t pwnednext_llama_generate(
    pwnednext_llama_handle handle,
    const char * prompt,
    int32_t max_tokens,
    char ** output,
    char ** error_message) {
    if (handle == nullptr || prompt == nullptr || output == nullptr || max_tokens <= 0) {
        set_error(error_message, "llama.cpp received invalid generation arguments");
        return 1;
    }

    // Initialize the output to null to ensure no stale data is returned in case of early failure.
    *output = nullptr;
    LlamaHandle * native_handle = static_cast<LlamaHandle *>(handle);
    // Reset the context so the summary prompt receives only the supplied evidence, not the prior SQL conversation.
    llama_free(native_handle->context);
    native_handle->context = llama_init_from_model(native_handle->model, native_handle->context_params);
    if (native_handle->context == nullptr) {
        set_error(error_message, "llama.cpp could not reset the inference context");
        return 2;
    }
    // The vocabulary converts the human-readable prompt into the tokens llama.cpp understands.
    const llama_vocab * vocab = llama_model_get_vocab(native_handle->model);
    const int32_t prompt_length = static_cast<int32_t>(std::strlen(prompt));
    std::vector<llama_token> tokens(static_cast<size_t>(prompt_length) + 8);
    int32_t token_count = llama_tokenize(
        vocab,
        prompt,
        prompt_length,
        tokens.data(),
        static_cast<int32_t>(tokens.size()),
        true,
        true);
    // A negative count means the first buffer was too small, so resize and try again like a very confident parser.
    if (token_count < 0) {
        tokens.resize(static_cast<size_t>(-token_count));
        token_count = llama_tokenize(vocab, prompt, prompt_length, tokens.data(), -token_count, true, false);
    }
    if (token_count <= 0) {
        set_error(error_message, "llama.cpp could not tokenize the prompt");
        return 2;
    }
    tokens.resize(static_cast<size_t>(token_count));

    // Greedy sampling keeps the generation repeatable enough for testers to compare outputs.
    llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
    llama_sampler * sampler = llama_sampler_chain_init(sampler_params);
    if (sampler == nullptr) {
        set_error(error_message, "llama.cpp could not create a sampler");
        return 3;
    }
    llama_sampler * greedy_sampler = llama_sampler_init_greedy();
    if (greedy_sampler == nullptr) {
        llama_sampler_free(sampler);
        set_error(error_message, "llama.cpp could not create a greedy sampler");
        return 3;
    }
    llama_sampler_chain_add(sampler, greedy_sampler);

    // Decode the whole prompt before asking for the first generated token.
    llama_batch batch = llama_batch_get_one(tokens.data(), token_count);
    if (llama_decode(native_handle->context, batch) != 0) {
        llama_sampler_free(sampler);
        set_error(error_message, "llama.cpp failed to decode the prompt");
        return 4;
    }

    // Keep the response
    std::string generated;
    const llama_token end_token = llama_vocab_eos(vocab);
    // Ensure the token ceiling is generous to allow for sufficiently long responses.
    for (int32_t index = 0; index < max_tokens; ++index) {
        const llama_token token = llama_sampler_sample(sampler, native_handle->context, -1);
        // Stop on the model's native end token before appending it to the visible answer.
        if (token == end_token) {
            break;
        }
        llama_sampler_accept(sampler, token);

        char piece[256];
        const int32_t piece_length = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, true);
        if (piece_length < 0) {
            llama_sampler_free(sampler);
            set_error(error_message, "llama.cpp returned an oversized token piece");
            return 5;
        }
        // Convert each token to text so the Swift layer can parse SQL or display prose.
        const std::string piece_text(piece, static_cast<size_t>(piece_length));
        if (piece_text.find("<end_of_turn>") != std::string::npos || piece_text.find("<eos>") != std::string::npos) {
            break;
        }
        generated.append(piece_text);

        // Feeding the previous token back into decode advances generation one token at a time.
        llama_token next_token = token;
        batch = llama_batch_get_one(&next_token, 1);
        if (llama_decode(native_handle->context, batch) != 0) {
            llama_sampler_free(sampler);
            set_error(error_message, "llama.cpp failed during token generation");
            return 6;
        }
    }
    // Return the generated response to the caller.
    llama_sampler_free(sampler);
    *output = copy_string(generated);
    if (*output == nullptr) {
        set_error(error_message, "llama.cpp could not allocate generated output");
        return 7;
    }
    return 0;
}

// Releases bridge-owned text allocated by the model.
extern "C" void pwnednext_llama_free_string(char * value) {
    std::free(value);
}

// Closes the native model and backend when the investigation screen finally goes away.
extern "C" void pwnednext_llama_close(pwnednext_llama_handle handle) {
    if (handle == nullptr) {
        return;
    }
    LlamaHandle * native_handle = static_cast<LlamaHandle *>(handle);
    llama_free(native_handle->context);
    llama_model_free(native_handle->model);
    delete native_handle;
    llama_backend_free();
}