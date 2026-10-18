// Puente para usar libarchive desde Swift.
// libarchive viene dentro de iOS (es de Apple, no un programa de terceros), pero Apple no publica
// sus "instrucciones" (headers), así que acá se declaran solo las funciones que usamos.
// Ojo: Apple no permite esto en apps del App Store; esta app es de uso personal.

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

struct archive;
struct archive_entry;

struct archive *archive_read_new(void);
int archive_read_support_format_all(struct archive *);
int archive_read_support_filter_all(struct archive *);
int archive_read_open_filename(struct archive *, const char *filename, size_t block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *buffer, size_t length);
int archive_read_data_skip(struct archive *);
const char *archive_error_string(struct archive *);
int archive_read_free(struct archive *);

const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
