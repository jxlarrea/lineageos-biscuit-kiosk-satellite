// Amazon's wake word engine (Pryon) as a service for Kiosk Satellite.
//
// The libraries and models come from the Fire OS 6.5.7.4 OTA (see
// scripts/extract-fireos6-blobs.sh). Nothing is loaded until a client asks
// to listen, so the daemon costs next to nothing while another engine runs.
//
// Protocol, on the init socket biscuit-pryon:
//
// The daemon speaks first, with one JSON line listing every model under
// /system/etc/pryon, the keywords each one spots and the threshold each
// keyword is accepted at before any client property lowers it. A keyword
// named STOP is a stop word, every other one a wake word:
//
//   {"event":"hello","version":1,"models":[{"model":"ALEXA",
//     "wake_words":["ALEXA"],"stop_words":["STOP"],
//     "accept_thresholds":{"ALEXA":0.923,"STOP":0.55}}]}
//
// The client sends frames: a type byte, a little-endian 32-bit length and
// the payload.
//
//   'S' start listening with the comma separated models in the payload, or
//       with every model when it is empty. Answered with a "started" or an
//       "error" event.
//   'A' 16 kHz mono 16-bit little-endian audio.
//   'P' a client property, "name=value". Pryon lowers its thresholds while
//       AudioPlayerState, audio_playback or AlarmState is 1. Kept until it
//       is pushed again, and pushed again after every 'E'.
//   'E' a gap in the audio.
//
// Every keyword Pryon spots comes back as a JSON line. accepted is false for
// a near miss, and its threshold is then the lower one Pryon reports near
// misses from. begin and end count samples since the client's first audio.
//
//   {"event":"detection","model":"ALEXA","keyword":"ALEXA","stop":false,
//    "accepted":true,"score":0.976,"threshold":0.923,"begin":133920,
//    "end":142080}
//
// One client at a time: the next one waits until the first disconnects.
// PRYOND_LIB_DIR, PRYOND_MODEL_DIR and PRYOND_SOCKET override the paths for
// testing from /data/local/tmp. PRYOND_DEBUG=1 prints every result and
// Pryon's detection log lines to stderr.

#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <map>
#include <string>
#include <vector>

#define LIB_DIR "/system/lib/pryon"
#define MODEL_DIR "/system/etc/pryon"
#define SOCKET_NAME "biscuit-pryon"
#define MAX_FRAME (1 << 20)

// The layouts below were read from libpryon.so 6.5.7.4 and checked on a Dot:
// the decoder's audio format, a client property event and the fields of a
// result this daemon reads.
struct PryonFormat {
    int32_t encoding, sampleRate, bitsPerSample, numChannels;
    int32_t channelTypes[32];
};
struct PryonProperty { const char* name; uint32_t pad; int64_t value; };
struct PryonEvent { uint32_t one; const PryonProperty* property; };

static int (*p_set_log)(void (*)(int, const char*, const char*));
static int (*p_set_result)(void (*)(const char*, void*));
static int (*p_model_new)(const char*, const char*, const char*);
static int (*p_model_delete)(const char*);
static void (*p_format_default)(PryonFormat*);
static int (*p_decoder_new)(const char*, const char*, const char*, PryonFormat, const char*);
static int (*p_decoder_delete)(const char*);
static int (*p_push)(const char*, uint64_t, const int16_t*, uint32_t);
static int (*p_push_events)(const char*, const PryonEvent*, uint32_t);
static int (*p_session_end)(const char*);

struct Model {
    std::string name;
    std::vector<std::string> wake, stop;
    std::map<std::string, double> accept;
};
struct Score { double score, threshold; };

static std::string g_lib_dir = LIB_DIR;
static std::string g_model_dir = MODEL_DIR;
static bool g_debug;
static bool g_loaded;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_client = -1;
// Pryon logs the score of a detection just before it reports the detection
// itself, both on the decoder's thread. Keyed by decoder id.
static std::map<std::string, Score> g_scores;

static void send_line(const std::string& line) {
    pthread_mutex_lock(&g_lock);
    if (g_client >= 0) send(g_client, (line + "\n").c_str(), line.size() + 1, MSG_NOSIGNAL);
    pthread_mutex_unlock(&g_lock);
}

static std::string quote(const std::string& s) {
    std::string out = "\"";
    for (size_t i = 0; i < s.size(); ++i) {
        char c = s[i];
        if (c == '"' || c == '\\') { out += '\\'; out += c; }
        else if ((unsigned char)c < 0x20) out += ' ';
        else out += c;
    }
    return out + "\"";
}

static std::string list(const std::vector<std::string>& v) {
    std::string out = "[";
    for (size_t i = 0; i < v.size(); ++i) out += (i ? "," : "") + quote(v[i]);
    return out + "]";
}

