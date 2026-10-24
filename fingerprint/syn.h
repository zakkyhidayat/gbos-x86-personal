// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 * syn.h: Synaptics match-on-chip USB fingerprint sensors (06cb:00f9 in the ThinkPad X13 Gen 2i, and the
 * rest of libfprint's synaptics id table) over usbfs. Used by gbos_fp.c (Android) and syn_test.c (host).
 *
 * A port of libfprint's synaptics driver (libfprint/drivers/synaptics/, Copyright (C) 2019 Synaptics Inc,
 * LGPL-2.1-or-later): the same BMKT messages, endpoints, sequence numbers and command state machine
 * (send -> reply on EP 0x81 -> wait on the interrupt EP 0x83 -> ASYNCMSG_READ -> reply ...), written as
 * blocking usbfs calls instead of GLib/GUsb. Templates live on the sensor and are matched there; the host
 * only gives each one a name (the "user id", <= 100 bytes) and later asks "which of these names is this
 * finger?". Nothing here lists, overwrites or clears templates it was not given by name, so other users
 * of the sensor (fprintd on another OS on the same laptop) keep theirs.
 *
 * The interrupt EP is read the way libfprint reads it: one transfer with no timeout, left submitted while
 * the sensor works (an async URB, polled). A blocking read with a timeout would kill and resubmit the URB
 * every time, and a "message pending" report arriving in that window is lost, leaving the command hanging.
 *
 * All USB I/O happens on one thread. syn_request_cancel() may be called from any thread: it only sets a
 * flag, which the I/O thread turns into BMKT_CMD_CANCEL_OP the next time it waits on the interrupt EP
 * (it wakes every 250 ms), exactly where libfprint cancels.
 *
 * The includer provides: memcpy, memset, strlen, snprintf, open, close, read, ioctl, poll, struct pollfd,
 * POLLOUT, SYN_ERRNO (the current errno value), SYN_LOGI/SYN_LOGW/SYN_LOGE (printf-style) and the O_ and
 * E constants used below.
 */
#ifndef GBOS_SYN_H
#define GBOS_SYN_H

/* ---- usbfs (linux/usbdevice_fs.h, x86_64) ---- */
struct syn_usb_bulk { unsigned int ep, len, timeout; void *data; };
#define SYN_USBDEVFS_BULK		0xc0185502	/* _IOWR('U', 2, struct usbdevfs_bulktransfer) */
#define SYN_USBDEVFS_CLAIMINTERFACE	0x8004550f	/* _IOR('U', 15, unsigned int) */
#define SYN_USBDEVFS_RELEASEINTERFACE	0x80045510	/* _IOR('U', 16, unsigned int) */
#define SYN_USBDEVFS_RESET		0x5514		/* _IO('U', 20) */
struct syn_usb_urb {	/* struct usbdevfs_urb without iso descriptors */
	unsigned char type, endpoint;
	int status;
	unsigned int flags;
	void *buffer;
	int buffer_length, actual_length, start_frame, number_of_packets, error_count;
	unsigned int signr;
	void *usercontext;
};
_Static_assert(sizeof(struct syn_usb_urb) == 56, "usbdevfs_urb layout");
#define SYN_USBDEVFS_URB_TYPE_INTERRUPT	1
#define SYN_USBDEVFS_SUBMITURB		0x8038550a	/* _IOR('U', 10, struct usbdevfs_urb) */
#define SYN_USBDEVFS_DISCARDURB		0x550b		/* _IO('U', 11) */
#define SYN_USBDEVFS_REAPURB		0x4008550c	/* _IOW('U', 12, void *) */
#define SYN_USBDEVFS_REAPURBNDELAY	0x4008550d	/* _IOW('U', 13, void *) */

/* ---- synaptics.h ---- */
#define SYN_VID			0x06cb
#define SYN_EP_REQUEST		0x01
#define SYN_EP_REPLY		0x81
#define SYN_EP_INTERRUPT	0x83
#define SYN_MAX_TRANSFER	(263 + 1 + 2)
#define SYN_ASYNC_PENDING	0x04
#define SYN_CMD_GET_VERSION	1
#define SYN_CMD_ACE_COMMAND	167
#define SYN_CMD_ASYNCMSG_READ	168
#define SYN_REPLY_HEADER_LEN	2
#define SYN_ENROLL_STAGES	8
#define SYN_MAX_UID		100	/* BMKT_MAX_USER_ID_LEN */

