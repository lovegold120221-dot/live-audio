#include <jni.h>
#include <android/log.h>
#include <cstring>
#include <string>
#include <vector>
#include <mutex>
#include <atomic>
#include <sstream>

#include "llama.h"

#define LOG_TAG "LlamaBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ---------------------------------------------------------------------------
//  Global state
// ---------------------------------------------------------------------------
static struct {
    llama_model          * model               = nullptr;
    llama_context        * ctx                 = nullptr;
    llama_sampler        * sampler             = nullptr;
    const llama_vocab    * vocab               = nullptr;
    std::mutex             mtx;
    std::atomic<bool>      stop_requested{false};
    std::atomic<bool>      generating{false};
    JavaVM               * jvm                 = nullptr;
} g_state;

// ---------------------------------------------------------------------------
//  JNI on-load – cache JavaVM
// ---------------------------------------------------------------------------
jint JNI_OnLoad(JavaVM *vm, void *) {
    g_state.jvm = vm;
    LOGI("JNI_OnLoad – JavaVM cached");
    return JNI_VERSION_1_6;
}

// ---------------------------------------------------------------------------
//  Helper: get a JNIEnv* for the current thread
// ---------------------------------------------------------------------------
static JNIEnv *get_env() {
    JNIEnv *env = nullptr;
    if (g_state.jvm->GetEnv((void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        g_state.jvm->AttachCurrentThread(&env, nullptr);
    }
    return env;
}

// ---------------------------------------------------------------------------
//  Helper: create the greedy sampler chain (must hold lock)
// ---------------------------------------------------------------------------
static bool create_sampler() {
    if (g_state.sampler) {
        llama_sampler_free(g_state.sampler);
        g_state.sampler = nullptr;
    }
    auto sparams = llama_sampler_chain_default_params();
    g_state.sampler = llama_sampler_chain_init(sparams);
    if (!g_state.sampler) {
        LOGE("Failed to create sampler chain");
        return false;
    }
    // Greedy sampling — always picks the most likely token
    llama_sampler_chain_add(g_state.sampler, llama_sampler_init_greedy());
    return true;
}

// ---------------------------------------------------------------------------
//  JNI: nativeLoadModel
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_com_privateagent_llama_1native_LlamaNativePlugin_nativeLoadModel(
    JNIEnv *env, jclass, jstring j_model_path) {

    std::lock_guard<std::mutex> lock(g_state.mtx);

    // Cleanup previous state
    if (g_state.sampler) { llama_sampler_free(g_state.sampler); g_state.sampler = nullptr; }
    if (g_state.ctx)     { llama_free(g_state.ctx);            g_state.ctx     = nullptr; }
    if (g_state.model)   { llama_model_free(g_state.model);    g_state.model   = nullptr; }
    g_state.vocab = nullptr;

    const char *model_path = env->GetStringUTFChars(j_model_path, nullptr);
    LOGI("Loading model: %s", model_path);

    // Backend init (idempotent)
    llama_backend_init();

    // Model params — CPU-only for broadest Android compat
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;

    g_state.model = llama_model_load_from_file(model_path, model_params);
    env->ReleaseStringUTFChars(j_model_path, model_path);

    if (!g_state.model) {
        LOGE("Failed to load model");
        return JNI_FALSE;
    }

    // Get vocab reference
    g_state.vocab = llama_model_get_vocab(g_state.model);
    if (!g_state.vocab) {
        LOGE("Failed to get vocab");
        llama_model_free(g_state.model);
        g_state.model = nullptr;
        return JNI_FALSE;
    }

    // Context params
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx           = 2048;
    ctx_params.n_batch         = 512;
    ctx_params.n_threads       = 4;
    ctx_params.n_threads_batch = 4;

    g_state.ctx = llama_init_from_model(g_state.model, ctx_params);
    if (!g_state.ctx) {
        LOGE("Failed to create context");
        llama_model_free(g_state.model);
        g_state.model = nullptr;
        g_state.vocab = nullptr;
        return JNI_FALSE;
    }

    // Create sampler
    if (!create_sampler()) {
        llama_free(g_state.ctx);
        g_state.ctx = nullptr;
        llama_model_free(g_state.model);
        g_state.model = nullptr;
        g_state.vocab = nullptr;
        return JNI_FALSE;
    }

    LOGI("Model loaded successfully");
    return JNI_TRUE;
}

// ---------------------------------------------------------------------------
//  JNI: nativeIsModelLoaded
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_com_privateagent_llama_1native_LlamaNativePlugin_nativeIsModelLoaded(
    JNIEnv *, jclass) {
    return (g_state.model != nullptr && g_state.ctx != nullptr)
           ? JNI_TRUE : JNI_FALSE;
}

// ---------------------------------------------------------------------------
//  JNI: nativeGetModelInfo
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT jobject JNICALL
Java_com_privateagent_llama_1native_LlamaNativePlugin_nativeGetModelInfo(
    JNIEnv *env, jclass) {

    jclass hashmap_class = env->FindClass("java/util/HashMap");
    jmethodID hashmap_init = env->GetMethodID(hashmap_class, "<init>", "()V");
    jmethodID hashmap_put = env->GetMethodID(
        hashmap_class, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jobject map = env->NewObject(hashmap_class, hashmap_init);

    std::lock_guard<std::mutex> lock(g_state.mtx);
    if (g_state.model && g_state.ctx && g_state.vocab) {
        int n_ctx   = llama_n_ctx(g_state.ctx);
        int n_vocab = llama_vocab_n_tokens(g_state.vocab);

        auto put_int = [&](const char *key, int val) {
            jstring j_key = env->NewStringUTF(key);
            auto integer_class = env->FindClass("java/lang/Integer");
            jmethodID int_init = env->GetMethodID(integer_class, "<init>", "(I)V");
            jobject j_val = env->NewObject(integer_class, int_init, val);
            env->CallObjectMethod(map, hashmap_put, j_key, j_val);
            env->DeleteLocalRef(j_val);
            env->DeleteLocalRef(j_key);
        };

        put_int("contextSize",    n_ctx);
        put_int("vocabularySize", n_vocab);
    }

    return map;
}

// ---------------------------------------------------------------------------
//  Internal: do one step of generation (eval + sample)
//  Returns the decoded token string, or empty on EOS/stop.
//  Caller must hold g_state.mtx.
// ---------------------------------------------------------------------------
static std::string generate_token() {
    if (!g_state.model || !g_state.ctx || !g_state.vocab || !g_state.sampler ||
        g_state.stop_requested) {
        return "";
    }

    // Sample using the greedy sampler chain
    llama_token token_id = llama_sampler_sample(
        g_state.sampler, g_state.ctx, -1);

    if (token_id == LLAMA_TOKEN_NULL ||
        llama_vocab_is_eog(g_state.vocab, token_id)) {
        return "";
    }

    // Decode token to text
    std::vector<char> piece(8, 0);
    int n = llama_token_to_piece(
        g_state.vocab, token_id,
        piece.data(), (int)piece.size(), 0, false);

    // Feed token back for next iteration
    llama_decode(g_state.ctx,
                 llama_batch_get_one(&token_id, 1));

    if (n > 0) {
        return std::string(piece.data(), n);
    }
    return "";
}

// ---------------------------------------------------------------------------
//  Internal: tokenize + eval the prompt. Caller must hold g_state.mtx.
// ---------------------------------------------------------------------------
static bool eval_prompt(const std::string &prompt) {
    if (!g_state.model || !g_state.ctx || !g_state.vocab) return false;

    int n_tokens = llama_tokenize(
        g_state.vocab,
        prompt.data(), (int)prompt.size(),
        nullptr, 0, true, false);
    if (n_tokens <= 0) return false;

    std::vector<llama_token> tokens(n_tokens);
    llama_tokenize(
        g_state.vocab,
        prompt.data(), (int)prompt.size(),
        tokens.data(), n_tokens, true, false);

    // Reset sampler state before processing new prompt
    llama_sampler_reset(g_state.sampler);

    llama_decode(g_state.ctx,
                 llama_batch_get_one(tokens.data(), (int)tokens.size()));
    return true;
}

// ---------------------------------------------------------------------------
//  JNI: nativeGenerate (blocking, returns full text)
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT jstring JNICALL
Java_com_privateagent_llama_1native_LlamaNativePlugin_nativeGenerate(
    JNIEnv *env, jclass, jstring j_prompt, jint j_max_tokens) {

    std::lock_guard<std::mutex> lock(g_state.mtx);

    const char *prompt_c = env->GetStringUTFChars(j_prompt, nullptr);
    std::string prompt(prompt_c);
    env->ReleaseStringUTFChars(j_prompt, prompt_c);

    if (!eval_prompt(prompt)) {
        return env->NewStringUTF("");
    }

    g_state.stop_requested = false;
    g_state.generating = true;

    std::string result;
    int max_tokens = (int)j_max_tokens;

    for (int i = 0; i < max_tokens; i++) {
        if (g_state.stop_requested) {
            LOGI("Generation stopped by user");
            break;
        }

        std::string piece = generate_token();
        if (piece.empty()) break;
        result.append(piece);
    }

    g_state.generating = false;
    return env->NewStringUTF(result.c_str());
}

// ---------------------------------------------------------------------------
//  JNI: nativeGenerateInit – tokenize prompt & set up generation state.
// ---------------------------------------------------------------------------
static bool g_gen_initialized = false;

extern "C" JNIEXPORT jboolean JNICALL
Java_com_privateagent_llama_1native_LlamaNativePlugin_nativeGenerateInit(
    JNIEnv *env, jclass, jstring j_prompt, jint j_max_tokens) {

    std::lock_guard<std::mutex> lock(g_state.mtx);

    const char *prompt_c = env->GetStringUTFChars(j_prompt, nullptr);
    std::string prompt(prompt_c);
    env->ReleaseStringUTFChars(j_prompt, prompt_c);

    g_state.stop_requested = false;
    g_state.generating = true;

    if (!eval_prompt(prompt)) {
        g_state.generating = false;
        return JNI_FALSE;
    }

    g_gen_initialized = true;
    return JNI_TRUE;
}

// ---------------------------------------------------------------------------
//  JNI: nativeGenerateNext – generate and return the next token string.
//  Returns empty string when generation is complete or stopped.
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT jstring JNICALL
Java_com_privateagent_llama_1native_LlamaNativePlugin_nativeGenerateNext(
    JNIEnv *env, jclass) {

    if (g_state.stop_requested) {
        g_state.generating = false;
        return env->NewStringUTF("");
    }

    // try_lock so we don't block the platform thread if the model is busy
    if (!g_state.mtx.try_lock()) {
        return env->NewStringUTF("");
    }

    std::string piece = generate_token();

    if (piece.empty()) {
        g_state.generating = false;
        g_state.mtx.unlock();
        return env->NewStringUTF("");
    }

    g_state.mtx.unlock();
    return env->NewStringUTF(piece.c_str());
}

// ---------------------------------------------------------------------------
//  JNI: nativeGenerateFinish – clean up generation state.
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT void JNICALL
Java_com_privateagent_llama_1native_LlamaNativePlugin_nativeGenerateFinish(
    JNIEnv *, jclass) {
    g_state.generating = false;
    g_gen_initialized = false;
}

// ---------------------------------------------------------------------------
//  JNI: nativeStopGeneration
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT void JNICALL
Java_com_privateagent_llama_1native_LlamaNativePlugin_nativeStopGenerating(
    JNIEnv *, jclass) {
    g_state.stop_requested = true;
}

// ---------------------------------------------------------------------------
//  JNI: nativeUnloadModel
// ---------------------------------------------------------------------------
extern "C" JNIEXPORT void JNICALL
Java_com_privateagent_llama_1native_LlamaNativePlugin_nativeUnloadModel(
    JNIEnv *, jclass) {

    std::lock_guard<std::mutex> lock(g_state.mtx);
    g_state.stop_requested = true;
    g_state.generating = false;
    g_gen_initialized = false;

    if (g_state.sampler) { llama_sampler_free(g_state.sampler); g_state.sampler = nullptr; }
    if (g_state.ctx)     { llama_free(g_state.ctx);            g_state.ctx     = nullptr; }
    if (g_state.model)   { llama_model_free(g_state.model);    g_state.model   = nullptr; }
    g_state.vocab = nullptr;
    LOGI("Model unloaded");
}