static std::string read_file(const std::string& path) {
    std::string out;
    FILE* f = fopen(path.c_str(), "r");
    if (!f) return out;
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) out.append(buf, n);
    fclose(f);
    return out;
}

// kw.cfg.json names each keyword's spotter and gives its accept threshold
// right after. A scan for the two keys does: the file is Amazon's, fixed by
// the manifest's checksum.
static double accept_threshold(const std::string& cfg, const std::string& keyword) {
    size_t at = 0;
    while ((at = cfg.find("\"name\"", at)) != std::string::npos) {
        at += 6;
        size_t open = cfg.find('"', cfg.find(':', at));
        if (open == std::string::npos) break;
        size_t close = cfg.find('"', open + 1);
        if (close == std::string::npos) break;
        if (cfg.compare(open + 1, close - open - 1, keyword)) continue;
        size_t key = cfg.find("\"accept-threshold\"", close);
        if (key == std::string::npos) break;
        size_t colon = cfg.find(':', key);
        if (colon == std::string::npos) break;
        return atof(cfg.c_str() + colon + 1);
    }
    return -1;
}

static std::vector<Model> find_models() {
    std::vector<Model> models;
    DIR* d = opendir(g_model_dir.c_str());
    if (!d) return models;
    while (dirent* e = readdir(d)) {
        if (e->d_name[0] == '.') continue;
        std::string dir = g_model_dir + "/" + e->d_name;
        if (access((dir + "/pryon.manifest").c_str(), R_OK)) continue;
        // words.shrunk.txt: "<eps> 0", then one keyword and its id per line.
        FILE* f = fopen((dir + "/words.shrunk.txt").c_str(), "r");
        if (!f) continue;
        Model m;
        m.name = e->d_name;
        char word[128];
        int id;
        while (fscanf(f, "%127s %d", word, &id) == 2) {
            if (word[0] == '<') continue;
            (strcmp(word, "STOP") ? m.wake : m.stop).push_back(word);
        }
        fclose(f);
        std::string cfg = read_file(dir + "/kw.cfg.json");
        for (size_t i = 0; i < m.wake.size(); ++i) m.accept[m.wake[i]] = accept_threshold(cfg, m.wake[i]);
        for (size_t i = 0; i < m.stop.size(); ++i) m.accept[m.stop[i]] = accept_threshold(cfg, m.stop[i]);
        if (!m.wake.empty() || !m.stop.empty()) models.push_back(m);
    }
    closedir(d);
    return models;
}

static void on_log(int level, const char*, const char* msg) {
    if (!msg) return;
    const char* id = strstr(msg, "DecoderID=");
    const char* sc = strstr(msg, "classifier_score=");
    const char* th = strstr(msg, "active_threshold=");
    if (g_debug && (strstr(msg, "detection_type") || strstr(msg, "ActiveKeywords") ||
                    strstr(msg, "keyword") || level <= 3))
        fprintf(stderr, "pryon[%d]: %s\n", level, msg);
    if (id && sc && th) {
        id += 10;
        const char* end = strchr(id, ':');
        if (!end) return;
        Score s = { atof(sc + 17), atof(th + 17) };
        pthread_mutex_lock(&g_lock);
        g_scores[std::string(id, end - id)] = s;
        pthread_mutex_unlock(&g_lock);
    } else if (level <= 2) {
        fprintf(stderr, "pryon: %s\n", msg);
    }
}

static void on_result(const char* decoder, void* result) {
    const uint8_t* r = (const uint8_t*)result;
    uint64_t begin, end;
    const char* keyword;
    int32_t type;
    memcpy(&begin, r + 0x08, 8);
    memcpy(&keyword, r + 0x1c, sizeof(keyword));
    memcpy(&type, r + 0x24, 4);
    memcpy(&end, r + 0x40, 8);
    if (g_debug)
        fprintf(stderr, "result %s keyword=%s type=%d begin=%llu end=%llu\n", decoder,
                keyword ? keyword : "(null)", type, (unsigned long long)begin, (unsigned long long)end);
    if (!keyword) return;
    // 2 is an accept, 0 a near miss. Fire OS also acts on 3.
    bool accepted = type == 2 || type == 3;
    Score s = { -1, -1 };
    pthread_mutex_lock(&g_lock);
    std::map<std::string, Score>::iterator it = g_scores.find(decoder);
    if (it != g_scores.end()) { s = it->second; g_scores.erase(it); }
    pthread_mutex_unlock(&g_lock);
    // Decoder ids are "ks-<model>".
    std::string model = strncmp(decoder, "ks-", 3) ? decoder : decoder + 3;
    char nums[160];
    snprintf(nums, sizeof(nums), "\"score\":%.4f,\"threshold\":%.4f,\"begin\":%llu,\"end\":%llu}",
             s.score, s.threshold, (unsigned long long)begin, (unsigned long long)end);
    send_line("{\"event\":\"detection\",\"model\":" + quote(model) + ",\"keyword\":" + quote(keyword) +
              ",\"stop\":" + (strcmp(keyword, "STOP") ? "false" : "true") +
              ",\"accepted\":" + (accepted ? "true" : "false") + "," + nums);
}

