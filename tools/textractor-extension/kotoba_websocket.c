/*
 * Kotoba WebSocket: a Textractor extension that sends every line of the
 * selected text thread over WebSocket (port 6677), and keeps the lines.
 *
 * Works like kuroahna's textractor_websocket (plain text frames, so
 * texthooker-ui and kizuna-texthooker-ui work unchanged), plus:
 * - the server starts when Textractor loads the extension, not at the first line;
 * - it remembers the last 2000 lines. A client that connects with
 *   /?kotoba=1&session=S&since=N gets, as JSON, every line after N that it
 *   missed (the phone was asleep), then the new ones:
 *   {"sentence":"…","id":N,"session":"S"}
 *   If S is not this run's session (Textractor restarted), it gets them all.
 *
 * Build (Windows DLLs, from Linux or Windows with MinGW):
 *   i686-w64-mingw32-gcc   -O2 -shared -o kotoba_websocket_x86.dll kotoba_websocket.c -lws2_32 -static-libgcc
 *   x86_64-w64-mingw32-gcc -O2 -shared -o kotoba_websocket_x64.dll kotoba_websocket.c -lws2_32 -static-libgcc
 * Test build (Linux): gcc -DKOTOBA_TEST -O1 -o test_server kotoba_websocket.c -lpthread
 */

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
typedef SOCKET sock_t;
#define CLOSESOCK closesocket
static int would_block(void) { return WSAGetLastError() == WSAEWOULDBLOCK; }
static void set_nonblocking(sock_t s) { u_long on = 1; ioctlsocket(s, FIONBIO, &on); }
static CRITICAL_SECTION lock;
#define LOCK() EnterCriticalSection(&lock)
#define UNLOCK() LeaveCriticalSection(&lock)
static uint64_t now_ms(void) { return GetTickCount64(); }
static void sleep_ms(int ms) { Sleep(ms); }
#else
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
typedef int sock_t;
#define INVALID_SOCKET (-1)
#define CLOSESOCK close
static int would_block(void) { return errno == EAGAIN || errno == EWOULDBLOCK; }
static void set_nonblocking(sock_t s) { fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK); }
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
#define LOCK() pthread_mutex_lock(&lock)
#define UNLOCK() pthread_mutex_unlock(&lock)
static uint64_t now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static void sleep_ms(int ms) { usleep(ms * 1000); }
#endif

#define PORT 6677
#define HISTORY 2000
#define MAX_CLIENTS 32
#define IN_SIZE 16384

/* ---------- history ---------- */

static char *history[HISTORY]; /* UTF-8, line with id n lives at n % HISTORY */
static uint64_t last_id = 0;    /* ids start at 1 */
static char session[32];

static void push_line(const char *utf8) {
    size_t n = strlen(utf8);
    char *copy = (char *)malloc(n + 1);
    if (!copy) return;
    memcpy(copy, utf8, n + 1);
    LOCK();
    last_id++;
    free(history[last_id % HISTORY]);
    history[last_id % HISTORY] = copy;
    UNLOCK();
}

static uint64_t first_id(void) { return last_id > HISTORY ? last_id - HISTORY + 1 : 1; }

/* ---------- SHA-1 and base64, for the handshake ---------- */

static uint32_t rol(uint32_t v, int b) { return (v << b) | (v >> (32 - b)); }

