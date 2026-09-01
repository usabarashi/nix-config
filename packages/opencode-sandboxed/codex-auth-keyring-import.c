#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void zero_memory(void *buffer, size_t length) {
  volatile unsigned char *bytes = buffer;
  while (length-- > 0) {
    *bytes++ = 0;
  }
}

static void print_osstatus(const char *operation, OSStatus status) {
  CFStringRef message = SecCopyErrorMessageString(status, NULL);
  if (message == NULL) {
    fprintf(stderr, "%s failed with OSStatus %d\n", operation, (int)status);
    return;
  }

  char buffer[512];
  if (CFStringGetCString(message, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
    fprintf(stderr, "%s failed: %s\n", operation, buffer);
  } else {
    fprintf(stderr, "%s failed with OSStatus %d\n", operation, (int)status);
  }
  CFRelease(message);
}

static unsigned char *read_stdin(size_t *length) {
  const size_t maximum = 16 * 1024 * 1024;
  size_t capacity = 4096;
  size_t used = 0;
  unsigned char *buffer = malloc(capacity);
  if (buffer == NULL) {
    return NULL;
  }

  for (;;) {
    if (used == capacity) {
      if (capacity >= maximum) {
        zero_memory(buffer, used);
        free(buffer);
        errno = EFBIG;
        return NULL;
      }
      size_t next_capacity = capacity * 2;
      unsigned char *next = realloc(buffer, next_capacity);
      if (next == NULL) {
        zero_memory(buffer, used);
        free(buffer);
        return NULL;
      }
      buffer = next;
      capacity = next_capacity;
    }

    ssize_t count = read(STDIN_FILENO, buffer + used, capacity - used);
    if (count > 0) {
      used += (size_t)count;
      continue;
    }
    if (count == 0) {
      break;
    }
    if (errno != EINTR) {
      zero_memory(buffer, used);
      free(buffer);
      return NULL;
    }
  }

  *length = used;
  return buffer;
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: %s SERVICE ACCOUNT TRUSTED_APPLICATION\n", argv[0]);
    return 2;
  }

  size_t password_length = 0;
  unsigned char *password = read_stdin(&password_length);
  if (password == NULL || password_length == 0) {
    fprintf(stderr, "failed to read credential from stdin\n");
    free(password);
    return 1;
  }

  SecTrustedApplicationRef trusted_application = NULL;
  OSStatus status = SecTrustedApplicationCreateFromPath(argv[3], &trusted_application);
  if (status != errSecSuccess) {
    print_osstatus("SecTrustedApplicationCreateFromPath", status);
    zero_memory(password, password_length);
    free(password);
    return 1;
  }

  const void *trusted_values[] = {trusted_application};
  CFArrayRef trusted_applications = CFArrayCreate(
      kCFAllocatorDefault, trusted_values, 1, &kCFTypeArrayCallBacks);
  CFStringRef label = CFStringCreateWithCString(
      kCFAllocatorDefault, argv[1], kCFStringEncodingUTF8);
  SecAccessRef access = NULL;
  status = SecAccessCreate(label, trusted_applications, &access);
  if (status != errSecSuccess) {
    print_osstatus("SecAccessCreate", status);
    CFRelease(label);
    CFRelease(trusted_applications);
    CFRelease(trusted_application);
    zero_memory(password, password_length);
    free(password);
    return 1;
  }

  SecKeychainAttribute attributes[] = {
      {kSecServiceItemAttr, (UInt32)strlen(argv[1]), argv[1]},
      {kSecAccountItemAttr, (UInt32)strlen(argv[2]), argv[2]},
  };
  SecKeychainAttributeList attribute_list = {2, attributes};
  SecKeychainItemRef item = NULL;
  status = SecKeychainItemCreateFromContent(
      kSecGenericPasswordItemClass, &attribute_list, (UInt32)password_length,
      password, NULL, access, &item);

  zero_memory(password, password_length);
  free(password);
  if (item != NULL) {
    CFRelease(item);
  }
  CFRelease(access);
  CFRelease(label);
  CFRelease(trusted_applications);
  CFRelease(trusted_application);

  if (status != errSecSuccess) {
    print_osstatus("SecKeychainItemCreateFromContent", status);
    return 1;
  }
  return 0;
}
