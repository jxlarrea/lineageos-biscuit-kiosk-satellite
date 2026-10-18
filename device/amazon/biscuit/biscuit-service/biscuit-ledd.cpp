#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <string>
#include <time.h>
#include <vector>

#define LED_FRAME "/sys/bus/i2c/devices/0-003f/frame"
#define LED_BOOT "/sys/bus/i2c/devices/0-003f/boot_animation"
#define ANIM_DIR "/system/etc/biscuit-ledd"
#define SOCKET_PATH "/dev/socket/biscuit-ledd"

struct Frame { int ms; std::string hex; };
struct Animation { bool loop; std::vector<Frame> frames; };

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t g_thread;
static bool g_running;
static unsigned g_generation;
static unsigned g_volume_generation;
static std::string g_manual;
static std::string g_active;
// The last frame a client sent with FRAME, put back after the volume
// overlay. Empty once anything else owns the ring.
static std::string g_client_frame;
static bool g_countdown_running;
static unsigned g_countdown_generation;
static long long g_countdown_remaining;
static long long g_countdown_total;

static bool write_file(const char* path, const std::string& s) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) return false;
    bool ok = write(fd, s.c_str(), s.size()) == (ssize_t)s.size();
    close(fd);
    return ok;
}

static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    c = tolower(c);
    if (c >= 'a' && c <= 'f') return 10 + c - 'a';
    return -1;
}

static bool valid_frame(const std::string& s) {
    if (s.size() != 72) return false;
    for (size_t i = 0; i < s.size(); ++i) if (hexval(s[i]) < 0) return false;
    return true;
}

static std::string trim(std::string s) {
    size_t a = 0, b = s.size();
    while (a < b && isspace(s[a])) ++a;
    while (b > a && isspace(s[b - 1])) --b;
    return s.substr(a, b - a);
}

static bool parse_rgb(const std::string& in, std::string* out) {
    std::string s = trim(in);
    for (size_t i = 0; i < s.size(); ++i) s[i] = toupper(s[i]);
    if (s.size() == 3) {
        out->clear();
        for (size_t i = 0; i < 3; ++i) {
            if (hexval(s[i]) < 0) return false;
            out->push_back(s[i]); out->push_back(s[i]);
        }
        return true;
    }
    if (s.size() == 6) {
        for (size_t i = 0; i < 6; ++i) if (hexval(s[i]) < 0) return false;
        *out = s;
        return true;
    }
    return false;
}

struct Rgb { int red; int green; int blue; };

// Index 11 -> 0 matches the physical fill order of volume.animation.
static const int k_countdown_order[12] = { 11, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };

static int scale_component(int component, int percent) {
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    return (component * percent + 50) / 100;
}

static void append_rgb(std::string* frame, int red, int green, int blue) {
    char rgb[7];
    snprintf(rgb, sizeof(rgb), "%02X%02X%02X", red, green, blue);
    frame->append(rgb);
}

static Rgb countdown_color() {
    // Saturated purple remains visibly colored on the physical LED ring.
    return Rgb{0xFF, 0x00, 0xFF};
}

static std::string render_countdown_frame(long long remaining, long long total,
                                          int body_percent, int cursor_percent) {
    if (total <= 0 || remaining <= 0 || remaining > total) return std::string(72, '0');
    int lit = (int)(((long double)remaining * 12.0L + (long double)total - 1.0L)
            / (long double)total);
    if (lit < 0) lit = 0;
    if (lit > 12) lit = 12;

    int brightness[12] = {};
    for (int i = 0; i < lit; ++i) {
        brightness[k_countdown_order[i]] = i == lit - 1 ? cursor_percent : body_percent;
    }

    Rgb color = countdown_color();
    std::string frame;
    frame.reserve(72);
    for (int led = 0; led < 12; ++led) {
        append_rgb(&frame,
                   scale_component(color.red, brightness[led]),
                   scale_component(color.green, brightness[led]),
                   scale_component(color.blue, brightness[led]));
    }
    return frame;
}