#define SYM(var, name) \
    if (!(*(void**)&var = dlsym(lib, name))) { fprintf(stderr, "missing %s\n", name); return false; }

// An app cannot point the linker at a library folder, and neither can this
// daemon without LD_LIBRARY_PATH, so each library is loaded by its full path
// after the ones it needs.
static bool load_pryon() {
    static const char* libs[] = {
        "libc++_shared.so", "libfst.so", "libfstfar.so", "libfstscript.so", "libfstngram.so",
        "libpugixml.so", "libpryonConfig.so", "libwatermars.so", "libAFEMetadataDecoder.so",
        "libNeMoRt.so", "libnemort-cnpy.so", "libacsl.so", "libblu_native_toolkit.so",
        "libgrxml_parser.so", "libpryon.so",
    };
    if (g_loaded) return true;
    void* lib = NULL;
    for (size_t i = 0; i < sizeof(libs) / sizeof(*libs); ++i) {
        std::string path = g_lib_dir + "/" + libs[i];
        if (!(lib = dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL))) {
            fprintf(stderr, "dlopen %s: %s\n", path.c_str(), dlerror());
            return false;
        }
    }
    SYM(p_set_log, "PryonApi_SetLoggingCallback");
    SYM(p_set_result, "PryonApi_SetEnumeratedResultCallback");
    SYM(p_model_new, "PryonModelSet_New");
    SYM(p_model_delete, "PryonModelSet_Delete");
    SYM(p_format_default, "PryonDecoder_NewPryonMultichannelAudioFormat_Default");
    SYM(p_decoder_new, "PryonDecoder_NewSpotterAudioDecoder");
    SYM(p_decoder_delete, "PryonDecoder_Delete");
    SYM(p_push, "PryonDecoder_PushAudioEventSamples");
    SYM(p_push_events, "PryonDecoder_PushClientEvents");
    SYM(p_session_end, "PryonDecoder_SessionEnd");
    p_set_log(on_log);
    p_set_result(on_result);
    g_loaded = true;
    return true;
}

struct Session {
    std::vector<std::string> decoders, model_sets;
    std::map<std::string, int64_t> properties;
    uint64_t index;
};

static void push_properties(const std::vector<std::string>& decoders, const std::map<std::string, int64_t>& properties) {
    std::vector<PryonProperty> props;
    for (std::map<std::string, int64_t>::const_iterator it = properties.begin(); it != properties.end(); ++it) {
        PryonProperty p = { it->first.c_str(), 0, it->second };
        props.push_back(p);
    }
    if (props.empty()) return;
    std::vector<PryonEvent> events;
    for (size_t i = 0; i < props.size(); ++i) {
        PryonEvent e = { 1, &props[i] };
        events.push_back(e);
    }
    for (size_t i = 0; i < decoders.size(); ++i)
        p_push_events(decoders[i].c_str(), &events[0], events.size());
}

static void stop(Session& s) {
    for (size_t i = 0; i < s.decoders.size(); ++i) p_decoder_delete(s.decoders[i].c_str());
    for (size_t i = 0; i < s.model_sets.size(); ++i) p_model_delete(s.model_sets[i].c_str());
    s.decoders.clear();
    s.model_sets.clear();
    pthread_mutex_lock(&g_lock);
    g_scores.clear();
    pthread_mutex_unlock(&g_lock);
}

static void error(const std::string& message) {
    send_line("{\"event\":\"error\",\"message\":" + quote(message) + "}");
}

static void start(Session& s, const std::string& wanted) {
    stop(s);
    if (!load_pryon()) { error("cannot load Pryon from " + g_lib_dir); return; }
    std::vector<Model> models = find_models();
    std::vector<std::string> started;
    for (size_t i = 0; i < models.size(); ++i) {
        const Model& m = models[i];
        if (!wanted.empty() && ("," + wanted + ",").find("," + m.name + ",") == std::string::npos) continue;
        std::string set = "ks-set-" + m.name, decoder = "ks-" + m.name;
        std::string manifest = g_model_dir + "/" + m.name + "/pryon.manifest";
        if (p_model_new(set.c_str(), manifest.c_str(), "")) { error("cannot load model " + m.name); continue; }
        s.model_sets.push_back(set);
        // Without this Pryon spots only the model's default keyword, which
        // leaves out STOP.
        std::vector<std::string> all = m.wake;
        all.insert(all.end(), m.stop.begin(), m.stop.end());
        std::string config = "{\"keyword\":{\"enabled-keyword-list\":" + list(all) + "}}";
        PryonFormat format;
        p_format_default(&format);
        if (p_decoder_new(decoder.c_str(), set.c_str(), "pryon", format, config.c_str())) {
            error("cannot start a decoder for " + m.name);
            continue;
        }
        s.decoders.push_back(decoder);
        started.push_back(m.name);
    }
    s.index = 0;
    push_properties(s.decoders, s.properties);
    if (started.empty()) error("no model to listen with");
    else send_line("{\"event\":\"started\",\"models\":" + list(started) + "}");
}

