#
# Copyright 2017 Two Pore Guys, Inc.
# All rights reserved
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted providing that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES LOSS OF USE, DATA, OR PROFITS OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

import argparse
import librpc
import signal
import time


def hello(string):
    return f'Hello {string}'


def adder(n1, n2):
    return n1 + n2


def subtracter(n1, n2):
    return n1 - n2


def streamer():
    for i in range(0, 10):
        time.sleep(0.1)
        yield {'index': i}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--uri', help='Server URI')
    args = parser.parse_args()
    context = librpc.Context()
    server = librpc.Server(args.uri, context)

    context.register_method('hello', 'Classic hello world', hello)
    context.register_method('add', 'Adds two numbers', adder)
    context.register_method('sub', 'Subtracts two numbers', subtracter)
    context.register_method('stream', 'Streams some numbers', streamer)

    signal.pause()


if __name__ == '__main__':
    main()