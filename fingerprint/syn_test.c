// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 * syn_test: drive the Synaptics sensor with syn.h from a Linux host (needs write access to its usbfs node,
 * e.g. root, or docker run --device /dev/bus/usb/BBB/DDD).
 *
 *   syn_test probe   find the sensor, read its version, FPS_INIT, power down. Touches no template.
 *   syn_test cycle   enroll a throw-away template "GBOS-TEST-<random>" (touch the sensor 8+ times), identify
 *                    it (touch once), then delete it. Only that template is created and deleted.
 *   syn_test cancel  what Android's Settings does on its "touch the sensor" screen: start an enroll, cancel it at
 *                    the first touch (expects -ECANCELED), then close and reopen the sensor (it must answer).
 *                    Nothing is stored: a cancelled enroll leaves no template.
 *
 * Unlike gbos_fp the sensor is not reset (it may be in use by the host's fprintd).
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/random.h>
#include <unistd.h>

#define SYN_ERRNO errno
#define SYN_LOGI(...) (fprintf(stderr, "I: " __VA_ARGS__), fputc('\n', stderr))
#define SYN_LOGW(...) (fprintf(stderr, "W: " __VA_ARGS__), fputc('\n', stderr))
#define SYN_LOGE(...) (fprintf(stderr, "E: " __VA_ARGS__), fputc('\n', stderr))
#include "syn.h"

static bool cancel_at_capture;

static void on_event(void *ctx, int kind, int value)
{
	if (kind == SYN_EV_CAPTURE && cancel_at_capture) {
		printf("  capture: cancelling\n");
		syn_request_cancel(ctx);
	} else if (kind == SYN_EV_CAPTURE)
		printf("  capture\n");
	else if (kind == SYN_EV_RETRY)
		printf("  retry (lift and touch again)\n");
	else
		printf("  enroll stage %d/%d\n", value, SYN_ENROLL_STAGES);
	fflush(stdout);
}

int main(int argc, char **argv)
{
	const char *mode = argc > 1 ? argv[1] : "probe";
	struct syn s;
	struct syn_ev ev = { on_event, &s };
	char name[48], matched[SYN_MAX_UID + 1];
	const char *list[1] = { name };
	uint32_t rnd;
	int r, fail = 0;

	syn_init(&s);
	s.was_reset = true;
	if ((r = syn_open(&s)) < 0) {
		printf("SYN_TEST_FAIL open: %d (%s)\n", r, strerror(-r));
		return 1;
	}
	printf("sensor %s 06cb:%04x firmware %d.%d build %u product %d serial %02x%02x%02x%02x%02x%02x\n",
	       s.path, s.pid, s.ver.major, s.ver.minor, s.ver.build_num, s.ver.product, s.ver.serial[0],
	       s.ver.serial[1], s.ver.serial[2], s.ver.serial[3], s.ver.serial[4], s.ver.serial[5]);
	if (strcmp(mode, "cancel") == 0) {
		cancel_at_capture = true;
		printf("enrolling GBOS-TEST-CANCEL: touch the sensor once\n");
		fflush(stdout);
		r = syn_enroll(&s, "GBOS-TEST-CANCEL", &ev, &fail);
		printf("enroll returned %d, sensor code %d (want %d = cancelled)\n", r, fail, -ECANCELED);
		r = r == -ECANCELED ? SYN_OK : -EPROTO;
		syn_close(&s);
		if (r == SYN_OK && (r = syn_open(&s)) < 0)
			printf("SYN_TEST_FAIL sensor does not answer after the cancel: %d\n", r);
		else if (r == SYN_OK)
			printf("sensor answers again after the cancel\n");
	} else if (strcmp(mode, "cycle") == 0) {
		if (getrandom(&rnd, sizeof(rnd), 0) != sizeof(rnd))
			rnd = (uint32_t)getpid();
		snprintf(name, sizeof(name), "GBOS-TEST-%08x", rnd);
		printf("enrolling %s: touch the sensor repeatedly\n", name);
		fflush(stdout);
		r = syn_enroll(&s, name, &ev, &fail);
		if (r != SYN_OK) {
			printf("SYN_TEST_FAIL enroll: %d (sensor code %d)\n", r, fail);
			syn_close(&s);
			return 1;
		}
		printf("enrolled; touch the sensor once to identify\n");
		fflush(stdout);
		do
			r = syn_identify(&s, list, 1, &ev, matched, &fail);
		while (r == SYN_RETRY);
		printf("identify: %s%s\n", r == SYN_OK ? "match " : r == SYN_NOMATCH ? "no match" : "error",
		       r == SYN_OK ? matched : "");
		if (r == SYN_OK && strcmp(matched, name) != 0)
			r = -EPROTO;
		{
			int d = syn_delete(&s, name, &fail);

			printf("delete %s: %d\n", name, d);
			if (d != SYN_OK)
				r = -EIO;
		}
	}
	syn_close(&s);
	if (r == SYN_OK)
		printf("SYN_TEST_PASS\n");
	else
		printf("SYN_TEST_FAIL %d\n", r);
	return r == SYN_OK ? 0 : 1;
}