static void sha1(const unsigned char *data, size_t len, unsigned char out[20]) {
    uint32_t h[5] = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0};
    size_t total = ((len + 8) / 64 + 1) * 64;
    unsigned char *msg = (unsigned char *)calloc(total, 1);
    if (!msg) { memset(out, 0, 20); return; }
    memcpy(msg, data, len);
    msg[len] = 0x80;
    uint64_t bits = (uint64_t)len * 8;
    for (int i = 0; i < 8; i++) msg[total - 1 - i] = (unsigned char)(bits >> (8 * i));
    for (size_t off = 0; off < total; off += 64) {
        uint32_t w[80];
        for (int i = 0; i < 16; i++)
            w[i] = (uint32_t)msg[off + 4 * i] << 24 | (uint32_t)msg[off + 4 * i + 1] << 16 |
                   (uint32_t)msg[off + 4 * i + 2] << 8 | msg[off + 4 * i + 3];
        for (int i = 16; i < 80; i++) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
        for (int i = 0; i < 80; i++) {
            uint32_t f, k;
            if (i < 20) { f = (b & c) | (~b & d); k = 0x5A827999; }
            else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
            else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
            else { f = b ^ c ^ d; k = 0xCA62C1D6; }
            uint32_t t = rol(a, 5) + f + e + k + w[i];
            e = d; d = c; c = rol(b, 30); b = a; a = t;
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e;
    }
    free(msg);
    for (int i = 0; i < 5; i++)
        for (int j = 0; j < 4; j++) out[4 * i + j] = (unsigned char)(h[i] >> (24 - 8 * j));
}