/* ---- bmkt_message.h / bmkt_response.h / bmkt.h ---- */
#define BMKT_HEADER_ID			0xfe
#define BMKT_CMD_FPS_INIT		0x11
#define BMKT_CMD_CANCEL_OP		0x41
#define BMKT_CMD_ENROLL_USER		0x51
#define BMKT_CMD_DEL_USER_FP		0x81
#define BMKT_CMD_POWER_DOWN_NOTIFY	0xa1
#define BMKT_CMD_ID_USER_IN_ORDER	0xe1
#define BMKT_CMD_ID_NEXT_USER		0xe3
#define BMKT_EVT_FINGER_REPORT		0x91
#define BMKT_RSP_FPS_INIT_OK		0x13
#define BMKT_RSP_CANCEL_OP_OK		0x42
#define BMKT_RSP_CANCEL_OP_FAIL		0x43
#define BMKT_RSP_ENROLL_READY		0x54
#define BMKT_RSP_ENROLL_REPORT		0x55
#define BMKT_RSP_ENROLL_FAIL		0x58
#define BMKT_RSP_ENROLL_OK		0x59
#define BMKT_RSP_CAPTURE_COMPLETE	0x60
#define BMKT_RSP_ID_READY		0x62
#define BMKT_RSP_ID_FAIL		0x63
#define BMKT_RSP_ID_OK			0x64
#define BMKT_RSP_DEL_USER_FP_FAIL	0x82
#define BMKT_RSP_DEL_USER_FP_OK		0x83
#define BMKT_RSP_DELETE_PROGRESS	0x87
#define BMKT_RSP_POWER_DOWN_READY	0xa2
#define BMKT_RSP_POWER_DOWN_FAIL	0xa3
#define BMKT_RSP_GENERAL_ERROR		0xc1
#define BMKT_RSP_SEND_NEXT_USER_ID	0xe2
#define BMKT_FP_SYSTEM_BUSY		102
#define BMKT_OPERATION_DENIED		103
#define BMKT_SENSOR_STIMULUS_ERROR	213
#define BMKT_FP_NO_MATCH		404
#define BMKT_FP_DATABASE_FULL		501
#define BMKT_FP_DATABASE_EMPTY		502
#define BMKT_FP_DATABASE_NO_RECORD_EXISTS 504

/* syn_enroll / syn_identify / syn_delete results; negative values are -errno (-ECANCELED: cancelled). */
enum { SYN_OK = 0, SYN_NOMATCH, SYN_RETRY, SYN_NORECORD, SYN_FAILED };

/* Progress reported while an operation runs (on the I/O thread). */
enum { SYN_EV_CAPTURE, SYN_EV_RETRY, SYN_EV_PROGRESS /* value: enroll stages done, 1..7 */ };
struct syn_ev { void (*fn)(void *ctx, int kind, int value); void *ctx; };

struct syn {
	int fd;			/* -1 while closed */
	char path[32];		/* /dev/bus/usb/BBB/DDD of the sensor, once found */
	uint16_t pid;
	bool was_reset;		/* reset once per process, like libfprint's probe */
	uint8_t last_seq, cmd_seq;
	bool waiting;		/* next step is the interrupt EP (else a reply is due on EP 0x81) */
	bool finger_on;
	bool cancel_sent;
	int cancel;		/* __atomic, set by syn_request_cancel */
	struct syn_usb_urb irq_urb;	/* the interrupt transfer, while irq_busy */
	uint8_t irq_buf[8];
	bool irq_busy;
	struct {
		uint32_t build_time, build_num;
		uint8_t major, minor, target, product, silicon_rev, formal_release, platform, patch;
		uint8_t serial[6];
		uint16_t security;
		uint8_t iface, device_type;
		bool valid;
	} ver;
};

struct syn_msg { uint8_t id, seq, len; uint8_t payload[255]; int result; bool complete; };

static const uint16_t syn_pids[] = {
	0x00bd, 0x00c2, 0x00c4, 0x00c6, 0x00df, 0x00e9, 0x00f0, 0x00f9, 0x00fc, 0x0100, 0x0103, 0x0104,
	0x0106, 0x0107, 0x0108, 0x0109, 0x010a, 0x010b, 0x010d, 0x010e, 0x0123, 0x0124, 0x0126, 0x0129,
	0x015f, 0x0168, 0x0169, 0x016c, 0x0173, 0x0174, 0x019d, 0x019f, 0x01a0, 0x01a4,
};