static bool read_all(int fd, void* buf, size_t len) {
    uint8_t* p = (uint8_t*)buf;
    while (len) {
        ssize_t n = read(fd, p, len);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        p += n;
        len -= n;
    }
    return true;
}

static void serve(int fd) {
    pthread_mutex_lock(&g_lock);
    g_client = fd;
    pthread_mutex_unlock(&g_lock);

    std::vector<Model> models = find_models();
    std::string hello = "{\"event\":\"hello\",\"version\":1,\"models\":[";
    for (size_t i = 0; i < models.size(); ++i) {
        std::string accept;
        for (std::map<std::string, double>::iterator it = models[i].accept.begin(); it != models[i].accept.end(); ++it) {
            if (it->second < 0) continue;
            char num[32];
            snprintf(num, sizeof(num), "%.4g", it->second);
            accept += (accept.empty() ? "" : ",") + quote(it->first) + ":" + num;
        }
        hello += (i ? "," : "") + std::string("{\"model\":") + quote(models[i].name) +
                 ",\"wake_words\":" + list(models[i].wake) + ",\"stop_words\":" + list(models[i].stop) +
                 ",\"accept_thresholds\":{" + accept + "}}";
    }
    send_line(hello + "]}");

    Session s;
    s.index = 0;
    std::vector<uint8_t> payload;
    for (;;) {
        uint8_t header[5];
        if (!read_all(fd, header, sizeof(header))) break;
        uint32_t len = header[1] | header[2] << 8 | header[3] << 16 | (uint32_t)header[4] << 24;
        if (len > MAX_FRAME) break;
        payload.resize(len);
        if (len && !read_all(fd, &payload[0], len)) break;
        std::string text(payload.begin(), payload.end());
        switch (header[0]) {
        case 'S':
            start(s, text);
            break;
        case 'A': {
            uint32_t samples = len / 2;
            if (!samples) break;
            for (size_t i = 0; i < s.decoders.size(); ++i)
                p_push(s.decoders[i].c_str(), s.index, (const int16_t*)&payload[0], samples);
            s.index += samples;
            break;
        }
        case 'P': {
            size_t eq = text.find('=');
            if (eq == std::string::npos || !eq) { error("bad property"); break; }
            std::map<std::string, int64_t> one;
            one[text.substr(0, eq)] = atoll(text.c_str() + eq + 1);
            s.properties[text.substr(0, eq)] = one.begin()->second;
            push_properties(s.decoders, one);
            break;
        }
        case 'E':
            for (size_t i = 0; i < s.decoders.size(); ++i) p_session_end(s.decoders[i].c_str());
            push_properties(s.decoders, s.properties);
            break;
        default:
            error("unknown frame");
        }
    }
    if (g_loaded) stop(s);
    pthread_mutex_lock(&g_lock);
    g_client = -1;
    pthread_mutex_unlock(&g_lock);
    close(fd);
}

static int make_socket(const char* path) {
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s < 0) return -1;
    unlink(path);
    sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    if (bind(s, (sockaddr*)&addr, sizeof(addr)) < 0) { close(s); return -1; }
    chmod(path, 0666);
    return s;
}

int main() {
    signal(SIGPIPE, SIG_IGN);
    if (getenv("PRYOND_LIB_DIR")) g_lib_dir = getenv("PRYOND_LIB_DIR");
    if (getenv("PRYOND_MODEL_DIR")) g_model_dir = getenv("PRYOND_MODEL_DIR");
    g_debug = getenv("PRYOND_DEBUG") && !strcmp(getenv("PRYOND_DEBUG"), "1");
    setvbuf(stderr, NULL, _IOLBF, 0);
    int s = -1;
    const char* env = getenv("ANDROID_SOCKET_" SOCKET_NAME);
    if (getenv("PRYOND_SOCKET")) s = make_socket(getenv("PRYOND_SOCKET"));
    else if (env) s = atoi(env);
    else s = make_socket("/dev/socket/" SOCKET_NAME);
    if (s < 0 || listen(s, 4) < 0) return 1;
    for (;;) {
        int c = accept(s, NULL, NULL);
        if (c >= 0) serve(c);
    }
}
