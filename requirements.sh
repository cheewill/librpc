#!/bin/bash

case "`uname -s`" in
    Darwin*)
	if [ -x /usr/local/bin/brew ]; then
        	echo "I am a Mac.  Brew installing stuff."
        	echo "Don't worry about warnings of things already installed."
        	brew install glib libsoup yajl libusb libyaml yajl python3 cmake
        	pip3 install cython
	elif [ -x /opt/local/bin/port ]; then
        	echo "I am a Mac.  Using macports to install stuff with sudo"
        	sudo port install glib2 libsoup yajl libusb libyaml yajl python36 cmake lcov
        	sudo pip-3.6 install cython
	else
		echo "I am a Mac but you have neither macports or brew installed."
		exit 1
	fi
        ;;
    Linux*)
        echo "I am some kind of Linux, hopefully Ubuntu."
        apt-get -y install \
            cmake clang libglib2.0-dev libsoup-gnome2.4-dev \
            libyajl-dev libblocksruntime-dev libyaml-dev libudev-dev \
            libusb-1.0-0-dev python3 cython3 python3-sphinx \
	        python3-setuptools
        ;;
    default)
        echo "Don't know how to set up for your OS."
        exit 1
esac