static void syn_init(struct syn *s)
{
	memset(s, 0, sizeof(*s));
	s->fd = -1;
}

static inline void syn_request_cancel(struct syn *s) { __atomic_store_n(&s->cancel, 1, __ATOMIC_RELEASE); }
static inline void syn_clear_cancel(struct syn *s) { __atomic_store_n(&s->cancel, 0, __ATOMIC_RELEASE); }

static int syn_bulk(struct syn *s, unsigned int ep, void *buf, unsigned int len, unsigned int timeout_ms)
{
	struct syn_usb_bulk b = { ep, len, timeout_ms, buf };
	int n = ioctl(s->fd, (int)SYN_USBDEVFS_BULK, &b);

	return n < 0 ? -SYN_ERRNO : n;
}

/* Wait up to 250 ms on the interrupt EP (cmd_interrupt_cb): 1 when the sensor has a message pending, 0 when
 * not yet (the transfer stays submitted), < 0 on error. */
static int syn_irq_wait(struct syn *s)
{
	struct syn_usb_urb *done = NULL;
	struct pollfd p = { .fd = s->fd, .events = POLLOUT };

	if (!s->irq_busy) {
		memset(&s->irq_urb, 0, sizeof(s->irq_urb));
		s->irq_urb.type = SYN_USBDEVFS_URB_TYPE_INTERRUPT;
		s->irq_urb.endpoint = SYN_EP_INTERRUPT;
		s->irq_urb.buffer = s->irq_buf;
		s->irq_urb.buffer_length = 7;	/* USB_INTERRUPT_DATA_SIZE */
		if (ioctl(s->fd, (int)SYN_USBDEVFS_SUBMITURB, &s->irq_urb) < 0)
			return -SYN_ERRNO;
		s->irq_busy = true;
	}
	if (poll(&p, 1, 250) < 0 && SYN_ERRNO != EINTR)
		return -SYN_ERRNO;
	if (ioctl(s->fd, (int)SYN_USBDEVFS_REAPURBNDELAY, &done) < 0)
		return SYN_ERRNO == EAGAIN ? 0 : -SYN_ERRNO;
	s->irq_busy = false;
	if (done != &s->irq_urb)
		return -EPROTO;
	if (done->status < 0)
		return done->status;
	return done->actual_length >= 1 && (s->irq_buf[0] & SYN_ASYNC_PENDING) ? 1 : 0;
}

static void syn_irq_discard(struct syn *s)
{
	struct syn_usb_urb *done;

	if (!s->irq_busy)
		return;
	ioctl(s->fd, (int)SYN_USBDEVFS_DISCARDURB, &s->irq_urb);
	ioctl(s->fd, (int)SYN_USBDEVFS_REAPURB, &done);	/* the discarded URB comes back at once */
	s->irq_busy = false;
}

static bool syn_pid_supported(uint16_t pid)
{
	for (size_t i = 0; i < sizeof(syn_pids) / sizeof(syn_pids[0]); i++)
		if (syn_pids[i] == pid)
			return true;
	return false;
}

/* usbfs nodes start with the 18-byte device descriptor: checking them needs no sysfs access. */
static bool syn_probe_node(const char *path, uint16_t *pid)
{
	uint8_t d[18];
	int fd = open(path, O_RDONLY | O_CLOEXEC), n;

	if (fd < 0)
		return false;
	n = (int)read(fd, d, sizeof(d));
	close(fd);
	if (n < 18 || d[1] != 1 || (d[8] | d[9] << 8) != SYN_VID || !syn_pid_supported(d[10] | d[11] << 8))
		return false;
	*pid = d[10] | d[11] << 8;
	return true;
}

static int syn_find(struct syn *s)
{
	if (s->path[0] && syn_probe_node(s->path, &s->pid))
		return 0;
	for (int bus = 1; bus <= 32; bus++)
		for (int dev = 1; dev <= 127; dev++) {
			snprintf(s->path, sizeof(s->path), "/dev/bus/usb/%03d/%03d", bus, dev);
			if (syn_probe_node(s->path, &s->pid))
				return 0;
		}
	s->path[0] = 0;
	return -ENODEV;
}