static void base64(const unsigned char *in, size_t len, char *out) {
    static const char t[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t o = 0;
    for (size_t i = 0; i < len; i += 3) {
        uint32_t v = (uint32_t)in[i] << 16 | (i + 1 < len ? (uint32_t)in[i + 1] << 8 : 0) | (i + 2 < len ? in[i + 2] : 0);
        out[o++] = t[(v >> 18) & 63];
        out[o++] = t[(v >> 12) & 63];
        out[o++] = i + 1 < len ? t[(v >> 6) & 63] : '=';
        out[o++] = i + 2 < len ? t[v & 63] : '=';
    }
    out[o] = 0;
}

/* ---------- clients ---------- */

typedef struct {
    sock_t sock;
    int open;     /* handshake done */
    int closing;  /* close after the output is flushed */
    int json;     /* a Kotoba client: JSON with ids */
    uint64_t cursor; /* last id sent */
    unsigned char in[IN_SIZE];
    size_t inlen;
    char *out;
    size_t outlen, outcap;
    uint64_t heard, pinged;
} client_t;

static client_t clients[MAX_CLIENTS];

static int out_append(client_t *c, const void *data, size_t len) {
    if (c->outlen + len > c->outcap) {
        size_t cap = c->outcap ? c->outcap : 4096;
        while (cap < c->outlen + len) cap *= 2;
        /* A client that reads nothing for megabytes is gone. */
        if (cap > (8u << 20)) return 0;
        char *grown = (char *)realloc(c->out, cap);
        if (!grown) return 0;
        c->out = grown;
        c->outcap = cap;
    }
    memcpy(c->out + c->outlen, data, len);
    c->outlen += len;
    return 1;
}

static int send_frame(client_t *c, int opcode, const void *data, size_t len) {
    unsigned char head[10];
    size_t h = 0;
    head[h++] = (unsigned char)(0x80 | opcode);
    if (len < 126) head[h++] = (unsigned char)len;
    else if (len < 65536) { head[h++] = 126; head[h++] = (unsigned char)(len >> 8); head[h++] = (unsigned char)len; }
    else { head[h++] = 127; for (int i = 7; i >= 0; i--) head[h++] = (unsigned char)((uint64_t)len >> (8 * i)); }
    return out_append(c, head, h) && out_append(c, data, len);
}

static void drop(client_t *c) {
    CLOSESOCK(c->sock);
    free(c->out);
    memset(c, 0, sizeof *c);
    c->sock = INVALID_SOCKET;
}

/* Value of a query parameter in the request path ("" when absent). */
static void query(const char *path, const char *name, char *out, size_t size) {
    out[0] = 0;
    size_t n = strlen(name);
    for (const char *p = path; (p = strstr(p, name)) != NULL; p += n) {
        if ((p == path || p[-1] == '?' || p[-1] == '&') && p[n] == '=') {
            p += n + 1;
            size_t i = 0;
            while (p[i] && p[i] != '&' && p[i] != ' ' && i + 1 < size) { out[i] = p[i]; i++; }
            out[i] = 0;
            return;
        }
    }
}

static int strncasecmp_portable(const char *a, const char *b, size_t n) {
    for (size_t i = 0; i < n; i++) {
        int x = tolower((unsigned char)a[i]), y = tolower((unsigned char)b[i]);
        if (x != y || !x) return x - y;
    }
    return 0;
}

static int handshake(client_t *c) {
    c->in[c->inlen] = 0;
    char *end = strstr((char *)c->in, "\r\n\r\n");
    if (!end) return c->inlen + 1 < IN_SIZE; /* wait for more, unless full */
    char path[512] = "";
    sscanf((char *)c->in, "GET %511s", path);
    char key[128] = "";
    for (char *line = (char *)c->in; line && line < end; line = strstr(line, "\r\n"), line = line ? line + 2 : NULL) {
        if (!strncasecmp_portable(line, "sec-websocket-key:", 18)) {
            const char *v = line + 18;
            while (*v == ' ') v++;
            size_t i = 0;
            while (v[i] && v[i] != '\r' && i + 1 < sizeof key) { key[i] = v[i]; i++; }
            key[i] = 0;
        }
    }
    if (!key[0]) {
        const char *bad = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        out_append(c, bad, strlen(bad));
        c->closing = 1;
        return 1;
    }
    char joined[256];
    snprintf(joined, sizeof joined, "%s258EAFA5-E914-47DA-95CA-C5AB0DC85B11", key);
    unsigned char digest[20];
    sha1((unsigned char *)joined, strlen(joined), digest);
    char accept[40];
    base64(digest, 20, accept);
    char reply[256];
    snprintf(reply, sizeof reply,
             "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n",
             accept);
    out_append(c, reply, strlen(reply));

    char flag[16], since[32], their_session[64];
    query(path, "kotoba", flag, sizeof flag);
    query(path, "since", since, sizeof since);
    query(path, "session", their_session, sizeof their_session);
    c->json = flag[0] != 0;
    LOCK();
    if (!c->json) {
        c->cursor = last_id; /* texthooker-ui: only new lines, as before */
    } else if (strcmp(their_session, session) == 0) {
        uint64_t n = strtoull(since, NULL, 10);
        c->cursor = n < last_id ? n : last_id;
    } else {
        c->cursor = 0; /* a new Textractor run: everything it has */
    }
    UNLOCK();
    c->open = 1;
    size_t used = (size_t)(end + 4 - (char *)c->in);
    memmove(c->in, c->in + used, c->inlen - used);
    c->inlen -= used;
    return 1;
}

/* Reads the client's frames: answers pings and close, ignores the rest. */
static int frames(client_t *c) {
    for (;;) {
        if (c->inlen < 2) return 1;
        int opcode = c->in[0] & 15;
        int masked = c->in[1] & 0x80;
        uint64_t len = c->in[1] & 127;
        size_t h = 2;
        if (len == 126) { if (c->inlen < 4) return 1; len = (uint64_t)c->in[2] << 8 | c->in[3]; h = 4; }
        else if (len == 127) { if (c->inlen < 10) return 1; len = 0; for (int i = 0; i < 8; i++) len = len << 8 | c->in[2 + i]; h = 10; }
        if (len > IN_SIZE - 14) return 0;
        unsigned char *mask = c->in + h;
        if (masked) h += 4;
        if (c->inlen < h + len) return 1;
        unsigned char *payload = c->in + h;
        if (masked) for (uint64_t i = 0; i < len; i++) payload[i] ^= mask[i % 4];
        if (opcode == 8) { send_frame(c, 8, payload, len < 2 ? len : 2); c->closing = 1; }
        else if (opcode == 9) send_frame(c, 10, payload, (size_t)len);
        memmove(c->in, c->in + h + len, c->inlen - h - len);
        c->inlen -= h + len;
    }
}

static void json_line(client_t *c, uint64_t id, const char *text) {
    size_t n = strlen(text);
    char *buf = (char *)malloc(n * 6 + 96);
    if (!buf) return;
    size_t o = 0;
    o += sprintf(buf + o, "{\"sentence\":\"");
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        if (*p == '"' || *p == '\\') { buf[o++] = '\\'; buf[o++] = (char)*p; }
        else if (*p == '\n') { buf[o++] = '\\'; buf[o++] = 'n'; }
        else if (*p == '\r') { buf[o++] = '\\'; buf[o++] = 'r'; }
        else if (*p == '\t') { buf[o++] = '\\'; buf[o++] = 't'; }
        else if (*p < 0x20) o += sprintf(buf + o, "\\u%04x", *p);
        else buf[o++] = (char)*p;
    }
    char digits[24];
    int d = 0;
    do { digits[d++] = (char)('0' + id % 10); id /= 10; } while (id);
    o += sprintf(buf + o, "\",\"id\":");
    while (d) buf[o++] = digits[--d];
    o += sprintf(buf + o, ",\"session\":\"%s\"}", session);
    send_frame(c, 1, buf, o);
    free(buf);
}