static unsigned long long monotonic_ms() {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (unsigned long long)now.tv_sec * 1000ULL + (unsigned long long)now.tv_nsec / 1000000ULL;
}

static void countdown_brightness(int* body_percent, int* cursor_percent) {
    const unsigned long long period_ms = 2000;
    const unsigned long long half_period_ms = period_ms / 2;
    unsigned long long phase = monotonic_ms() % period_ms;
    unsigned long long triangle = phase <= half_period_ms ? phase : period_ms - phase;
    // ponytail: the caller owns timekeeping; the daemon only renders the continuous breath.
    *body_percent = 35 + (int)(triangle * 45 / half_period_ms);
    *cursor_percent = 55 + (int)(triangle * 45 / half_period_ms);
}

static bool parse_frame_line(const std::string& line, Frame* frame) {
    size_t colon = line.find(':');
    if (colon == std::string::npos) return false;
    frame->ms = atoi(line.substr(0, colon).c_str());
    if (frame->ms < 0) return false;
    std::string rest = line.substr(colon + 1), rgb, hex;
    size_t start = 0;
    for (int n = 0; n < 12; ++n) {
        size_t comma = rest.find(',', start);
        std::string part = rest.substr(start, comma == std::string::npos ? std::string::npos : comma - start);
        if (!parse_rgb(part, &rgb)) return false;
        hex += rgb;
        if (n < 11 && comma == std::string::npos) return false;
        start = comma + 1;
    }
    frame->hex = hex;
    return valid_frame(frame->hex);
}

static void clear();

static bool load_animation(const std::string& name, Animation* anim) {
    anim->loop = false;
    anim->frames.clear();
    if (name.find('/') != std::string::npos || name.find("..") != std::string::npos) return false;
    std::string path = std::string(ANIM_DIR) + "/" + name;
    if (path.find(".animation") == std::string::npos) path += ".animation";
    FILE* f = fopen(path.c_str(), "r");
    if (!f) return false;
    char buf[512];
    while (fgets(buf, sizeof(buf), f)) {
        std::string line = trim(buf);
        if (line.empty() || line[0] == '#') continue;
        if (line == "loop") { anim->loop = true; continue; }
        Frame fr;
        if (!parse_frame_line(line, &fr)) { fclose(f); return false; }
        anim->frames.push_back(fr);
    }
    fclose(f);
    return !anim->frames.empty();
}

static void* player(void* arg) {
    std::string name = *(std::string*)arg;
    delete (std::string*)arg;
    Animation anim;
    if (!load_animation(name, &anim)) {
        pthread_mutex_lock(&g_lock);
        if (g_active == name) { g_active.clear(); g_running = false; }
        pthread_mutex_unlock(&g_lock);
        return NULL;
    }
    pthread_mutex_lock(&g_lock);
    unsigned gen = g_generation;
    pthread_mutex_unlock(&g_lock);
    do {
        for (size_t i = 0; i < anim.frames.size(); ++i) {
            pthread_mutex_lock(&g_lock);
            bool stop = gen != g_generation || g_active != name;
            pthread_mutex_unlock(&g_lock);
            if (stop) return NULL;
            write_file(LED_FRAME, anim.frames[i].hex);
            usleep(anim.frames[i].ms * 1000);
        }
    } while (anim.loop);
    pthread_mutex_lock(&g_lock);
    if (g_active == name) { g_active.clear(); g_running = false; }
    pthread_mutex_unlock(&g_lock);
    return NULL;
}

static void play_name(const std::string& name, bool manual) {
    pthread_mutex_lock(&g_lock);
    g_client_frame.clear();
    if (manual) {
        g_manual = name;
        g_countdown_running = false;
        ++g_countdown_generation;
    }
    g_active = name;
    ++g_generation;
    ++g_volume_generation;
    g_running = true;
    pthread_mutex_unlock(&g_lock);
    pthread_create(&g_thread, NULL, player, new std::string(name));
    pthread_detach(g_thread);
}

static void play(const std::string& name) {
    play_name(name, true);
}