/* One ACE command: 0xa7, then the BMKT message FE <seq> <id> <len> <payload>. seq 0 starts a command,
 * a positive seq continues the current one, -1 is the out-of-band cancel (libfprint's numbering). */
static int syn_send(struct syn *s, int seq, uint8_t msg_id, const uint8_t *payload, uint8_t len)
{
	uint8_t buf[1 + 4 + 255];
	uint8_t real_seq;
	int n;

	if (seq <= 0) {
		s->last_seq = (uint8_t)(s->last_seq + 1);
		if (!s->last_seq)
			s->last_seq = 1;
		real_seq = s->last_seq;
		if (seq == 0)
			s->cmd_seq = real_seq;
	} else {
		real_seq = (uint8_t)seq;
		s->last_seq = real_seq;
	}
	buf[0] = SYN_CMD_ACE_COMMAND;
	buf[1] = BMKT_HEADER_ID;
	buf[2] = real_seq;
	buf[3] = msg_id;
	buf[4] = len;
	if (len)
		memcpy(buf + 5, payload, len);
	n = syn_bulk(s, SYN_EP_REQUEST, buf, 5u + len, 1000);
	if (n < 0)
		return n;
	return n == 5 + len ? 0 : -EIO;
}

static int syn_begin(struct syn *s, uint8_t msg_id, const uint8_t *payload, uint8_t len)
{
	syn_irq_discard(s);	/* a report left over from the previous command is stale */
	s->waiting = false;
	s->cancel_sent = false;
	return syn_send(s, 0, msg_id, payload, len);
}

static int syn_continue(struct syn *s, uint8_t msg_id, const uint8_t *payload, uint8_t len)
{
	s->waiting = false;
	return syn_send(s, s->cmd_seq, msg_id, payload, len);
}

/* bmkt_parse_message_payload(): which replies end a command, and the result code of the *_FAIL ones. */
static int syn_classify(struct syn_msg *m)
{
	m->result = 0;
	m->complete = false;
	switch (m->id) {
	case 0x02: case 0x09: case 0x12: case 0x22: case 0x32: case 0x35: case 0x43: case 0x58: case 0x63:
	case 0x67: case 0x79: case 0x82: case 0x85: case 0x93: case 0xa3: case 0xb3: case 0xc3: case 0xc6:
	case 0xd3: case 0xe5:
		if (m->len != 2)
			return -EPROTO;
		m->result = m->payload[0] << 8 | m->payload[1];	/* big endian, as in libfprint */
		m->complete = true;
		return 0;
	case BMKT_RSP_ENROLL_REPORT:
		return m->len == 1 ? 0 : -EPROTO;
	case BMKT_RSP_ENROLL_OK:
		m->complete = true;
		return m->len >= 1 && m->len <= SYN_MAX_UID + 1 ? 0 : -EPROTO;
	case BMKT_RSP_ID_OK: case 0x68:	/* VERIFY_OK */
		m->complete = true;
		return m->len >= 3 && m->len <= SYN_MAX_UID + 3 ? 0 : -EPROTO;
	case BMKT_RSP_FPS_INIT_OK:
		m->complete = true;
		return m->len == 1 ? 0 : -EPROTO;
	case 0x42: case 0x83: case 0x86: case 0x23: case 0x33: case 0x36: case 0x76: case 0x77: case 0x78:
	case 0xa2: case 0xb2:
		m->complete = true;
		return 0;
	default:
		return 0;
	}
}

static int syn_recv(struct syn *s, struct syn_msg *m)
{
	uint8_t buf[SYN_MAX_TRANSFER];
	int n = syn_bulk(s, SYN_EP_REPLY, buf, sizeof(buf), 5000);
	const uint8_t *b = buf + SYN_REPLY_HEADER_LEN;

	if (n < 0)
		return n;
	n -= SYN_REPLY_HEADER_LEN;
	if (n < 4 || b[0] != BMKT_HEADER_ID || b[3] > n - 4) {
		SYN_LOGW("corrupted message from the sensor (%d bytes)", n);
		return -EPROTO;
	}
	m->seq = b[1];
	m->id = b[2];
	m->len = b[3];
	memcpy(m->payload, b + 4, m->len);
	return syn_classify(m);
}

