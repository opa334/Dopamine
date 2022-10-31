//
//  print.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include <stdio.h>
#include <stdbool.h>
#include <stdarg.h>
#include <unistd.h>
#include <stdint.h>

void printf_putchar(char ch) {
    write(STDOUT_FILENO, &ch, sizeof(ch));
}

int vprintf(const char * __restrict format, va_list vl) {
    bool special = false;
    
    while (*format) {
        if (special) {
            switch (*format) {
                case 'x':
                case 'p': {
                    // Pointer
                    printf_putchar('0');
                    printf_putchar('x');
                    
                    uintptr_t ptr = va_arg(vl, uintptr_t);
                    bool didWrite = false;
                    for (int i = 7; i >= 0; i--) {
                        uint8_t cur = (ptr >> (i * 8)) & 0xFF;
                        char first = cur >> 4;
                        if (first >= 0 && first <= 9) {
                            first = first + '0';
                        } else {
                            first = (first - 0xA) + 'A';
                        }
                        
                        char second = cur & 0xF;
                        if (second >= 0 && second <= 9) {
                            second = second + '0';
                        } else {
                            second = (second - 0xA) + 'A';
                        }
                        
                        if (didWrite || cur) {
                            if (didWrite || first != '0') {
                                printf_putchar(first);
                            }
                            
                            printf_putchar(second);
                            didWrite = true;
                        }
                    }
                    
                    if (!didWrite) {
                        printf_putchar('0');
                    }
                    break;
                }
                    
                case 's': {
                    const char *str = va_arg(vl, const char*);
                    if (str == NULL) {
                        str = "<NULL>";
                    }
                    
                    while (*str) {
                        printf_putchar(*str++);
                    }
                    break;
                }
                    
                case 'c':
                    printf_putchar(va_arg(vl, int));
                    break;
                    
                case 'l':
                    // Prefix, ignore
                    format++;
                    continue;
                    
                case '%':
                    printf_putchar(*format);
                    break;
                    
                default:
                    printf_putchar('%');
                    printf_putchar(*format);
                    break;
            }
            
            special = false;
        } else {
            if (*format == '%') {
                special = true;
            } else {
                printf_putchar(*format);
            }
        }
        
        format++;
    }
    
    return 0; // Not up to spec, but who uses the return value of (v)printf anyway?
}

int printf(const char * __restrict format, ...) {
    va_list vl;
    va_start(vl, format);
    
    int res = vprintf(format, vl);
    
    va_end(vl);
    
    return res;
}

#pragma clang optimize off

int puts(const char *str) {
    return printf("%s\n", str);
}

#pragma clang optimize on