static void* volume_clearer(void* arg) {
    unsigned gen = *(unsigned*)arg;
    delete (unsigned*)arg;
    usleep(1000 * 1000);
    pthread_mutex_lock(&g_lock);
    bool clear = gen == g_volume_generation && g_manual.empty();
    std::string restore = g_client_frame;
    pthread_mutex_unlock(&g_lock);
    // A client's frame comes back after the overlay rather than a dark ring.
    if (clear) write_file(LED_FRAME, restore.empty()
            ? "000000000000000000000000000000000000000000000000000000000000000000000000"
            : restore);
    return NULL;
}

static void show_volume(int current, int max) {
    if (max <= 0 || current < 0) return;
    Animation anim;
    if (!load_animation("volume", &anim)) return;
    int step = (current * (int)anim.frames.size() + max / 2) / max;
    if (step < 0) step = 0;
    if (step >= (int)anim.frames.size()) step = (int)anim.frames.size() - 1;
    pthread_mutex_lock(&g_lock);
    bool blocked = !g_manual.empty();
    unsigned gen = ++g_volume_generation;
    pthread_mutex_unlock(&g_lock);
    if (blocked) return;
    write_file(LED_FRAME, anim.frames[step].hex);
    pthread_t thread;
    pthread_create(&thread, NULL, volume_clearer, new unsigned(gen));
    pthread_detach(thread);
}

static void* countdown_player(void* arg) {
    unsigned generation = *(unsigned*)arg;
    delete (unsigned*)arg;
    for (;;) {
        long long remaining = 0, total = 0;
        pthread_mutex_lock(&g_lock);
        bool active = g_countdown_running && generation == g_countdown_generation;
        remaining = g_countdown_remaining;
        total = g_countdown_total;
        pthread_mutex_unlock(&g_lock);
        if (!active) return NULL;

        int body_percent = 0, cursor_percent = 0;
        countdown_brightness(&body_percent, &cursor_percent);
        write_file(LED_FRAME, render_countdown_frame(remaining, total, body_percent, cursor_percent));
        usleep(50 * 1000);
    }
}

static void clear_countdown() {
    pthread_mutex_lock(&g_lock);
    g_manual.clear();
    g_active.clear();
    g_running = false;
    g_countdown_running = false;
    g_countdown_remaining = 0;
    g_countdown_total = 0;
    ++g_generation;
    ++g_volume_generation;
    ++g_countdown_generation;
    pthread_mutex_unlock(&g_lock);
    write_file(LED_FRAME, "000000000000000000000000000000000000000000000000000000000000000000000000");
}

static void show_countdown(long long remaining, long long total) {
    if (total <= 0 || remaining < 0 || remaining > total) return;
    if (remaining == 0) {
        clear_countdown();
        return;
    }

    bool start = false;
    unsigned generation = 0;
    pthread_mutex_lock(&g_lock);
    g_client_frame.clear();
    g_manual = "countdown";
    g_active = "countdown";
    ++g_generation;
    ++g_volume_generation;
    g_running = true;
    g_countdown_remaining = remaining;
    g_countdown_total = total;
    if (!g_countdown_running) {
        g_countdown_running = true;
        generation = ++g_countdown_generation;
        start = true;
    }
    pthread_mutex_unlock(&g_lock);

    if (start) {
        pthread_t thread;
        pthread_create(&thread, NULL, countdown_player, new unsigned(generation));
        pthread_detach(thread);
    }
}

// Stops whatever the daemon is animating, without touching the ring.
static void stop_effects() {
    pthread_mutex_lock(&g_lock);
    g_manual.clear();
    g_active.clear();
    g_running = false;
    g_countdown_running = false;
    g_countdown_remaining = 0;
    g_countdown_total = 0;
    ++g_generation;
    ++g_volume_generation;
    ++g_countdown_generation;
    pthread_mutex_unlock(&g_lock);
}