/* The next reply of the running command (cmd_receive_cb + the interrupt states of synaptics_cmd_run_state).
 * Finger on/off reports are returned too (id BMKT_EVT_FINGER_REPORT) so callers can wait for removal. */
static int syn_next(struct syn *s, struct syn_msg *m)
{
	int n;

	for (;;) {
		if (s->waiting) {
			uint8_t c = SYN_CMD_ASYNCMSG_READ;

			if (!s->cancel_sent && __atomic_load_n(&s->cancel, __ATOMIC_ACQUIRE)) {
				s->cancel_sent = true;
				if ((n = syn_send(s, -1, BMKT_CMD_CANCEL_OP, NULL, 0)) < 0)
					return n;
			}
			if ((n = syn_irq_wait(s)) < 0)
				return n;
			if (n == 0)
				continue;
			if ((n = syn_bulk(s, SYN_EP_REQUEST, &c, 1, 1000)) < 0)
				return n;
			s->waiting = false;
		}
		if ((n = syn_recv(s, m)) < 0)
			return n;
		s->waiting = true;	/* unless the caller sends a follow-up (syn_continue) */
		if (m->id == BMKT_EVT_FINGER_REPORT) {
			if (m->len != 1)
				return -EPROTO;
			s->finger_on = m->payload[0] == 1;
		}
		if (m->id == BMKT_RSP_CANCEL_OP_OK)
			return -ECANCELED;
		if (m->id == BMKT_RSP_CANCEL_OP_FAIL)	/* nothing left to cancel (e.g. waiting for removal) */
			return s->cancel_sent ? -ECANCELED : -EPROTO;
		if (m->seq == 0) {
			if (m->id == BMKT_RSP_GENERAL_ERROR) {
				SYN_LOGE("sensor general error %d", m->len >= 2 ? m->payload[0] << 8 | m->payload[1] : -1);
				return -EIO;
			}
			if (m->id == BMKT_EVT_FINGER_REPORT)
				return 0;
			continue;
		}
		if (m->seq != s->cmd_seq && m->seq != s->last_seq)
			SYN_LOGW("unexpected sequence number %d (expected %d)", m->seq, s->cmd_seq);
		return 0;
	}
}

/* Run a command that has no follow-ups until its final reply. */
static int syn_simple(struct syn *s, uint8_t msg_id, const uint8_t *payload, uint8_t len, struct syn_msg *m)
{
	int r = syn_begin(s, msg_id, payload, len);

	while (r == 0) {
		if ((r = syn_next(s, m)) < 0)
			break;
		if (m->complete)
			return 0;
	}
	return r;
}

static int syn_get_version(struct syn *s)
{
	uint8_t c = SYN_CMD_GET_VERSION, b[40];
	int n;

	for (int attempt = 0; attempt < 2; attempt++) {
		if ((n = syn_bulk(s, SYN_EP_REQUEST, &c, 1, 1000)) < 0)
			return n;
		if ((n = syn_bulk(s, SYN_EP_REPLY, b, sizeof(b), 1000)) < 0)
			return n;
		if (n < 2)
			return -EPROTO;
		if ((b[0] | b[1] << 8) == 0)
			break;
		SYN_LOGW("version query: status %d", b[0] | b[1] << 8);
		if (attempt)
			return -EPROTO;
	}
	if (n < 28)	/* status u16, then bmkt_sensor_version_t packed (26 bytes) */
		return -EPROTO;
	memcpy(&s->ver.build_time, b + 2, 4);
	memcpy(&s->ver.build_num, b + 6, 4);
	s->ver.major = b[10]; s->ver.minor = b[11]; s->ver.target = b[12]; s->ver.product = b[13];
	s->ver.silicon_rev = b[14]; s->ver.formal_release = b[15]; s->ver.platform = b[16]; s->ver.patch = b[17];
	memcpy(s->ver.serial, b + 18, 6);
	memcpy(&s->ver.security, b + 24, 2);
	s->ver.iface = b[26];
	s->ver.device_type = b[27];
	s->ver.valid = true;
	return 0;
}

static void syn_close(struct syn *s);

/* dev_probe() + dev_init(): find the sensor, (reset it once), claim interface 0, read its version the first
 * time, then FPS_INIT. "Already initialised" (OPERATION_DENIED) is fine; "busy" is cancelled and is fine. */