/* Queues every line the client hasn't had yet. */
static void catch_up(client_t *c) {
    LOCK();
    if (c->cursor + 1 < first_id()) c->cursor = first_id() - 1;
    while (c->cursor < last_id && c->outlen < (1u << 20)) {
        c->cursor++;
        const char *line = history[c->cursor % HISTORY];
        if (!line) continue;
        if (c->json) json_line(c, c->cursor, line);
        else send_frame(c, 1, line, strlen(line));
    }
    UNLOCK();
}

static volatile int stopping = 0;

static void serve(void) {
    for (int i = 0; i < MAX_CLIENTS; i++) clients[i].sock = INVALID_SOCKET;
    sock_t listener = INVALID_SOCKET;
    while (!stopping) {
        if (listener == INVALID_SOCKET) {
            listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
            struct sockaddr_in addr;
            memset(&addr, 0, sizeof addr);
            addr.sin_family = AF_INET;
            addr.sin_addr.s_addr = htonl(INADDR_ANY);
            addr.sin_port = htons(PORT);
#ifndef _WIN32
            int on = 1;
            setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
#endif
            if (listener == INVALID_SOCKET || bind(listener, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(listener, 8) != 0) {
                /* Port taken (another Textractor with this extension?): try again later. */
                if (listener != INVALID_SOCKET) CLOSESOCK(listener);
                listener = INVALID_SOCKET;
                sleep_ms(3000);
                continue;
            }
            set_nonblocking(listener);
        }

        fd_set readable, writable;
        FD_ZERO(&readable);
        FD_ZERO(&writable);
        FD_SET(listener, &readable);
        sock_t top = listener;
        for (int i = 0; i < MAX_CLIENTS; i++) {
            client_t *c = &clients[i];
            if (c->sock == INVALID_SOCKET) continue;
            FD_SET(c->sock, &readable);
            if (c->outlen) FD_SET(c->sock, &writable);
            if (c->sock > top) top = c->sock;
        }
        struct timeval wait = {0, 40000};
        if (select((int)top + 1, &readable, &writable, NULL, &wait) < 0) { sleep_ms(40); continue; }

        if (FD_ISSET(listener, &readable)) {
            sock_t s;
            while ((s = accept(listener, NULL, NULL)) != INVALID_SOCKET) {
                int slot = -1;
                for (int i = 0; i < MAX_CLIENTS; i++) if (clients[i].sock == INVALID_SOCKET) { slot = i; break; }
                if (slot < 0) { CLOSESOCK(s); continue; }
                set_nonblocking(s);
                client_t *c = &clients[slot];
                memset(c, 0, sizeof *c);
                c->sock = s;
                c->heard = c->pinged = now_ms();
            }
        }

        uint64_t now = now_ms();
        for (int i = 0; i < MAX_CLIENTS; i++) {
            client_t *c = &clients[i];
            if (c->sock == INVALID_SOCKET) continue;
            if (FD_ISSET(c->sock, &readable)) {
                int got = recv(c->sock, (char *)c->in + c->inlen, (int)(IN_SIZE - 1 - c->inlen), 0);
                if (got <= 0) { if (got == 0 || !would_block()) { drop(c); continue; } }
                else {
                    c->inlen += (size_t)got;
                    c->heard = now;
                    if (!c->open && !handshake(c)) { drop(c); continue; }
                    if (c->open && !frames(c)) { drop(c); continue; }
                }
            }
            if (c->open && !c->closing) {
                /* A phone that went to sleep never says goodbye: ping, and give up after a minute of silence. */
                if (now - c->heard > 60000) { drop(c); continue; }
                if (now - c->pinged > 15000) { send_frame(c, 9, "k", 1); c->pinged = now; }
                catch_up(c);
            }
            if (c->outlen) {
                int sent = send(c->sock, c->out, (int)c->outlen, 0);
                if (sent < 0 && !would_block()) { drop(c); continue; }
                if (sent > 0) { memmove(c->out, c->out + sent, c->outlen - (size_t)sent); c->outlen -= (size_t)sent; }
            }
            if (c->closing && !c->outlen) drop(c);
        }
    }
}

static void make_session(uint64_t seed) {
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < 16; i++) session[i] = hex[(seed >> (60 - 4 * i)) & 15];
    session[16] = 0;
}