static void clear() {
    pthread_mutex_lock(&g_lock);
    g_client_frame.clear();
    g_manual.clear();
    g_active.clear();
    g_running = false;
    g_countdown_running = false;
    g_countdown_remaining = 0;
    g_countdown_total = 0;
    ++g_generation;
    ++g_volume_generation;
    ++g_countdown_generation;
    pthread_mutex_unlock(&g_lock);
    write_file(LED_FRAME, "000000000000000000000000000000000000000000000000000000000000000000000000");
}

static void handle(int fd, char* line) {
    char* nl = strchr(line, '\n'); if (nl) *nl = 0;
    if (!strncmp(line, "FRAME ", 6)) {
        std::string hex = trim(line + 6);
        // A frame replaces the ring in one write. Clearing first blanked it
        // for about 14 ms on every frame, which made a client's animation
        // (20 frames a second) strobe.
        if (valid_frame(hex)) {
            stop_effects();
            pthread_mutex_lock(&g_lock);
            g_client_frame = hex;
            pthread_mutex_unlock(&g_lock);
            write_file(LED_FRAME, hex);
            dprintf(fd, "OK\n");
        }
        else dprintf(fd, "ERR bad frame\n");
    } else if (!strncmp(line, "PLAY ", 5)) {
        std::string name = trim(line + 5);
        Animation anim;
        if (load_animation(name, &anim)) { play(name); dprintf(fd, "OK\n"); }
        else dprintf(fd, "ERR bad animation\n");
    } else if (!strncmp(line, "COUNTDOWN ", 10)) {
        long long remaining = -1, total = -1;
        if (sscanf(line + 10, "%lld %lld", &remaining, &total) == 2
                && total > 0 && remaining >= 0 && remaining <= total) {
            show_countdown(remaining, total);
            dprintf(fd, "OK\n");
        } else {
            dprintf(fd, "ERR bad countdown\n");
        }
    } else if (!strncmp(line, "VOLUME ", 7)) {
        int cur = -1, max = -1;
        if (sscanf(line + 7, "%d %d", &cur, &max) == 2) { show_volume(cur, max); dprintf(fd, "OK\n"); }
        else dprintf(fd, "ERR bad volume\n");
    } else if (!strncmp(line, "CLEAR", 5) || !strcmp(line, "OFF")) {
        clear(); dprintf(fd, "OK\n");
    } else if (!strcmp(line, "STATUS")) {
        pthread_mutex_lock(&g_lock);
        dprintf(fd, "manual=%s active=%s running=%d\n", g_manual.c_str(), g_active.c_str(), g_running ? 1 : 0);
        pthread_mutex_unlock(&g_lock);
    } else {
        dprintf(fd, "ERR unknown\n");
    }
}

static int make_socket() {
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s < 0) return -1;
    unlink(SOCKET_PATH);
    sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);
    if (bind(s, (sockaddr*)&addr, sizeof(addr)) < 0) { close(s); return -1; }
    chown(SOCKET_PATH, 1000, 1000); // AID_SYSTEM; init socket normally does this.
    chmod(SOCKET_PATH, 0660);
    if (listen(s, 4) < 0) { close(s); return -1; }
    return s;
}

int main() {
    signal(SIGPIPE, SIG_IGN);
    write_file(LED_BOOT, "0");
    Animation boot;
    if (load_animation("boot-complete-green", &boot)) {
        for (size_t i = 0; i < boot.frames.size(); ++i) {
            write_file(LED_FRAME, boot.frames[i].hex);
            usleep(boot.frames[i].ms * 1000);
        }
    }
    int s = -1;
    const char* env = getenv("ANDROID_SOCKET_biscuit-ledd");
    if (env) {
        s = atoi(env);
        if (listen(s, 4) < 0) s = -1;
    }
    if (s < 0) s = make_socket();
    if (s < 0) return 1;
    for (;;) {
        int c = accept(s, NULL, NULL);
        if (c < 0) continue;
        FILE* f = fdopen(c, "r+");
        char line[256];
        while (f && fgets(line, sizeof(line), f)) handle(c, line);
        if (f) fclose(f); else close(c);
    }
}
