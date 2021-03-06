/*
 * Copyright 2017 Two Pore Guys, Inc.
 * All rights reserved
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted providing that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
 * IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 */

/**
 * @example fd-client.c
 *
 * An example that shows how to receive a file descriptor over librpc
 * connection.
 */

#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <rpc/object.h>
#include <rpc/client.h>

int
main(int argc, const char *argv[])
{
	rpc_client_t client;
	rpc_connection_t conn;
	rpc_object_t result;
	int fds[2];

	if (argc < 2) {
		fprintf(stderr, "Usage: fd-client <server socket URI>\n");
		return (1);
	}

	client = rpc_client_create(argv[1], 0);
	if (client == NULL) {
		fprintf(stderr, "cannot connect: %s\n", strerror(errno));
		return (1);
	}

	if (pipe(fds) != 0) {
		fprintf(stderr, "cannot create pipe: %s\n", strerror(errno));
		return (1);
	}

	conn = rpc_client_get_connection(client);
	result = rpc_connection_call_sync(conn, NULL, NULL, "write_to_pipe",
	    rpc_fd_create(fds[1]), NULL);
	printf("result = %s\n", rpc_string_get_string_ptr(result));
	rpc_release(result);

	close(fds[1]);

	for (;;) {
		char buf[1024];
		ssize_t ret;

		ret = read(fds[0], buf, sizeof(buf));
		if (ret <= 0)
			break;

		printf("%.*s", (int)ret, buf);
	}

	rpc_client_close(client);
	return (0);
}