static int syn_open(struct syn *s)
{
	unsigned int iface = 0;
	struct syn_msg m;
	int r;

	if (s->fd >= 0)
		return 0;
	if ((r = syn_find(s)) < 0)
		return r;
	if ((s->fd = open(s->path, O_RDWR | O_CLOEXEC)) < 0) {
		r = -SYN_ERRNO;
		SYN_LOGE("open %s: %d", s->path, r);
		return r;
	}
	if (!s->was_reset) {
		if (ioctl(s->fd, (int)SYN_USBDEVFS_RESET, 0) < 0)
			SYN_LOGW("reset %s: %d", s->path, -SYN_ERRNO);
		s->was_reset = true;
	}
	if (ioctl(s->fd, (int)SYN_USBDEVFS_CLAIMINTERFACE, &iface) < 0) {
		r = -SYN_ERRNO;
		SYN_LOGE("claim interface: %d", r);
		close(s->fd);
		s->fd = -1;
		return r;
	}
	if (!s->ver.valid && (r = syn_get_version(s)) < 0)
		goto fail;
	r = syn_simple(s, BMKT_CMD_FPS_INIT, NULL, 0, &m);
	if (r == 0 && m.id != BMKT_RSP_FPS_INIT_OK && m.result != BMKT_OPERATION_DENIED) {
		if (m.result != BMKT_FP_SYSTEM_BUSY) {
			SYN_LOGE("FPS_INIT failed: %d", m.result);
			r = -EIO;
			goto fail;
		}
		/* fps_init_msg_cb: cancel whatever the sensor is busy with; the cancel reply ends the init. */
		if ((r = syn_continue(s, BMKT_CMD_CANCEL_OP, NULL, 0)) == 0)
			while ((r = syn_next(s, &m)) == 0 && !m.complete)
				;
		if (r == -ECANCELED)
			r = 0;
	}
	if (r < 0)
		goto fail;
	s->finger_on = false;
	return 0;
fail:
	SYN_LOGE("sensor init failed: %d", r);
	syn_close(s);
	return r;
}

static void syn_close(struct syn *s)
{
	unsigned int iface = 0;
	struct syn_msg m;

	if (s->fd < 0)
		return;
	syn_irq_discard(s);
	syn_clear_cancel(s);
	if (syn_simple(s, BMKT_CMD_POWER_DOWN_NOTIFY, NULL, 0, &m) == 0 && m.id == BMKT_RSP_POWER_DOWN_FAIL)
		SYN_LOGW("power down failed: %d", m.result);
	ioctl(s->fd, (int)SYN_USBDEVFS_RELEASEINTERFACE, &iface);
	close(s->fd);
	s->fd = -1;
}

static void syn_emit(const struct syn_ev *ev, int kind, int value)
{
	if (ev && ev->fn)
		ev->fn(ev->ctx, kind, value);
}

/* After a rejected or unreadable touch: finish the command only once the finger is lifted
 * (cmd_complete_on_removal), so one long touch is one attempt. */
static int syn_wait_removal(struct syn *s)
{
	struct syn_msg m;
	int r = 0;

	while (s->finger_on && (r = syn_next(s, &m)) == 0)
		;
	return r;
}

/* enroll(): BMKT_CMD_ENROLL_USER [backup 0, finger 1, uid]. SYN_FAILED leaves the sensor's code in *fail. */
static int syn_enroll(struct syn *s, const char *uid, const struct syn_ev *ev, int *fail)
{
	uint8_t p[2 + SYN_MAX_UID];
	size_t n = strlen(uid);
	struct syn_msg m;
	int stage = 0, r;

	if (n == 0 || n > SYN_MAX_UID || uid[0] == ' ')
		return -EINVAL;
	p[0] = 0;
	p[1] = 1;
	memcpy(p + 2, uid, n);
	if ((r = syn_begin(s, BMKT_CMD_ENROLL_USER, p, (uint8_t)(n + 2))) < 0)
		return r;
	for (;;) {
		if ((r = syn_next(s, &m)) < 0)
			return r;
		switch (m.id) {
		case BMKT_RSP_ENROLL_READY:
			stage = 0;
			break;
		case BMKT_RSP_CAPTURE_COMPLETE:
			syn_emit(ev, SYN_EV_CAPTURE, 0);
			break;
		case BMKT_RSP_ENROLL_REPORT: {
			int done = (m.payload[0] * SYN_ENROLL_STAGES + 99) / 100;

			if (m.payload[0] < 100 && done > SYN_ENROLL_STAGES - 1)
				done = SYN_ENROLL_STAGES - 1;
			if (done == stage)
				syn_emit(ev, SYN_EV_RETRY, stage);
			while (stage < done)
				syn_emit(ev, SYN_EV_PROGRESS, ++stage);
			break;
		}
		case BMKT_RSP_ENROLL_FAIL:
			*fail = m.result;
			return SYN_FAILED;
		case BMKT_RSP_ENROLL_OK:
			return SYN_OK;
		}
	}
}

