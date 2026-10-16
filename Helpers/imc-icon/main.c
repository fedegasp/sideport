// imc-icon: scarica le icone delle app installate su un dispositivo iOS.
//
// libimobiledevice espone le icone solo tramite il servizio SpringBoard
// (`sbservices_get_icon_pngdata`) e nessuno dei suoi tool a riga di comando
// lo usa: questo helper colma il vuoto con un'unica sessione per tutte le app.
//
// Uso: imc-icon -u UDID -o CARTELLA BUNDLEID...
//
// Scrive CARTELLA/<bundleid>.png e stampa una riga per app su stdout:
//   OK <bundleid>
//   ERR <bundleid> <motivo>
// Esce con 1 se il dispositivo o il servizio non sono raggiungibili, 2 per
// argomenti non validi.

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/sbservices.h>

static void usage(void) {
    fprintf(stderr, "Uso: imc-icon -u UDID -o CARTELLA BUNDLEID...\n");
}

// I bundle ID arrivano dal dispositivo ma diventano nomi di file: si scartano
// quelli che potrebbero uscire dalla cartella di destinazione.
static int is_safe_bundle_id(const char *bundle_id) {
    return bundle_id[0] != '\0' && bundle_id[0] != '.' && strchr(bundle_id, '/') == NULL;
}

static int write_file(const char *path, const char *data, uint64_t size) {
    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        return 0;
    }
    size_t written = fwrite(data, 1, (size_t)size, file);
    int closed = fclose(file) == 0;
    return written == size && closed;
}

int main(int argc, char **argv) {
    const char *udid = NULL;
    const char *output_dir = NULL;
    int option;

    while ((option = getopt(argc, argv, "u:o:h")) != -1) {
        switch (option) {
        case 'u':
            udid = optarg;
            break;
        case 'o':
            output_dir = optarg;
            break;
        default:
            usage();
            return 2;
        }
    }
    if (udid == NULL || output_dir == NULL || optind >= argc) {
        usage();
        return 2;
    }

    idevice_t device = NULL;
    if (idevice_new_with_options(&device, udid, IDEVICE_LOOKUP_USBMUX) != IDEVICE_E_SUCCESS) {
        fprintf(stderr, "Dispositivo %s non trovato.\n", udid);
        return 1;
    }

    sbservices_client_t springboard = NULL;
    sbservices_error_t error = sbservices_client_start_service(device, &springboard, "imc-icon");
    if (error != SBSERVICES_E_SUCCESS) {
        fprintf(stderr, "Impossibile avviare il servizio SpringBoard (errore %d).\n", error);
        idevice_free(device);
        return 1;
    }

    for (int index = optind; index < argc; index++) {
        const char *bundle_id = argv[index];
        if (!is_safe_bundle_id(bundle_id)) {
            printf("ERR %s nome-non-valido\n", bundle_id);
            continue;
        }

        char *png = NULL;
        uint64_t size = 0;
        error = sbservices_get_icon_pngdata(springboard, bundle_id, &png, &size);
        if (error != SBSERVICES_E_SUCCESS || png == NULL || size == 0) {
            printf("ERR %s servizio-%d\n", bundle_id, error);
        } else {
            char path[PATH_MAX];
            int length = snprintf(path, sizeof path, "%s/%s.png", output_dir, bundle_id);
            if (length < 0 || length >= (int)sizeof path) {
                printf("ERR %s percorso-troppo-lungo\n", bundle_id);
            } else if (write_file(path, png, size)) {
                printf("OK %s\n", bundle_id);
            } else {
                printf("ERR %s scrittura\n", bundle_id);
            }
        }
        free(png);
        fflush(stdout);
    }

    sbservices_client_free(springboard);
    idevice_free(device);
    return 0;
}