#ifdef _WIN32

/* Textractor's extension interface. */
typedef struct { const char *name; int64_t value; } InfoForExtension;

static int64_t info(const InfoForExtension *list, const char *name) {
    for (; list && list->name; list++) if (!strcmp(list->name, name)) return list->value;
    return 0;
}

__declspec(dllexport) wchar_t *OnNewSentence(wchar_t *sentence, const InfoForExtension *sentenceInfo) {
    /* Only the thread you picked in Textractor, not the console or the clipboard. */
    if (sentence && info(sentenceInfo, "current select") && info(sentenceInfo, "text number") > 1) {
        int size = WideCharToMultiByte(CP_UTF8, 0, sentence, -1, NULL, 0, NULL, NULL);
        if (size > 1) {
            char *utf8 = (char *)malloc((size_t)size);
            if (utf8) {
                WideCharToMultiByte(CP_UTF8, 0, sentence, -1, utf8, size, NULL, NULL);
                push_line(utf8);
                free(utf8);
            }
        }
    }
    return sentence;
}

static DWORD WINAPI server_thread(LPVOID unused) {
    (void)unused;
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 0;
    serve();
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
        InitializeCriticalSection(&lock);
        make_session(GetTickCount64() ^ ((uint64_t)GetCurrentProcessId() << 32));
        /* The server thread runs our code until Textractor exits: keep the DLL loaded even if the extension is removed. */
        HMODULE pinned;
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN, (LPCWSTR)(void *)&DllMain, &pinned);
        HANDLE t = CreateThread(NULL, 0, server_thread, NULL, 0, NULL);
        if (t) CloseHandle(t);
    }
    return TRUE;
}

#endif

#ifdef KOTOBA_TEST
/* Linux harness: lines typed on stdin become sentences. */
static void *server_thread(void *unused) { (void)unused; serve(); return NULL; }

int main(void) {
    make_session((uint64_t)time(NULL) ^ (uint64_t)getpid());
    pthread_t t;
    pthread_create(&t, NULL, server_thread, NULL);
    printf("session %s\n", session);
    fflush(stdout);
    char line[4096];
    while (fgets(line, sizeof line, stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0]) push_line(line);
    }
    sleep_ms(300);
    return 0;
}
#endif