/* identify(): offer exactly these names, one per message (ID_USER_IN_ORDER, then ID_NEXT_USER on request).
 * SYN_OK copies the matched name to matched[SYN_MAX_UID + 1]. */
static int syn_identify(struct syn *s, const char *const *uids, int count, const struct syn_ev *ev,
			char *matched, int *fail)
{
	uint8_t p[3 + SYN_MAX_UID];
	struct syn_msg m;
	int idx = 0, r, w;
	size_t n;

	if (count <= 0 || count > 255)
		return -EINVAL;
	for (;;) {
		if (idx >= count)
			return -EPROTO;	/* the sensor asked for more names than it was told about */
		n = strlen(uids[idx]);
		if (n == 0 || n > SYN_MAX_UID)
			return -EINVAL;
		if (idx == 0) {
			p[0] = (uint8_t)count;
			p[1] = 1;
			p[2] = (uint8_t)n;
			memcpy(p + 3, uids[0], n);
			r = syn_begin(s, BMKT_CMD_ID_USER_IN_ORDER, p, (uint8_t)(n + 3));
		} else {
			p[0] = 1;
			p[1] = (uint8_t)n;
			memcpy(p + 2, uids[idx], n);
			r = syn_continue(s, BMKT_CMD_ID_NEXT_USER, p, (uint8_t)(n + 2));
		}
		if (r < 0)
			return r;
		idx++;
		for (;;) {
			if ((r = syn_next(s, &m)) < 0)
				return r;
			if (m.id == BMKT_RSP_SEND_NEXT_USER_ID)
				break;
			if (m.id == BMKT_RSP_CAPTURE_COMPLETE) {
				syn_emit(ev, SYN_EV_CAPTURE, 0);
			} else if (m.id == BMKT_RSP_ID_OK) {
				memcpy(matched, m.payload + 3, m.len - 3u);
				matched[m.len - 3] = 0;
				return SYN_OK;
			} else if (m.id == BMKT_RSP_ID_FAIL) {
				switch (m.result) {
				case BMKT_SENSOR_STIMULUS_ERROR:
					r = SYN_RETRY;
					break;
				case BMKT_FP_NO_MATCH:
					r = SYN_NOMATCH;
					break;
				case BMKT_FP_DATABASE_NO_RECORD_EXISTS: case BMKT_FP_DATABASE_EMPTY:
					r = SYN_NORECORD;
					break;
				default:
					*fail = m.result;
					return SYN_FAILED;
				}
				if (r == SYN_RETRY)
					syn_emit(ev, SYN_EV_RETRY, 0);
				w = syn_wait_removal(s);
				return w < 0 ? w : r;
			}
		}
	}
}

/* delete_print(): BMKT_CMD_DEL_USER_FP [finger 1, uid]. A name the sensor doesn't have counts as deleted. */
static int syn_delete(struct syn *s, const char *uid, int *fail)
{
	uint8_t p[1 + SYN_MAX_UID];
	size_t n = strlen(uid);
	struct syn_msg m;
	int r;

	if (n == 0 || n > SYN_MAX_UID)
		return -EINVAL;
	p[0] = 1;
	memcpy(p + 1, uid, n);
	if ((r = syn_simple(s, BMKT_CMD_DEL_USER_FP, p, (uint8_t)(n + 1), &m)) < 0)
		return r;
	if (m.id == BMKT_RSP_DEL_USER_FP_OK)
		return SYN_OK;
	if (m.id == BMKT_RSP_DEL_USER_FP_FAIL &&
	    (m.result == BMKT_FP_DATABASE_NO_RECORD_EXISTS || m.result == BMKT_FP_DATABASE_EMPTY))
		return SYN_NORECORD;
	*fail = m.result;
	return SYN_FAILED;
}

#endif
