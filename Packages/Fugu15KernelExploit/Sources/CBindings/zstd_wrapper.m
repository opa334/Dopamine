//
//  zstd_wrapper.m
//  
//
//  Created by Lars Fröder on 23.04.23.
//

#import <Foundation/Foundation.h>
#import <zstd.h>

#define BUFFER_SIZE 8192

int decompress_tar_zstd(const char* src_file_path, const char* dst_file_path) {
    // Open the input file for reading
    FILE *input_file = fopen(src_file_path, "rb");
    if (input_file == NULL) {
        NSLog(@"Failed to open input file %s: %s", src_file_path, strerror(errno));
        return 40;
    }

    // Open the output file for writing
    FILE *output_file = fopen(dst_file_path, "wb");
    if (output_file == NULL) {
        NSLog(@"Failed to open output file %s: %s", dst_file_path, strerror(errno));
        fclose(input_file);
        return 41;
    }

    // Create a ZSTD decompression context
    ZSTD_DCtx *dctx = ZSTD_createDCtx();
    if (dctx == NULL) {
        NSLog(@"Failed to create ZSTD decompression context");
        fclose(input_file);
        fclose(output_file);
        return 42;
    }

    // Create a buffer for reading input data
    uint8_t *input_buffer = (uint8_t *) malloc(BUFFER_SIZE);
    if (input_buffer == NULL) {
        NSLog(@"Failed to allocate input buffer");
        ZSTD_freeDCtx(dctx);
        fclose(input_file);
        fclose(output_file);
        return 43;
    }

    // Create a buffer for writing output data
    uint8_t *output_buffer = (uint8_t *) malloc(BUFFER_SIZE);
    if (output_buffer == NULL) {
        NSLog(@"Failed to allocate output buffer");
        free(input_buffer);
        ZSTD_freeDCtx(dctx);
        fclose(input_file);
        fclose(output_file);
        return 44;
    }

    // Create a ZSTD decompression stream
    ZSTD_inBuffer in = {0};
    ZSTD_outBuffer out = {0};
    ZSTD_DStream *dstream = ZSTD_createDStream();
    if (dstream == NULL) {
        NSLog(@"Failed to create ZSTD decompression stream");
        free(output_buffer);
        free(input_buffer);
        ZSTD_freeDCtx(dctx);
        fclose(input_file);
        fclose(output_file);
        return 45;
    }

    // Initialize the ZSTD decompression stream
    size_t ret = ZSTD_initDStream(dstream);
    if (ZSTD_isError(ret)) {
        NSLog(@"Failed to initialize ZSTD decompression stream: %s", ZSTD_getErrorName(ret));
        ZSTD_freeDStream(dstream);
        free(output_buffer);
        free(input_buffer);
        ZSTD_freeDCtx(dctx);
        fclose(input_file);
        fclose(output_file);
        return 46;
    }
    
    // Read and decompress the input file
    size_t total_bytes_read = 0;
    size_t total_bytes_written = 0;
    size_t bytes_read;
    size_t bytes_written;
    while (1) {
        // Read input data into the input buffer
        bytes_read = fread(input_buffer, 1, BUFFER_SIZE, input_file);
        if (bytes_read == 0) {
            if (feof(input_file)) {
                // End of input file reached, break out of loop
                break;
            } else {
                NSLog(@"Failed to read input file: %s", strerror(errno));
                ZSTD_freeDStream(dstream);
                free(output_buffer);
                free(input_buffer);
                ZSTD_freeDCtx(dctx);
                fclose(input_file);
                fclose(output_file);
                return 47;
            }
        }

        in.src = input_buffer;
        in.size = bytes_read;
        in.pos = 0;

        while (in.pos < in.size) {
            // Initialize the output buffer
            out.dst = output_buffer;
            out.size = BUFFER_SIZE;
            out.pos = 0;

            // Decompress the input data
            ret = ZSTD_decompressStream(dstream, &out, &in);
            if (ZSTD_isError(ret)) {
                NSLog(@"Failed to decompress input data: %s", ZSTD_getErrorName(ret));
                ZSTD_freeDStream(dstream);
                free(output_buffer);
                free(input_buffer);
                ZSTD_freeDCtx(dctx);
                fclose(input_file);
                fclose(output_file);
                return 48;
            }

            // Write the decompressed data to the output file
            bytes_written = fwrite(output_buffer, 1, out.pos, output_file);
            if (bytes_written != out.pos) {
                NSLog(@"Failed to write output file: %s", strerror(errno));
                ZSTD_freeDStream(dstream);
                free(output_buffer);
                free(input_buffer);
                ZSTD_freeDCtx(dctx);
                fclose(input_file);
                fclose(output_file);
                return 49;
            }

            total_bytes_written += bytes_written;
        }

        total_bytes_read += bytes_read;
    }

    NSLog(@"Decompressed %lu bytes from %s to %lu bytes in %s", total_bytes_read, src_file_path, total_bytes_written, dst_file_path);

    // Clean up resources
    ZSTD_freeDStream(dstream);
    free(output_buffer);
    free(input_buffer);
    ZSTD_freeDCtx(dctx);
    fclose(input_file);
    fclose(output_file);

    return 0;
}
